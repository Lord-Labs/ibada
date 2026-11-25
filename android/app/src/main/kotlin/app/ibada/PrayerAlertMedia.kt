package app.ibada

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.RingtoneManager
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.widget.ImageView
import java.io.File
import java.io.FileNotFoundException
import java.util.UUID

internal object PrayerAlertMedia {
    private const val MAX_BYTES = 25 * 1024 * 1024
    private const val MAX_IMAGE_EDGE = 1600
    private const val SOFT_LABEL = "نغمة عبادة الهادئة"
    private const val HORIZON_LABEL = "أفق المساء"
    private const val INVALID_SOUND = "اختر ملفًا صوتيًا صالحًا."
    private const val INVALID_IMAGE = "تعذّر قراءة الصورة. اختر صورة أخرى."

    private val soundPresets = mapOf(
        "adhan_medina" to "أذان المسجد النبوي",
        "adhan_classic" to "أذان آدم",
        "adhan_aasim" to "أذان عاصم جاويد",
    )
    private fun device(context: Context) = context.createDeviceProtectedStorageContext()
    private fun prefs(context: Context) = device(context).getSharedPreferences("prayer-alert-media", Context.MODE_PRIVATE)
    private fun importFile(context: Context, name: String?) =
        name?.takeIf { it.startsWith("import-") && '/' !in it }?.let { File(device(context).noBackupFilesDir, it) }

    fun status(context: Context): Map<String, Any?> {
        val saved = prefs(context)
        fun label(kind: String): String? {
            val file = importFile(context, saved.getString(kind, null))
            return if (file == null || file.isFile) saved.getString("${kind}Label", null) else null
        }
        return mapOf(
            "sound" to label("sound"), "image" to label("image"),
            "imageScope" to "fullscreen", "systemSounds" to true, "soundPreset" to false,
            "imageSupported" to true, "imagePreset" to true, "soundPresets" to soundPresets,
        )
    }

    fun select(context: Context, kind: String, preset: String?) {
        val label = when {
            preset == null -> null
            kind == "image" && preset == "horizon" -> HORIZON_LABEL
            kind == "sound" && preset == "soft" -> SOFT_LABEL
            kind == "sound" && preset in soundPresets -> soundPresets.getValue(preset)
            else -> error("خيار التنبيه غير متاح.")
        }
        save(context, kind, preset, label)
    }

    @Synchronized
    private fun save(context: Context, kind: String, name: String?, label: String?, mime: String? = null) {
        val saved = prefs(context)
        val previous = saved.getString(kind, null)
        check(saved.edit().putString(kind, name).putString("${kind}Label", label)
            .putString("${kind}Mime", mime).commit()) { "تعذّر حفظ التخصيص." }
        if (previous != name) importFile(context, previous)?.delete()
    }

    fun sound(context: Context): Pair<String, Uri> {
        val selected = prefs(context).getString("sound", null)
        if (importFile(context, selected)?.isFile == true) return "_import" to importedSoundUri(context)
        val preset = selected?.takeIf { it in soundPresets }
        val resource = preset ?: "prayer_chime"
        return (preset?.let { "_$it" } ?: "") to Uri.parse("android.resource://${context.packageName}/raw/$resource")
    }

    fun importedSoundUri(context: Context): Uri = Uri.parse("content://${context.packageName}.prayer-media/sound")

    @Synchronized
    fun openSound(context: Context): ParcelFileDescriptor {
        val file = importFile(context, prefs(context).getString("sound", null)) ?: throw FileNotFoundException()
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    fun soundMime(context: Context) = prefs(context).getString("soundMime", null) ?: "audio/*"

    fun background(context: Context): ImageView? {
        val selected = prefs(context).getString("image", null) ?: return null
        val view = ImageView(context).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
        if (selected == "horizon") {
            view.setImageResource(R.drawable.ibada_alarm_horizon)
        } else {
            val file = importFile(context, selected) ?: return null
            val bitmap = BitmapFactory.decodeFile(file.path) ?: return null
            view.setImageBitmap(bitmap)
        }
        return view
    }

    fun import(context: Context, uri: Uri, kind: String, systemTone: Boolean) {
        require(uri.scheme == "content" && uri.authority != importedSoundUri(context).authority) {
            "تعذّرت قراءة الملف المختار."
        }
        val local = device(context)
        val staged = File.createTempFile("prayer-", ".tmp", local.cacheDir)
        val destination = File(local.noBackupFilesDir, "import-${UUID.randomUUID()}")
        try {
            val input = context.contentResolver.openInputStream(uri) ?: error("تعذّرت قراءة الملف المختار.")
            input.use { source ->
                staged.outputStream().use { output ->
                    val buffer = ByteArray(32 * 1024)
                    var total = 0
                    while (true) {
                        val count = source.read(buffer)
                        if (count == -1) break
                        total += count
                        require(total <= MAX_BYTES) { "اختر ملفًا لا يتجاوز ٢٥ ميغابايت." }
                        output.write(buffer, 0, count)
                    }
                }
            }
            val mime = if (kind == "sound") {
                val type = validateSound(staged)
                check(staged.renameTo(destination)) { "تعذّر حفظ الملف الصوتي." }
                type
            } else {
                convertImage(staged, destination)
                null
            }
            val name = if (systemTone) runCatching {
                RingtoneManager.getRingtone(context, uri)?.getTitle(context)
            }.getOrNull() else null
            val fileLabel = name ?: runCatching {
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0)?.substringBeforeLast('.') else null
                }
            }.getOrNull()
            val label = fileLabel?.take(80)?.filterNot(Char::isISOControl)?.trim()?.takeIf { it.isNotEmpty() }
                ?: if (kind == "sound") "صوت من الجهاز" else "صورة من الجهاز"
            save(context, kind, destination.name, label, mime)
        } catch (error: Exception) {
            destination.delete()
            throw error
        } finally {
            staged.delete()
        }
    }

    private fun validateSound(file: File): String {
        val metadata = MediaMetadataRetriever()
        try {
            metadata.setDataSource(file.path)
            require(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes" &&
                metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes" &&
                (metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0) > 0)
            return metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: "audio/*"
        } catch (_: RuntimeException) {
            error(INVALID_SOUND)
        } finally {
            metadata.release()
        }
    }

    private fun convertImage(file: File, destination: File) {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, options)
        require(options.outWidth > 0 && options.outHeight > 0) { INVALID_IMAGE }
        var sample = 1
        while (maxOf(options.outWidth, options.outHeight).toLong() > MAX_IMAGE_EDGE.toLong() * sample) sample *= 2
        options.inSampleSize = sample
        options.inJustDecodeBounds = false
        val decoded = BitmapFactory.decodeFile(file.path, options) ?: error(INVALID_IMAGE)
        val transform = Matrix()
        val orientation = runCatching {
            ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)
        }.getOrDefault(1)
        when (orientation) {
            2 -> transform.setScale(-1f, 1f)
            3 -> transform.setRotate(180f)
            4 -> transform.setScale(1f, -1f)
            5, 6, 7, 8 -> {
                transform.setRotate(if (orientation == 7 || orientation == 8) -90f else 90f)
                if (orientation == 5 || orientation == 7) transform.postScale(-1f, 1f)
            }
        }
        val image = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, transform, true)
        try {
            destination.outputStream().use { check(image.compress(Bitmap.CompressFormat.JPEG, 85, it)) { INVALID_IMAGE } }
        } finally {
            if (image !== decoded) image.recycle()
            decoded.recycle()
        }
    }
}

// Android's ringtone player opens this stable URI each time an imported sound is used.
class PrayerSoundProvider : ContentProvider() {
    override fun onCreate() = true

    private fun checkUri(uri: Uri): Context {
        val app = requireNotNull(context)
        if (uri != PrayerAlertMedia.importedSoundUri(app)) throw FileNotFoundException()
        return app
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException()
        return PrayerAlertMedia.openSound(checkUri(uri))
    }

    override fun getType(uri: Uri) = PrayerAlertMedia.soundMime(checkUri(uri))

    override fun query(
        uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?,
    ): MatrixCursor {
        val app = checkUri(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            val row = newRow()
            for (column in columns) row.add(when (column) {
                OpenableColumns.DISPLAY_NAME -> PrayerAlertMedia.status(app)["sound"]
                OpenableColumns.SIZE -> PrayerAlertMedia.openSound(app).use { it.statSize }
                else -> null
            })
        }
    }

    override fun insert(uri: Uri, values: ContentValues?) = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) =
        throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) =
        throw UnsupportedOperationException()
}
