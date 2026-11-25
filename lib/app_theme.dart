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
    required this.sand,
    required this.sandInk,
  });

  static const light = IbadaColors(
    paper: Color(0xFFF5F6F0),
    surface: Color(0xFFFFFEF9),
    ink: Color(0xFF152C23),
    muted: Color(0xFF40594D),
    line: Color(0xFFD9E2D6),
    accent: Color(0xFF245D42),
    tint: Color(0xFFE0EEE4),
    tintInk: Color(0xFF224B34),
    sand: Color(0xFFF4E8D3),
    sandInk: Color(0xFF67481F),
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
    sand: Color(0xFF493924),
    sandInk: Color(0xFFF5DAB2),
  );
  static const pine = Color(0xFF142C25);
  static const amber = Color(0xFFF4CF90);
  static const cream = Color(0xFFFCF5E3);
  static const horizonShade = Color(0xD9142C25);
  static const pale = Color(0xFFCCDAD0);

  final Color paper, surface, ink, muted, line, accent, tint, tintInk;
  final Color sand, sandInk;

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
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
  );
  final base = ThemeData(
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
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      indicatorColor: palette.tint,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      elevation: 0,
      height: 68,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Thmanyah Sans',
          fontSize: 12,
          height: 1.2,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: palette.surface,
      indicatorColor: palette.tint,
      useIndicator: true,
      minWidth: 96,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minTileHeight: 58,
      iconColor: palette.accent,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 2),
    ),
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
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: palette.ink,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: palette.ink,
      ),
    ),
  );
}

class IbadaHeading extends StatelessWidget {
  const IbadaHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: compact ? typography.titleLarge : typography.headlineMedium,
          ),
        ),
        if (subtitle case final String description) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              color: IbadaColors.of(context).muted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

class IbadaSurface extends StatelessWidget {
  const IbadaSurface({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = IbadaColors.of(context);
    return Material(
      color: color ?? palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: palette.line),
      ),
      child: child,
    );
  }
}
