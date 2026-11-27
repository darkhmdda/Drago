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

enum AppTheme { classic, classicDark, drago, dragoDark, ryusui, nami }

extension AppThemeInfo on AppTheme {
  String get label => switch (this) {
        AppTheme.classic => 'Clásico',
        AppTheme.classicDark => 'Clásico oscuro',
        AppTheme.drago => 'Drago',
        AppTheme.dragoDark => 'Drago oscuro',
        AppTheme.ryusui => 'Ryusui',
        AppTheme.nami => 'Nami',
      };

  String get description => switch (this) {
        AppTheme.classic => 'Índigo y azul cielo, estilo banco digital',
        AppTheme.classicDark => 'Índigo y azul cielo en modo oscuro',
        AppTheme.drago => 'Dorado y café del emblema de Drago',
        AppTheme.dragoDark => 'El emblema de Drago en modo oscuro',
        AppTheme.ryusui => 'Naranja, azul cobalto y rojo capitán',
        AppTheme.nami => 'Naranja, durazno y azul cielo',
      };

  /// Colores de la paleta original (para la vista previa en Ajustes).
  List<Color> get swatch => switch (this) {
        AppTheme.classic => const [Color(0xFF4338CA), Color(0xFFE0E7FF), Color(0xFF0369A1), Color(0xFFE11D48), Color(0xFFF6F7FB)],
        AppTheme.classicDark => const [Color(0xFFA5B4FC), Color(0xFF312E81), Color(0xFF7DD3FC), Color(0xFFFB7185), Color(0xFF11121A)],
        AppTheme.drago => const [Color(0xFFFCC858), Color(0xFF5B3A1A), Color(0xFF270D07), Color(0xFFFCE7B0), Color(0xFFFBF7EE)],
        AppTheme.dragoDark => const [Color(0xFFFCC858), Color(0xFFE8B750), Color(0xFF5B3A1A), Color(0xFF270D07), Color(0xFF1A0B06)],
        AppTheme.ryusui => const [
            Color(0xFFE87524), Color(0xFF2455A4), Color(0xFFB92732), Color(0xFFF2C94C),
            Color(0xFF8B552E), Color(0xFFF0D6B5), Color(0xFF252525),
          ],
        AppTheme.nami => const [
            Color(0xFFF28C28), Color(0xFFFFAD45), Color(0xFFF5C49F), Color(0xFF75432E),
            Color(0xFF65BDEB), Color(0xFF226AA8), Color(0xFFE1BE2A), Color(0xFF79482C),
          ],
      };

  ThemeData get data => switch (this) {
        AppTheme.classic => _classic(Brightness.light),
        AppTheme.classicDark => _classic(Brightness.dark),
        AppTheme.drago => _drago(Brightness.light),
        AppTheme.dragoDark => _drago(Brightness.dark),
        AppTheme.ryusui => _ryusui(),
        AppTheme.nami => _nami(),
      };
}

/// Clásico (fintech moderno): índigo como color principal y azul cielo como acento,
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
          secondary: const Color(0xFF0369A1),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFE0F2FE),
          onSecondaryContainer: const Color(0xFF0C4A6E),
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
          secondary: const Color(0xFF7DD3FC),
          onSecondary: const Color(0xFF0C2A3E),
          secondaryContainer: const Color(0xFF0C4A6E),
          onSecondaryContainer: const Color(0xFFE0F2FE),
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
              income: Color(0xFF15803D),
              expense: Color(0xFFE11D48),
              pending: Color(0xFFB45309),
              paid: Color(0xFF4338CA),
              neutral: Color(0xFF6B7280),
              chartBase: Color(0xFF4338CA),
              chartScenario: Color(0xFFB45309))
          : const FinPalette(
              income: Color(0xFF3FB950),
              expense: Color(0xFFFB7185),
              pending: Color(0xFFFBBF24),
              paid: Color(0xFFA5B4FC),
              neutral: Color(0xFF9CA3AF),
              chartBase: Color(0xFF818CF8),
              chartScenario: Color(0xFFFBBF24)),
    ],
  );
}

/// Drago: los colores del emblema. Dorado #FCC858 sobre café muy oscuro
/// #270D07, con café medio #5B3A1A. En claro el dorado va en botones y
/// acentos (el texto usa café para leerse bien); en oscuro el dorado es el
/// color principal sobre fondos café casi negros.
ThemeData _drago(Brightness b) {
  final light = b == Brightness.light;
  const gold = Color(0xFFFCC858);
  const ink = Color(0xFF270D07);
  const brown = Color(0xFF5B3A1A);
  final scheme = light
      ? ColorScheme.fromSeed(seedColor: gold).copyWith(
          primary: brown,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFFCE7B0),
          onPrimaryContainer: ink,
          secondary: const Color(0xFF9A6A0C),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFFCD98B),
          onSecondaryContainer: ink,
          tertiary: const Color(0xFF8A4B1F),
          onTertiary: Colors.white,
          error: const Color(0xFFB3261E),
          errorContainer: const Color(0xFFFBE0DA),
          onErrorContainer: const Color(0xFF7A1A12),
          surface: const Color(0xFFFBF7EE),
          onSurface: ink,
          onSurfaceVariant: const Color(0xFF6B4E33),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF7F0E0),
          surfaceContainer: const Color(0xFFF3EAD5),
          surfaceContainerHigh: const Color(0xFFEEE2C8),
          surfaceContainerHighest: const Color(0xFFE7D8B9),
          outline: const Color(0xFFA8906E),
          outlineVariant: const Color(0xFFE9DCC0),
        )
      : ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark).copyWith(
          primary: gold,
          onPrimary: ink,
          primaryContainer: brown,
          onPrimaryContainer: const Color(0xFFFCE7B0),
          secondary: const Color(0xFFE8B750),
          onSecondary: ink,
          secondaryContainer: const Color(0xFF4A2E14),
          onSecondaryContainer: const Color(0xFFFCE7B0),
          tertiary: const Color(0xFFF0A868),
          onTertiary: ink,
          error: const Color(0xFFFF8A80),
          onError: const Color(0xFF4A0E08),
          errorContainer: const Color(0xFF4A1A14),
          onErrorContainer: const Color(0xFFFFD7D1),
          surface: const Color(0xFF1A0B06),
          onSurface: const Color(0xFFF5E9D6),
          onSurfaceVariant: const Color(0xFFC9B79C),
          surfaceContainerLowest: const Color(0xFF140804),
          surfaceContainerLow: const Color(0xFF22110A),
          surfaceContainer: const Color(0xFF2A160D),
          surfaceContainerHigh: const Color(0xFF331C11),
          surfaceContainerHighest: const Color(0xFF3D2416),
          outline: const Color(0xFF8A7058),
          outlineVariant: const Color(0xFF4A3020),
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
    // Botones y botón flotante en el dorado del emblema con texto café.
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: gold, foregroundColor: ink),
    extensions: [
      light
          ? const FinPalette(
              income: Color(0xFF2E7D32),
              expense: Color(0xFFB3261E),
              pending: Color(0xFFB26A00),
              paid: brown,
              neutral: Color(0xFF8C7B6B),
              chartBase: brown,
              chartScenario: Color(0xFFC08A1E))
          : const FinPalette(
              income: Color(0xFF81C784),
              expense: Color(0xFFFF8A80),
              pending: Color(0xFFFFB74D),
              paid: Color(0xFFE8D3A8),
              neutral: Color(0xFFA8998A),
              chartBase: gold,
              chartScenario: Color(0xFFFF8A65)),
    ],
  );
}

/// Ryusui: naranja Ryusui en botones y acentos, azul cobalto en la tarjeta
/// principal y los ingresos, rojo capitán para alertas y pagos vencidos,
/// barra superior negro carbón y fondo neutro (distinto del crema de Drago).
ThemeData _ryusui() {
  const orange = Color(0xFFE87524);
  const cobalt = Color(0xFF2455A4);
  const captain = Color(0xFFB92732);
  const charcoal = Color(0xFF252525);
  const brown = Color(0xFF8B552E);
  final scheme = ColorScheme.fromSeed(seedColor: orange).copyWith(
    // El naranja puro es claro para texto: «primary» (texto, iconos, bordes)
    // usa uno más profundo; los botones rellenos llevan el naranja original.
    primary: const Color(0xFFB9551A),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFDCE6F7),
    onPrimaryContainer: const Color(0xFF12305F),
    secondary: cobalt,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFCDCC4),
    onSecondaryContainer: const Color(0xFF5A2A0C),
    tertiary: captain,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFF2C94C),
    onTertiaryContainer: charcoal,
    error: captain,
    errorContainer: const Color(0xFFF8D9DB),
    onErrorContainer: const Color(0xFF7A1820),
    surface: const Color(0xFFF7F5F2),
    onSurface: charcoal,
    onSurfaceVariant: const Color(0xFF5E5148),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF1EEEA),
    surfaceContainer: const Color(0xFFECE7E1),
    surfaceContainerHigh: const Color(0xFFE5DFD7),
    surfaceContainerHighest: const Color(0xFFDDD5CB),
    outline: const Color(0xFF9A8F86),
    outlineVariant: const Color(0xFFF0D6B5),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(backgroundColor: charcoal, foregroundColor: Colors.white),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: orange, foregroundColor: charcoal)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: orange, foregroundColor: charcoal),
    extensions: const [
      FinPalette(
        income: cobalt,
        expense: captain,
        pending: Color(0xFF9A7400), // rubio dorado #F2C94C oscurecido para leerse sobre fondo claro
        paid: brown,
        neutral: Color(0xFF7D7268),
        chartBase: cobalt,
        chartScenario: Color(0xFFC85F12),
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
