import 'package:flutter/material.dart';

/// Paleta institucional: rojo y blanco.
///
/// Usa estos valores solo para la marca (barra superior, avatar de
/// categoría). Para texto y fondos usa `Theme.of(context).colorScheme`,
/// que ya tiene la variante correcta para modo claro y oscuro.
class ColoresLiebre {
  const ColoresLiebre._();

  /// Rojo principal de la barra superior y la marca.
  static const Color primario = Color(0xFFC1121F);

  /// Rojo oscuro para acentos sobre fondo claro.
  static const Color primarioOscuro = Color(0xFF780000);

  /// Fondo general, blanco con un matiz rosado.
  static const Color fondo = Color(0xFFFDF0EF);

  /// Superficie de tarjetas.
  static const Color superficie = Color(0xFFFFFFFF);

  /// Estrellas de calificación y destacados.
  static const Color estrella = Color(0xFFF2A900);

  /// Indicador de "Abierto ahora" (claro / oscuro).
  static Color abierto(Brightness brillo) =>
      brillo == Brightness.dark ? const Color(0xFF7BD88F) : const Color(0xFF2E7D32);
}

/// Separaciones estándar. Usarlas mantiene el ritmo vertical entre pantallas.
class Espacio {
  const Espacio._();

  /// 4 px.
  static const double xs = 4;

  /// 8 px.
  static const double s = 8;

  /// 12 px.
  static const double m = 12;

  /// 16 px: margen lateral de las pantallas.
  static const double l = 16;

  /// 24 px: separación entre secciones.
  static const double xl = 24;

  /// Ancho máximo del contenido en pantallas anchas.
  static const double anchoMaximo = 880;
}

/// Tema claro u oscuro. La barra superior se mantiene en rojo institucional.
ThemeData temaLiebre(Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  final esquema = ColorScheme.fromSeed(
    seedColor: ColoresLiebre.primario,
    brightness: brillo,
    primary: oscuro ? const Color(0xFFFFB3AE) : ColoresLiebre.primario,
    onPrimary: oscuro ? const Color(0xFF680008) : Colors.white,
    surface: oscuro ? const Color(0xFF1E1515) : ColoresLiebre.superficie,
  );
  final redondeo12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(useMaterial3: true, brightness: brillo, colorScheme: esquema);

  return base.copyWith(
    scaffoldBackgroundColor: oscuro ? const Color(0xFF140E0E) : ColoresLiebre.fondo,
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ColoresLiebre.primario,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: esquema.surface,
      indicatorColor: esquema.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((estados) {
        final activo = estados.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
          color: activo ? esquema.onSurface : esquema.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: esquema.surface,
      indicatorColor: esquema.primaryContainer,
    ),
    cardTheme: CardThemeData(
      color: esquema.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: esquema.outlineVariant.withValues(alpha: oscuro ? 0.4 : 0.6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: oscuro ? const Color(0xFF2A1E1E) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: redondeo12,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: esquema.primary,
        side: BorderSide(color: esquema.primary, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: redondeo12,
      ),
    ),
    chipTheme: ChipThemeData(shape: StadiumBorder(side: BorderSide(color: esquema.outlineVariant))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: redondeo12),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    expansionTileTheme: ExpansionTileThemeData(shape: redondeo12, collapsedShape: redondeo12),
  );
}
