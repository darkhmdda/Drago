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

  /// Series de las gráficas (validadas para daltonismo y contraste en cada tema):
  /// proyección base y simulación.
  final Color chartBase;
  final Color chartScenario;

  const FinPalette({
    required this.income,
    required this.expense,
    required this.pending,
    required this.paid,
    required this.neutral,
    required this.chartBase,
    required this.chartScenario,
  });

  @override
  FinPalette copyWith({Color? income, Color? expense, Color? pending, Color? paid, Color? neutral}) => FinPalette(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        pending: pending ?? this.pending,
        paid: paid ?? this.paid,
        neutral: neutral ?? this.neutral,
        chartBase: chartBase,
        chartScenario: chartScenario,
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
      chartBase: Color.lerp(chartBase, other.chartBase, t)!,
      chartScenario: Color.lerp(chartScenario, other.chartScenario, t)!,
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
        AppTheme.classic => 'Índigo y menta, estilo banco digital',
        AppTheme.classicDark => 'Índigo y menta en modo oscuro',
        AppTheme.ryusui => 'Dorado, rojo vino y azul',
        AppTheme.nami => 'Naranja, durazno y azul cielo',
      };

  /// Colores de la paleta original (para la vista previa en Ajustes).
  List<Color> get swatch => switch (this) {
        AppTheme.classic => const [Color(0xFF4338CA), Color(0xFFE0E7FF), Color(0xFF10B981), Color(0xFFE11D48), Color(0xFFF6F7FB)],
        AppTheme.classicDark => const [Color(0xFFA5B4FC), Color(0xFF312E81), Color(0xFF34D399), Color(0xFFFB7185), Color(0xFF11121A)],
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

/// Clásico (fintech moderno): índigo como color principal y menta como acento,
/// fondos fríos y limpios, tarjetas planas con borde fino.
ThemeData _classic(Brightness b) {
  final light = b == Brightness.light;
  const indigo = Color(0xFF4338CA);
  final scheme = light
      ? ColorScheme.fromSeed(seedColor: indigo).copyWith(
          primary: indigo,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFE0E7FF),
          onPrimaryContainer: const Color(0xFF1E1B4B),
          secondary: const Color(0xFF047857),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFD1FAE5),
          onSecondaryContainer: const Color(0xFF064E3B),
          tertiary: const Color(0xFF7C3AED),
          onTertiary: Colors.white,
          error: const Color(0xFFDC2626),
          errorContainer: const Color(0xFFFFE4E6),
          onErrorContainer: const Color(0xFF9F1239),
          surface: const Color(0xFFF6F7FB),
          onSurface: const Color(0xFF111827),
          onSurfaceVariant: const Color(0xFF4B5563),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF1F2F8),
          surfaceContainer: const Color(0xFFECEEF6),
          surfaceContainerHigh: const Color(0xFFE5E7F2),
          surfaceContainerHighest: const Color(0xFFDDE0EE),
          outline: const Color(0xFF9CA3AF),
          outlineVariant: const Color(0xFFE0E3EE),
        )
      : ColorScheme.fromSeed(seedColor: indigo, brightness: Brightness.dark).copyWith(
          primary: const Color(0xFFA5B4FC),
          onPrimary: const Color(0xFF1E1B4B),
          primaryContainer: const Color(0xFF312E81),
          onPrimaryContainer: const Color(0xFFE0E7FF),
          secondary: const Color(0xFF34D399),
          onSecondary: const Color(0xFF052E1C),
          secondaryContainer: const Color(0xFF064E3B),
          onSecondaryContainer: const Color(0xFFD1FAE5),
          tertiary: const Color(0xFFC4B5FD),
          onTertiary: const Color(0xFF2E1065),
          error: const Color(0xFFFB7185),
          onError: const Color(0xFF4C0519),
          errorContainer: const Color(0xFF3B1622),
          onErrorContainer: const Color(0xFFFECDD3),
          surface: const Color(0xFF11121A),
          onSurface: const Color(0xFFE5E7EB),
          onSurfaceVariant: const Color(0xFFA1A7B8),
          surfaceContainerLowest: const Color(0xFF0C0D13),
          surfaceContainerLow: const Color(0xFF161722),
          surfaceContainer: const Color(0xFF1B1C28),
          surfaceContainerHigh: const Color(0xFF232435),
          surfaceContainerHighest: const Color(0xFF2C2E42),
          outline: const Color(0xFF6B7085),
          outlineVariant: const Color(0xFF34364A),
        );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? Colors.white : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    extensions: [
      light
          ? const FinPalette(
              income: Color(0xFF047857),
              expense: Color(0xFFE11D48),
              pending: Color(0xFFB45309),
              paid: Color(0xFF4338CA),
              neutral: Color(0xFF6B7280),
              chartBase: Color(0xFF4338CA),
              chartScenario: Color(0xFFB45309))
          : const FinPalette(
              income: Color(0xFF34D399),
              expense: Color(0xFFFB7185),
              pending: Color(0xFFFBBF24),
              paid: Color(0xFFA5B4FC),
              neutral: Color(0xFF9CA3AF),
              chartBase: Color(0xFF818CF8),
              chartScenario: Color(0xFFFBBF24)),
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
        chartBase: Color(0xFF2455A4),
        chartScenario: Color(0xFFBF5F14),
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
        chartBase: Color(0xFF226AA8),
        chartScenario: Color(0xFFA6820A),
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
