import 'package:flutter/foundation.dart';

/// Versión fuera del navegador (app nativa y pruebas): no hay nada que instalar.
///
/// Misma interfaz que `instalacion_web.dart`; ver `instalacion.dart`.
class InstalacionApp extends ChangeNotifier {
  InstalacionApp._();

  /// Única instancia, compartida por todos los botones.
  static final InstalacionApp instancia = InstalacionApp._();

  /// El navegador ofrece su diálogo de instalación.
  bool get disponible => false;

  /// iPhone o iPad: se instala a mano desde "Compartir".
  bool get esIos => false;

  /// Ya corre como app instalada.
  bool get instalada => true;

  /// Mostrar el botón "Instalar app".
  bool get mostrarBoton => false;

  /// Abre el diálogo del navegador. Verdadero si la persona aceptó.
  Future<bool> instalar() async => false;
}
