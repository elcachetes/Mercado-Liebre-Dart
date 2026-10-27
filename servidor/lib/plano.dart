/// Códigos del plano del ITCJ. La geometría vive en la app Flutter
/// (`cliente/lib/mapa/puntos_campus.dart`); aquí solo se valida que el
/// vendedor elija un punto que existe.
///
/// Si agregas o quitas un punto, cambia ambos archivos. El test
/// `cliente/test/plano_sincronizado_test.dart` falla si no coinciden.
const Set<String> codigosDelPlano = {
  'A', 'B', 'C', 'D', 'E', 'F1', 'F2', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
  'O', 'P1', 'P2', 'P3', 'P4', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  'ZZ', '1', '2', '3', '4', '5', '6', '7', '8',
};
