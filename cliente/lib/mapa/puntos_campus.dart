/// Puntos del plano oficial del ITCJ, en píxeles de `mapa_plantel.jpg`.
///
/// Cada punto se puede tocar en el dibujo del edificio y en el texto de
/// la leyenda. 1024×549 es el tamaño de la imagen.
library;

/// Ancho de la imagen del plano, en píxeles.
const int imagenAncho = 1024;

/// Alto de la imagen del plano, en píxeles.
const int imagenAlto = 549;

/// Ancho del dibujo del plantel dentro de la imagen. A la derecha está la
/// leyenda impresa, que la app no muestra: la dibuja como texto.
const int dibujoAncho = 500;

/// Rectángulo de un edificio o de una línea de la leyenda.
class RectPlano {
  /// Coordenadas en píxeles de la imagen, origen arriba a la izquierda.
  const RectPlano(this.x, this.y, this.ancho, this.alto);

  /// Borde izquierdo.
  final int x;

  /// Borde superior.
  final int y;

  /// Ancho.
  final int ancho;

  /// Alto.
  final int alto;
}

/// Un lugar del plantel donde se puede vender.
class PuntoCampus {
  /// [plano] puede estar vacío si el lugar solo aparece en la leyenda.
  const PuntoCampus({
    required this.codigo,
    required this.nombre,
    required this.plano,
    required this.leyenda,
  });

  /// Clave corta: A, F1, 8, ZZ.
  final String codigo;

  /// Nombre de la leyenda.
  final String nombre;

  /// Zonas tocables sobre el dibujo.
  final List<RectPlano> plano;

  /// Zona tocable sobre el texto de la leyenda.
  final RectPlano leyenda;

  /// Título que se muestra al abrir el punto.
  String get titulo => '$codigo · $nombre';
}

const int _izqX = 504;
const int _izqW = 252;
const int _derX = 770;
const int _derW = 242;

RectPlano _izq(int y, int alto) => RectPlano(_izqX, y, _izqW, alto);
RectPlano _der(int y, int alto) => RectPlano(_derX, y, _derW, alto);

/// Catálogo en el mismo orden que la leyenda impresa.
final List<PuntoCampus> puntosCampus = [
  PuntoCampus(codigo: 'A', nombre: 'Edificio administrativo', plano: [RectPlano(40, 468, 26, 36)], leyenda: _izq(101, 12)),
  PuntoCampus(codigo: 'B', nombre: "Edif. Ramón Rivera Lara 100's y 200's", plano: [RectPlano(42, 374, 86, 90)], leyenda: _izq(113, 12)),
  PuntoCampus(codigo: 'C', nombre: 'Centro de información (biblioteca)', plano: [RectPlano(146, 444, 36, 46)], leyenda: _izq(124, 11)),
  PuntoCampus(codigo: 'D', nombre: 'Dpto. de Ing. Eléctrica y Electrónica', plano: [RectPlano(60, 332, 42, 32)], leyenda: _izq(135, 22)),
  PuntoCampus(codigo: 'E', nombre: 'Caldera de lab. de Ing. Mecánica', plano: [RectPlano(84, 298, 20, 16)], leyenda: _izq(158, 11)),
  PuntoCampus(codigo: 'F1', nombre: 'Laboratorio de Ing. Mecánica', plano: [RectPlano(106, 316, 32, 24)], leyenda: _izq(169, 11)),
  PuntoCampus(codigo: 'F2', nombre: 'Laboratorio de Ing. Eléctrica', plano: [RectPlano(106, 340, 32, 24)], leyenda: _izq(180, 11)),
  PuntoCampus(codigo: 'G', nombre: 'Laboratorio de Química y Física', plano: [RectPlano(136, 366, 28, 22)], leyenda: _izq(191, 11)),
  PuntoCampus(codigo: 'H', nombre: 'Cafetería', plano: [RectPlano(152, 310, 26, 20)], leyenda: _izq(202, 11)),
  PuntoCampus(codigo: 'I', nombre: 'Div. de Estudios Profesionales', plano: [RectPlano(162, 346, 24, 20)], leyenda: _izq(213, 21)),
  PuntoCampus(codigo: 'J', nombre: 'Centro de cómputo', plano: [RectPlano(188, 326, 24, 22)], leyenda: _izq(235, 11)),
  PuntoCampus(codigo: 'K', nombre: 'Edificio Guillot (salas de titulación)', plano: [RectPlano(220, 358, 42, 42)], leyenda: _izq(246, 11)),
  PuntoCampus(codigo: 'L', nombre: 'Dpto. Gestión Tecnológica y Vinculación', plano: [RectPlano(246, 314, 28, 38)], leyenda: _izq(257, 11)),
  PuntoCampus(codigo: 'M', nombre: "Dpto. de Ciencias Básicas y aulas 300's", plano: [RectPlano(78, 266, 30, 32)], leyenda: _izq(269, 11)),
  PuntoCampus(codigo: 'N', nombre: 'Dpto. de Mantenimiento y transporte', plano: [RectPlano(88, 204, 38, 48)], leyenda: _izq(280, 21)),
  PuntoCampus(codigo: 'O', nombre: 'Laboratorio de Ingeniería Industrial', plano: [RectPlano(114, 260, 32, 40)], leyenda: _izq(302, 11)),
  PuntoCampus(codigo: 'P1', nombre: 'Sala audiovisual', plano: [RectPlano(148, 264, 22, 10)], leyenda: _izq(313, 11)),
  PuntoCampus(codigo: 'P2', nombre: 'Coordinación de educación a distancia', plano: [RectPlano(148, 274, 22, 10)], leyenda: _izq(324, 11)),
  PuntoCampus(codigo: 'P3', nombre: 'Dpto. de Desarrollo Académico', plano: [RectPlano(148, 284, 22, 10)], leyenda: _izq(335, 11)),
  PuntoCampus(codigo: 'P4', nombre: "Aulas 400's", plano: [RectPlano(148, 294, 22, 12)], leyenda: _izq(347, 11)),
  PuntoCampus(codigo: 'Q', nombre: 'Gimnasio y actividades extraescolares', plano: [RectPlano(186, 264, 48, 44)], leyenda: _izq(358, 12)),
  PuntoCampus(codigo: 'R', nombre: 'Alberca y actividades culturales', plano: [RectPlano(234, 264, 46, 44)], leyenda: _der(101, 12)),
  PuntoCampus(codigo: 'S', nombre: "Aulas 800's", plano: [RectPlano(288, 238, 28, 24)], leyenda: _der(113, 11)),
  PuntoCampus(codigo: 'T', nombre: 'Oficina de activo fijo, editorial y almacén', plano: [RectPlano(280, 266, 36, 26)], leyenda: _der(124, 11)),
  PuntoCampus(codigo: 'U', nombre: "Dpto. de Ing. Industrial y aulas 900's", plano: [RectPlano(284, 292, 30, 36)], leyenda: _der(135, 11)),
  PuntoCampus(codigo: 'V', nombre: 'Centro de idiomas', plano: [RectPlano(326, 298, 40, 32)], leyenda: _der(146, 12)),
  PuntoCampus(codigo: 'W', nombre: 'Dpto. de Sistemas y laboratorio de cómputo', plano: [RectPlano(316, 362, 36, 32)], leyenda: _der(158, 20)),
  PuntoCampus(codigo: 'X', nombre: 'Posgrado e Investigación / Aula Magna', plano: [RectPlano(368, 306, 30, 48)], leyenda: _der(180, 20)),
  PuntoCampus(codigo: 'Y', nombre: 'Laboratorio de Mecatrónica', plano: [RectPlano(402, 294, 34, 40)], leyenda: _der(202, 11)),
  PuntoCampus(codigo: 'Z', nombre: 'Nodo de Creatividad y Emprendimiento', plano: [RectPlano(440, 276, 44, 48)], leyenda: _der(213, 11)),
  PuntoCampus(codigo: 'ZZ', nombre: 'Auditorio multifuncional', plano: [RectPlano(314, 64, 46, 58)], leyenda: _der(224, 12)),
  PuntoCampus(codigo: '1', nombre: 'Estacionamiento para personal', plano: [], leyenda: _der(246, 11)),
  PuntoCampus(codigo: '2', nombre: 'Plaza cívica', plano: [], leyenda: _der(257, 11)),
  PuntoCampus(codigo: '3', nombre: 'Área de esparcimiento', plano: [], leyenda: _der(269, 11)),
  PuntoCampus(codigo: '4', nombre: 'Obelisco Luz y Sabiduría', plano: [], leyenda: _der(280, 11)),
  PuntoCampus(codigo: '5', nombre: 'Lab. de Ciencias Económico Administrativas', plano: [], leyenda: _der(291, 11)),
  PuntoCampus(codigo: '6', nombre: 'Estacionamiento para alumnos', plano: [], leyenda: _der(302, 11)),
  PuntoCampus(codigo: '7', nombre: 'Domo de basquetbol', plano: [RectPlano(286, 198, 48, 36)], leyenda: _der(313, 11)),
  PuntoCampus(codigo: '8', nombre: 'Áreas deportivas', plano: [RectPlano(176, 118, 56, 42)], leyenda: _der(324, 12)),
];

/// Busca un punto por su código, sin importar mayúsculas.
PuntoCampus? puntoPorCodigo(String? codigo) {
  if (codigo == null || codigo.trim().isEmpty) {
    return null;
  }
  final buscado = codigo.trim().toUpperCase();
  for (final punto in puntosCampus) {
    if (punto.codigo == buscado) {
      return punto;
    }
  }
  return null;
}
