import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

@MainActor
final class PrayerAlertMedia: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  enum Kind: Equatable {
    case sound, image

    var contentType: UTType { self == .sound ? .audio : .image }
  }

  struct Choice: Codable, Equatable {
    let fileName: String
    let label: String
  }

  struct Selection: Codable, Equatable {
    var sound: Choice? = nil
    var image: Choice? = nil
  }

  enum MediaError: LocalizedError {
    case pickerUnavailable, fileTooLarge, invalidAudio, invalidImage, unknownPreset

    var errorDescription: String? {
      switch self {
      case .pickerUnavailable: return "تعذّر فتح منتقي الملفات. حاول مرة أخرى."
      case .fileTooLarge: return "الملف كبير. اختر ملفًا أصغر من ٢٥ ميغابايت."
      case .invalidAudio: return "اختر ملفًا صوتيًا صالحًا مدته أقل من ٣٠ ثانية."
      case .invalidImage: return "تعذّر قراءة الصورة. اختر صورة أخرى."
      case .unknownPreset: return "خيار التنبيه غير متاح."
      }
    }
  }

  private let files = FileManager.default
  private let defaults = UserDefaults.standard
  private let key = "ibada-alert-media"
  private weak var activePicker: UIDocumentPickerViewController?
  private var pickerResult: CheckedContinuation<URL?, Never>?

  private static let soft = Choice(fileName: "ibada-soft.wav", label: "نغمة عبادة الهادئة")
  private static let horizon = Choice(fileName: "ibada-alarm-horizon.jpg", label: "أفق المساء")
  private static let adhanPresets = [
    "adhan_medina": Choice(fileName: "adhan_medina.wav", label: "أذان المسجد النبوي"),
    "adhan_classic": Choice(fileName: "adhan_classic.wav", label: "أذان آدم"),
    "adhan_aasim": Choice(fileName: "adhan_aasim.wav", label: "أذان عاصم جاويد"),
  ]

  var selection: Selection {
    defaults.data(forKey: key)
      .flatMap { try? JSONDecoder().decode(Selection.self, from: $0) }
      ?? Selection()
  }

  func save(_ selection: Selection) throws {
    defaults.set(try JSONEncoder().encode(selection), forKey: key)
  }

  var status: [String: Any] {
    let selection = selection
    var values: [String: Any] = [
      "imageSupported": true, "imageScope": "notification", "systemSounds": false,
      "soundPreset": bundledURL(Self.soft) != nil, "imagePreset": bundledURL(Self.horizon) != nil,
      "soundPresets": Self.adhanPresets.filter { bundledURL($0.value) != nil }.mapValues(\.label),
    ]
    if let sound = selection.sound, url(for: sound, kind: .sound) != nil { values["sound"] = sound.label }
    if let image = selection.image, url(for: image, kind: .image) != nil { values["image"] = image.label }
    return values
  }

  var soundName: String? {
    guard let sound = selection.sound, url(for: sound, kind: .sound) != nil else { return nil }
    return sound.fileName
  }

  func makeAttachmentCopy() -> URL? {
    guard let image = selection.image, let source = url(for: image, kind: .image) else { return nil }
    let copy = files.temporaryDirectory.appendingPathComponent("ibada-\(UUID().uuidString).jpg")
    do {
      try files.copyItem(at: source, to: copy)
      return copy
    } catch {
      return nil
    }
  }

  func choose(_ kind: Kind) async throws -> URL? {
    guard pickerResult == nil, let presenter = frontmostController() else {
      throw MediaError.pickerUnavailable
    }

    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [kind.contentType], asCopy: true)
    picker.delegate = self
    return await withCheckedContinuation { continuation in
      pickerResult = continuation
      activePicker = picker
      presenter.present(picker, animated: true)
      picker.presentationController?.delegate = self
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishPicking(controller, url: urls.first)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPicking(controller, url: nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if let picker = presentationController.presentedViewController as? UIDocumentPickerViewController {
      finishPicking(picker, url: nil)
    }
  }

  func importFile(_ source: URL, kind: Kind) throws -> Choice {
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }

    let info = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard info.isRegularFile == true, let size = info.fileSize, size > 0 else {
      throw kind == .sound ? MediaError.invalidAudio : MediaError.invalidImage
    }
    guard size <= 25 * 1024 * 1024 else { throw MediaError.fileTooLarge }

    let directory = try storageDirectory(kind)
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileName = "ibada-\(UUID().uuidString)" + (kind == .sound ? ".caf" : ".jpg")
    let destination = directory.appendingPathComponent(fileName)
    do {
      if kind == .sound {
        try convertAudio(source, to: destination)
      } else {
        try convertImage(source, to: destination)
      }
      try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                              ofItemAtPath: destination.path)
    } catch {
      try? files.removeItem(at: destination)
      throw error
    }

    let label = String(source.deletingPathExtension().lastPathComponent.prefix(80))
    return Choice(fileName: fileName, label: label)
  }

  func preset(_ name: String?, kind: Kind) throws -> Choice {
    let choice: Choice
    switch (kind, name ?? "") {
    case (.sound, "soft"): choice = Self.soft
    case (.image, "horizon"): choice = Self.horizon
    case (.sound, let name):
      guard let adhan = Self.adhanPresets[name] else { throw MediaError.unknownPreset }
      choice = adhan
    default: throw MediaError.unknownPreset
    }
    guard bundledURL(choice) != nil else { throw MediaError.unknownPreset }
    return choice
  }

  func removeUnused(_ unused: Selection, keeping current: Selection) {
    if let sound = unused.sound, sound != current.sound { removeImport(sound, kind: .sound) }
    if let image = unused.image, image != current.image { removeImport(image, kind: .image) }
  }

  private func finishPicking(_ picker: UIDocumentPickerViewController, url: URL?) {
    guard picker === activePicker, let continuation = pickerResult else { return }
    pickerResult = nil
    activePicker = nil
    continuation.resume(returning: url)
  }

  private func frontmostController() -> UIViewController? {
    let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive && $0.windows.contains(where: \.isKeyWindow) }
    var controller = screen?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
      controller = presented
    }
    guard controller?.viewIfLoaded?.window != nil, controller?.isBeingDismissed == false else { return nil }
    return controller
  }

  private func storageDirectory(_ kind: Kind) throws -> URL {
    let library = try files.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    return library.appendingPathComponent(kind == .sound ? "Sounds" : "IbadaAlertImages", isDirectory: true)
  }

  private func bundledURL(_ choice: Choice) -> URL? {
    guard choice == Self.soft || choice == Self.horizon || Self.adhanPresets.values.contains(choice)
    else { return nil }
    return Bundle.main.url(forResource: choice.fileName, withExtension: nil)
  }

  private func importedURL(_ choice: Choice, kind: Kind) -> URL? {
    guard choice.fileName.hasPrefix("ibada-"), !choice.fileName.contains("/"),
          choice.fileName.hasSuffix(kind == .sound ? ".caf" : ".jpg"),
          let directory = try? storageDirectory(kind) else { return nil }
    return directory.appendingPathComponent(choice.fileName)
  }

  private func url(for choice: Choice, kind: Kind) -> URL? {
    if let bundled = bundledURL(choice) { return bundled }
    guard let file = importedURL(choice, kind: kind), files.fileExists(atPath: file.path) else { return nil }
    return file
  }

  private func removeImport(_ choice: Choice, kind: Kind) {
    guard let file = importedURL(choice, kind: kind) else { return }
    try? files.removeItem(at: file)
  }

  private func convertAudio(_ source: URL, to destination: URL) throws {
    do {
      let input = try AVAudioFile(forReading: source)
      let format = input.processingFormat
      let frames = input.length
      guard format.sampleRate.isFinite, (8_000.0...96_000.0).contains(format.sampleRate),
            format.channelCount == 1 || format.channelCount == 2, frames > 0,
            Double(frames) < format.sampleRate * 30,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
        throw MediaError.invalidAudio
      }

      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
      ]
      let output = try AVAudioFile(forWriting: destination, settings: settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
      while input.framePosition < frames {
        try input.read(into: buffer)
        guard buffer.frameLength > 0 else { break }
        guard Double(output.framePosition + AVAudioFramePosition(buffer.frameLength)) < format.sampleRate * 30 else {
          throw MediaError.invalidAudio
        }
        try output.write(from: buffer)
      }
      guard output.framePosition > 0 else { throw MediaError.invalidAudio }
    } catch {
      throw MediaError.invalidAudio
    }
  }

  private func convertImage(_ source: URL, to destination: URL) throws {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1_080,
    ]
    guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary),
          let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.78) else {
      throw MediaError.invalidImage
    }
    try data.write(to: destination, options: .atomic)
  }
}
