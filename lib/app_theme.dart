import 'package:material_ui/material_ui.dart';

class IbadaColors {
  const IbadaColors({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.tint,
    required this.tintInk,
  });

  static const light = IbadaColors(
    paper: Color(0xFFF6F5ED),
    surface: Color(0xFFFFFDF6),
    ink: Color(0xFF172C23),
    muted: Color(0xFF486052),
    line: Color(0xFFD9E2D5),
    accent: Color(0xFF245D42),
    tint: Color(0xFFE6EFE1),
    tintInk: Color(0xFF244A35),
  );
  static const dark = IbadaColors(
    paper: Color(0xFF101A17),
    surface: Color(0xFF1C2A23),
    ink: Color(0xFFF4F1E5),
    muted: Color(0xFFB0BDB1),
    line: Color(0xFF405247),
    accent: Color(0xFFB6DDBE),
    tint: Color(0xFF283D33),
    tintInk: Color(0xFFD8EBDC),
  );
  static const pine = Color(0xFF142C25);
  static const amber = Color(0xFFF4CF90);
  static const cream = Color(0xFFFCF5E3);
  static const pale = Color(0xFFCCDAD0);

  final Color paper, surface, ink, muted, line, accent, tint, tintInk;

  static IbadaColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData ibadaTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? IbadaColors.dark
      : IbadaColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ).copyWith(
        primary: palette.accent,
        onPrimary: brightness == Brightness.dark
            ? IbadaColors.pine
            : Colors.white,
        surface: palette.surface,
        primaryContainer: palette.tint,
        onPrimaryContainer: palette.tintInk,
        onSurface: palette.ink,
        onSurfaceVariant: palette.muted,
        outlineVariant: palette.line,
        secondaryContainer: palette.tint,
        onSecondaryContainer: palette.tintInk,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Thmanyah Sans',
    scaffoldBackgroundColor: palette.paper,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerColor: palette.line,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.paper,
      foregroundColor: palette.ink,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.paper,
      indicatorColor: palette.tint,
      elevation: 0,
      height: 68,
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: palette.surface),
    listTileTheme: const ListTileThemeData(minTileHeight: 56),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.line),
      ),
    ),
  );
}
