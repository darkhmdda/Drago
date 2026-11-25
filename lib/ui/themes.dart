import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colores con significado financiero. Cada tema define los suyos para que
/// ingresos, gastos, pendientes y pagados se distingan siempre.
@immutable
class FinPalette extends ThemeExtension<FinPalette> {
  final Color income;
  final Color expense;
  final Color pending;
  final Color paid;
  final Color neutral;

  const FinPalette({required this.income, required this.expense, required this.pending, required this.paid, required this.neutral});

  @override
  FinPalette copyWith({Color? income, Color? expense, Color? pending, Color? paid, Color? neutral}) => FinPalette(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        pending: pending ?? this.pending,
        paid: paid ?? this.paid,
        neutral: neutral ?? this.neutral,
      );

  @override
  FinPalette lerp(FinPalette? other, double t) {
    if (other == null) return this;
    return FinPalette(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      paid: Color.lerp(paid, other.paid, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}

enum AppTheme { classic, classicDark, ryusui, nami }

extension AppThemeInfo on AppTheme {
  String get label => switch (this) {
        AppTheme.classic => 'Clásico',
        AppTheme.classicDark => 'Clásico oscuro',
        AppTheme.ryusui => 'Ryusui',
        AppTheme.nami => 'Nami',
      };

  String get description => switch (this) {
        AppTheme.classic => 'Verde y claro, el tema original',
        AppTheme.classicDark => 'El tema original en modo oscuro',
        AppTheme.ryusui => 'Dorado, rojo vino y azul',
        AppTheme.nami => 'Naranja, durazno y azul cielo',
      };

  /// Colores de la paleta original (para la vista previa en Ajustes).
  List<Color> get swatch => switch (this) {
        AppTheme.classic => const [Color(0xFF1F6F5C), Color(0xFFA0F0D9), Color(0xFF1B8A5A), Color(0xFFC0392B), Color(0xFFF4FBF8)],
        AppTheme.classicDark => const [Color(0xFF1F6F5C), Color(0xFF84D6BE), Color(0xFF4CC38A), Color(0xFFFF6B5E), Color(0xFF0F1513)],
        AppTheme.ryusui => const [
            Color(0xFFE8B84C), Color(0xFFF5D77A), Color(0xFFC9272C), Color(0xFF751A24),
            Color(0xFFD9C29B), Color(0xFF2455A4), Color(0xFFE77A27), Color(0xFF65402D),
          ],
        AppTheme.nami => const [
            Color(0xFFF28C28), Color(0xFFFFAD45), Color(0xFFF5C49F), Color(0xFF75432E),
            Color(0xFF65BDEB), Color(0xFF226AA8), Color(0xFFE1BE2A), Color(0xFF79482C),
          ],
      };

  ThemeData get data => switch (this) {
        AppTheme.classic => _classic(Brightness.light),
        AppTheme.classicDark => _classic(Brightness.dark),
        AppTheme.ryusui => _ryusui(),
        AppTheme.nami => _nami(),
      };
}

const _classicSeed = Color(0xFF1F6F5C);

ThemeData _classic(Brightness b) {
  final light = b == Brightness.light;
  return ThemeData(
    colorSchemeSeed: _classicSeed,
    brightness: b,
    useMaterial3: true,
    extensions: [
      light
          ? const FinPalette(
              income: Color(0xFF1B8A5A),
              expense: Color(0xFFC0392B),
              pending: Color(0xFFB9770E),
              paid: Color(0xFF2E6DA4),
              neutral: Color(0xFF5D6D7E))
          : const FinPalette(
              income: Color(0xFF4CC38A),
              expense: Color(0xFFFF6B5E),
              pending: Color(0xFFF5B041),
              paid: Color(0xFF6FA8DC),
              neutral: Color(0xFFA0AAB4)),
    ],
  );
}

/// Ryusui: rojo vino como color principal, dorado en tarjetas y navegación,
/// fondo pergamino y azul para los ingresos.
ThemeData _ryusui() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF751A24)).copyWith(
    primary: const Color(0xFF751A24),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFF5D77A),
    onPrimaryContainer: const Color(0xFF65402D),
    secondary: const Color(0xFF2455A4),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFF5D77A),
    onSecondaryContainer: const Color(0xFF65402D),
    tertiary: const Color(0xFFE77A27),
    onTertiary: Colors.white,
    error: const Color(0xFFC9272C),
    errorContainer: const Color(0xFFF6D5D3),
    onErrorContainer: const Color(0xFF751A24),
    surface: const Color(0xFFFBF6EC),
    onSurface: const Color(0xFF3A2A20),
    onSurfaceVariant: const Color(0xFF65402D),
    surfaceContainerLowest: const Color(0xFFFFFDF8),
    surfaceContainerLow: const Color(0xFFF6EDDC),
    surfaceContainer: const Color(0xFFF1E5CE),
    surfaceContainerHigh: const Color(0xFFEBDDC1),
    surfaceContainerHighest: const Color(0xFFE3D2B2),
    outline: const Color(0xFF9C8466),
    outlineVariant: const Color(0xFFD9C29B),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: const [
      FinPalette(
        income: Color(0xFF2455A4),
        expense: Color(0xFFC9272C),
        pending: Color(0xFFBF5F14), // naranja #E77A27 oscurecido para leerse sobre fondo claro
        paid: Color(0xFF65402D),
        neutral: Color(0xFF8C7A63),
      ),
    ],
  );
}

/// Nami: naranja como color principal, durazno en tarjetas, azul cielo en la
/// navegación y azul mar para los ingresos.
ThemeData _nami() {
  // El naranja #F28C28 es muy claro para texto sobre fondo claro: «primary»
  // (texto, iconos, bordes) usa un naranja más profundo y los botones
  // rellenos conservan el naranja original.
  const namiOrange = Color(0xFFF28C28);
  const namiInk = Color(0xFF3B2214);
  final scheme = ColorScheme.fromSeed(seedColor: namiOrange).copyWith(
    primary: const Color(0xFFAE5409),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFF5C49F),
    onPrimaryContainer: const Color(0xFF75432E),
    secondary: const Color(0xFF226AA8),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFCFEAF9),
    onSecondaryContainer: const Color(0xFF113A5E),
    tertiary: const Color(0xFFE1BE2A),
    onTertiary: const Color(0xFF3B2214),
    surface: const Color(0xFFFFF8F1),
    onSurface: const Color(0xFF3B2214),
    onSurfaceVariant: const Color(0xFF79482C),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFFFF0E2),
    surfaceContainer: const Color(0xFFFDE8D5),
    surfaceContainerHigh: const Color(0xFFFADFC8),
    surfaceContainerHighest: const Color(0xFFF5D3B8),
    outline: const Color(0xFFA88267),
    outlineVariant: const Color(0xFFF5C49F),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: namiOrange, foregroundColor: namiInk),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Color(0xFFFFAD45), foregroundColor: namiInk),
    extensions: const [
      FinPalette(
        income: Color(0xFF226AA8),
        expense: Color(0xFFB3261E), // la paleta no tiene rojo: se usa uno estándar para alertas
        pending: Color(0xFFA6820A), // amarillo #E1BE2A oscurecido para leerse sobre fondo claro
        paid: Color(0xFF79482C),
        neutral: Color(0xFF8F7B6E),
      ),
    ],
  );
}

/// Guarda y aplica el tema elegido (preferencia de este dispositivo).
class ThemeController extends ChangeNotifier {
  static const _key = 'drago.theme';
  AppTheme _theme;
  ThemeController(this._theme);

  AppTheme get theme => _theme;

  static Future<ThemeController> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final name = p.getString(_key);
      return ThemeController(AppTheme.values.firstWhere((t) => t.name == name, orElse: () => AppTheme.classic));
    } catch (_) {
      return ThemeController(AppTheme.classic);
    }
  }

  Future<void> set(AppTheme t) async {
    if (t == _theme) return;
    _theme = t;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, t.name);
    } catch (_) {}
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({super.key, required ThemeController controller, required super.child}) : super(notifier: controller);
  static ThemeController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;
}
