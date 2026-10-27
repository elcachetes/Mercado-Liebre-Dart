import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../configuracion.dart';
import '../modelos/modelos.dart';

/// Fallo devuelto por la API, con el mensaje pensado para la persona.
///
/// También representa la falta de red o un tiempo de espera agotado
/// ([estado] = 0), así que las pantallas solo necesitan atrapar este tipo.
class ErrorApi implements Exception {
  /// [mensaje] viene del campo `error` del JSON, o un texto genérico.
  ErrorApi(this.mensaje, {this.estado = 0});

  /// Texto para un SnackBar.
  final String mensaje;

  /// Código HTTP, o 0 si no hubo respuesta del servidor.
  final int estado;

  /// Verdadero cuando ni siquiera hubo respuesta.
  bool get sinConexion => estado == 0;

  @override
  String toString() => mensaje;
}

/// Cliente HTTP de la app. No abre PostgreSQL.
///
/// Reutiliza una sola conexión ([http.Client]) para todas las peticiones.
class ClienteApi {
  /// [baseUrl] suele ser [ConfiguracionApp.apiBaseUrl].
  ClienteApi({String? baseUrl, this.token, http.Client? cliente})
      : baseUrl = baseUrl ?? ConfiguracionApp.apiBaseUrl,
        _http = cliente ?? http.Client();

  /// Origen de la API, sin barra final.
  final String baseUrl;

  /// Token de sesión, o null si la persona no entró.
  String? token;

  final http.Client _http;

  /// Tiempo máximo de espera por respuesta.
  static const Duration tiempoLimite = Duration(seconds: 15);

  static const String _sinConexion = 'No hay conexión con el servidor. Revisa tu internet e inténtalo de nuevo.';

  // ── Sesión ────────────────────────────────────────────────────────────

  /// Inicia sesión y devuelve el token junto con el usuario.
  Future<({String token, Usuario usuario})> iniciarSesion(String correo, String password) async {
    return _sesion(await _objeto('POST', '/api/sesion', {'correo': correo, 'password': password}));
  }

  /// Crea la cuenta y deja la sesión iniciada.
  Future<({String token, Usuario usuario})> registrar(Map<String, dynamic> datos) async {
    return _sesion(await _objeto('POST', '/api/usuarios', datos));
  }

  /// Recupera la cuenta del token guardado.
  Future<Usuario> yo() async => Usuario.fromJson(await _objeto('GET', '/api/yo'));

  /// Cambia teléfono, número de control y carrera. Vacío borra el dato.
  Future<Usuario> actualizarPerfil({String? telefono, String? numeroControl, String? carrera}) async {
    return Usuario.fromJson(await _objeto('PATCH', '/api/yo', {
      'telefono': telefono,
      'numeroControl': numeroControl,
      'carrera': carrera,
    }));
  }

  // ── Vendedores y productos ────────────────────────────────────────────

  /// Lista de negocios. [soloDisponibles] oculta los cerrados.
  Future<List<Vendedor>> vendedores({bool soloDisponibles = false}) async {
    final datos = await _lista('/api/vendedores', {if (soloDisponibles) 'soloDisponibles': 'true'});
    return datos.map(Vendedor.fromJson).toList();
  }

  /// Negocios con promoción vigente.
  Future<List<Vendedor>> destacados() async {
    return (await _lista('/api/vendedores/destacados')).map(Vendedor.fromJson).toList();
  }

  /// Negocio de la cuenta actual, o null si la cuenta no tiene uno.
  Future<Vendedor?> miNegocio() async {
    try {
      return Vendedor.fromJson(await _objeto('GET', '/api/vendedores/mio'));
    } on ErrorApi catch (error) {
      if (error.estado == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// Productos de un negocio.
  Future<List<Producto>> productosDe(String sellerId) async {
    return (await _lista('/api/productos', {'vendedor': sellerId})).map(Producto.fromJson).toList();
  }

  /// Ranking por veces vendidas.
  Future<List<Producto>> masVendidos() async {
    return (await _lista('/api/productos/mas-vendidos')).map(Producto.fromJson).toList();
  }

  /// Búsqueda por nombre, comida, producto o servicio.
  ///
  /// Con [termino] vacío lista todo (útil con [categoria]).
  Future<List<ResultadoBusqueda>> buscar(String termino, {String? categoria, bool soloDisponibles = false}) async {
    final datos = await _lista('/api/buscar', {
      'q': termino,
      if (categoria != null) 'categoria': categoria,
      if (soloDisponibles) 'soloDisponibles': 'true',
    });
    return datos.map(ResultadoBusqueda.fromJson).toList();
  }

  /// Avisos de inicio.
  Future<List<Aviso>> avisos() async {
    return (await _lista('/api/avisos')).map(Aviso.fromJson).toList();
  }

  // ── Favoritos y calificaciones ────────────────────────────────────────

  /// Ids de negocios favoritos.
  Future<Set<String>> favoritos() async {
    final lista = await _decodificar('GET', '/api/favoritos') as List<dynamic>;
    return {for (final id in lista) id.toString()};
  }

  /// Marca o desmarca un favorito. True si quedó guardado.
  Future<bool> alternarFavorito(String sellerId) async {
    return (await _objeto('POST', '/api/favoritos/$sellerId'))['marcado'] == true;
  }

  /// Publica estrellas y un comentario.
  Future<void> calificar(String productoId, int estrellas, String comentario) async {
    await _objeto('POST', '/api/calificaciones', {
      'productoId': productoId,
      'estrellas': estrellas,
      'comentario': comentario,
    });
  }

  /// Últimas reseñas de un producto.
  Future<List<Calificacion>> calificaciones(String productoId) async {
    return (await _lista('/api/calificaciones', {'producto': productoId})).map(Calificacion.fromJson).toList();
  }

  // ── Panel del vendedor ────────────────────────────────────────────────

  /// Registra el puesto del vendedor en un código del plano.
  Future<void> asignarPunto(String edificio) async {
    await _objeto('POST', '/api/vendedores/punto', {'edificio': edificio});
  }

  /// Abre o cierra el negocio.
  Future<void> disponibilidad(bool disponible) async {
    await _objeto('PATCH', '/api/vendedores/disponibilidad', {'disponible': disponible});
  }

  /// Publica un producto del negocio de la sesión.
  Future<Producto> publicarProducto({required String nombre, required double precio, String? descripcion}) async {
    final datos = await _objeto('POST', '/api/productos', {
      'nombre': nombre,
      'precio': precio,
      'descripcion': descripcion,
    });
    return Producto.fromJson(datos);
  }

  /// Actualiza un producto propio.
  Future<void> actualizarProducto(Producto producto) async {
    await _objeto('PATCH', '/api/productos/${producto.id}', {
      'nombre': producto.nombre,
      'precio': producto.precio,
      'descripcion': producto.descripcion,
      'agotado': producto.agotado,
    });
  }

  /// Borra un producto propio.
  Future<void> eliminarProducto(String id) async {
    await _objeto('DELETE', '/api/productos/$id');
  }

  /// Sube (o reemplaza) la foto de un producto propio. Devuelve su `/medios/...`.
  Future<String> subirFotoProducto(String id, String nombre, String datosBase64) async {
    return (await _objeto('POST', '/api/productos/$id/foto', {'nombre': nombre, 'datos': datosBase64}))['fotoUrl']
        as String;
  }

  /// Quita la foto de un producto propio.
  Future<void> quitarFotoProducto(String id) async {
    await _objeto('DELETE', '/api/productos/$id/foto');
  }

  /// Guarda el horario de atención.
  Future<void> guardarHorario({required String apertura, required String cierre, required String dias}) async {
    await _objeto('PATCH', '/api/vendedores/horario', {'apertura': apertura, 'cierre': cierre, 'dias': dias});
  }

  /// Guarda WhatsApp, Telegram, Instagram y teléfono. Vacío borra el canal.
  Future<void> guardarContacto({String? whatsapp, String? telegram, String? instagram, String? telefonoFijo}) async {
    await _objeto('PATCH', '/api/vendedores/contacto', {
      'whatsapp': whatsapp,
      'telegram': telegram,
      'instagram': instagram,
      'telefonoFijo': telefonoFijo,
    });
  }

  // ── Administración ────────────────────────────────────────────────────

  /// Menús, iconos y fotografías públicos.
  Future<Apariencia> apariencia() async => Apariencia.fromJson(await _objeto('GET', '/api/apariencia'));

  /// Guarda la apariencia. Solo la acepta un administrador.
  Future<Apariencia> guardarApariencia(Apariencia apariencia) async {
    return Apariencia.fromJson(await _objeto('PATCH', '/api/admin/apariencia', apariencia.toJson()));
  }

  /// Crea una cuenta sin cambiar la sesión del administrador.
  Future<Usuario> crearUsuario(Map<String, dynamic> datos) async {
    return Usuario.fromJson(await _objeto('POST', '/api/admin/usuarios', datos));
  }

  /// Sube una imagen y devuelve su ruta `/medios/...`.
  Future<String> subirMedio(String nombre, String datosBase64) async {
    return (await _objeto('POST', '/api/admin/medios', {'nombre': nombre, 'datos': datosBase64}))['url'] as String;
  }

  /// Datos visibles de la conexión. Nunca incluye la contraseña.
  Future<Map<String, dynamic>> conexion() => _objeto('GET', '/api/admin/conexion');

  /// Prueba host, puerto, base, usuario y contraseña sin guardarlos.
  Future<void> probarConexion(Map<String, dynamic> datos) async {
    await _objeto('POST', '/api/admin/conexion/probar', datos);
  }

  /// Guarda la conexión y reconecta el servidor.
  Future<Map<String, dynamic>> guardarConexion(Map<String, dynamic> datos) {
    return _objeto('PATCH', '/api/admin/conexion', datos);
  }

  /// Cuentas para moderación.
  Future<List<Usuario>> usuariosModeracion() async {
    return (await _lista('/api/moderacion/usuarios')).map(Usuario.fromJson).toList();
  }

  /// Bloquea o desbloquea una cuenta.
  Future<void> bloquear(String id, bool bloqueado) async {
    await _objeto('POST', '/api/moderacion/usuarios/$id/bloqueo', {'bloqueado': bloqueado});
  }

  /// Elimina una cuenta. Solo el administrador pasa la regla del servidor.
  Future<void> eliminarUsuario(String id) async {
    await _objeto('DELETE', '/api/moderacion/usuarios/$id');
  }

  // ── Transporte ────────────────────────────────────────────────────────

  ({String token, Usuario usuario}) _sesion(Map<String, dynamic> datos) {
    return (token: datos['token'] as String, usuario: Usuario.fromJson(datos['usuario'] as Map<String, dynamic>));
  }

  /// Respuesta que debe ser un objeto JSON (o vacía).
  Future<Map<String, dynamic>> _objeto(String metodo, String ruta, [Map<String, dynamic>? cuerpo]) async {
    final datos = await _decodificar(metodo, ruta, cuerpo: cuerpo);
    return datos is Map<String, dynamic> ? datos : {};
  }

  /// `GET` cuya respuesta es una lista de objetos.
  Future<List<Map<String, dynamic>>> _lista(String ruta, [Map<String, String>? consulta]) async {
    final datos = await _decodificar('GET', ruta, consulta: consulta);
    return (datos as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Object?> _decodificar(
    String metodo,
    String ruta, {
    Map<String, dynamic>? cuerpo,
    Map<String, String>? consulta,
  }) async {
    final uri = Uri.parse('$baseUrl$ruta').replace(queryParameters: (consulta?.isEmpty ?? true) ? null : consulta);
    final peticion = http.Request(metodo, uri)..headers.addAll(_cabeceras);
    if (cuerpo != null || metodo == 'POST' || metodo == 'PATCH') {
      peticion.body = jsonEncode(cuerpo ?? const {});
    }
    final http.Response respuesta;
    try {
      respuesta = await http.Response.fromStream(await _http.send(peticion).timeout(tiempoLimite));
    } on TimeoutException {
      throw ErrorApi('El servidor tardó demasiado en responder. Inténtalo de nuevo.');
    } on Exception {
      // ClientException en web; SocketException/HandshakeException en móvil y escritorio.
      throw ErrorApi(_sinConexion);
    }
    _verificar(respuesta);
    if (respuesta.body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(_texto(respuesta));
    } on FormatException {
      throw ErrorApi('El servidor respondió algo inesperado.', estado: respuesta.statusCode);
    }
  }

  Map<String, String> get _cabeceras {
    return {
      'content-type': 'application/json; charset=utf-8',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  /// Cuerpo como texto. La API manda UTF-8; si algo intermedio no lo hace,
  /// se usa el charset que declare la respuesta.
  String _texto(http.Response respuesta) {
    try {
      return utf8.decode(respuesta.bodyBytes);
    } on FormatException {
      return respuesta.body;
    }
  }

  void _verificar(http.Response respuesta) {
    final estado = respuesta.statusCode;
    if (estado >= 200 && estado < 300) {
      return;
    }
    // Mensaje si la respuesta no trae {"error": ...} (p. ej. una página de nginx).
    var mensaje = switch (estado) {
      413 => 'El archivo es demasiado grande.',
      >= 500 => 'El servidor no pudo completar la operación.',
      _ => 'El servidor rechazó la petición (código $estado).',
    };
    try {
      final cuerpo = jsonDecode(_texto(respuesta));
      if (cuerpo is Map && cuerpo['error'] is String) {
        mensaje = cuerpo['error'] as String;
      }
    } on FormatException {
      // Respuesta sin JSON (por ejemplo, un 502 de nginx): se queda el genérico.
    }
    throw ErrorApi(mensaje, estado: estado);
  }
}
