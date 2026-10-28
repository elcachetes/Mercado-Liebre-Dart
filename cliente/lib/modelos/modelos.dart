/// Entidades que la interfaz muestra. Llegan como JSON de la API.
///
/// Las claves JSON van en camelCase y las arma `servidor/lib/repositorio.dart`
/// (`_usuario`, `_vendedor`, `_producto`). Si agregas un campo allá,
/// agrégalo aquí en el constructor, el campo y `fromJson`.
library;

import 'package:flutter/widgets.dart' show StringCharacters;

/// Cuenta de una persona. No incluye la contraseña.
class Usuario {
  /// Arma el objeto con los campos que devuelve `GET /api/yo`.
  Usuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.correo,
    required this.rol,
    this.telefono,
    this.numeroControl,
    this.carrera,
    this.fotoPerfilUrl,
    this.bloqueado = false,
    this.perfilEditable = false,
    this.correoVerificado = true,
  });

  /// Identificador UUID.
  final String id;

  /// Nombre de pila.
  final String nombre;

  /// Apellido.
  final String apellido;

  /// Correo de acceso.
  final String correo;

  /// `admin`, `moderador`, `vendedor` o `comprador`.
  final String rol;

  /// Teléfono opcional.
  final String? telefono;

  /// Número de control del ITCJ.
  final String? numeroControl;

  /// Carrera.
  final String? carrera;

  /// URL de la foto, si existe.
  final String? fotoPerfilUrl;

  /// La moderación impide entrar cuando es verdadero.
  final bool bloqueado;

  /// Un moderador autorizó editar los datos personales.
  final bool perfilEditable;

  /// Abrió el enlace del correo de verificación. Sin esto no califica ni comenta.
  final bool correoVerificado;

  /// Nombre y apellido juntos.
  String get nombreCompleto => '$nombre $apellido'.trim();

  /// Etiqueta del rol para la interfaz.
  String get rolEtiqueta {
    switch (rol) {
      case 'admin':
        return 'Administrador';
      case 'moderador':
        return 'Gestor / Moderador';
      case 'vendedor':
        return 'Vendedor';
      default:
        return 'Comprador';
    }
  }

  /// Verdadero si puede registrar un puesto en el mapa.
  bool get esVendedor => rol == 'vendedor';

  /// Verdadero si ve el panel de bloqueo.
  bool get esModerador => rol == 'admin' || rol == 'moderador';

  /// Verdadero si ve el panel de administración.
  bool get esAdmin => rol == 'admin';

  /// Inicial para el avatar.
  String get inicial => nombre.isEmpty ? '?' : nombre.characters.first.toUpperCase();

  /// Construye desde el JSON de la API.
  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      apellido: json['apellido'] as String,
      correo: json['correo'] as String,
      rol: json['rol'] as String,
      telefono: json['telefono'] as String?,
      numeroControl: json['numeroControl'] as String?,
      carrera: json['carrera'] as String?,
      fotoPerfilUrl: json['fotoPerfilUrl'] as String?,
      bloqueado: json['bloqueado'] == true,
      perfilEditable: json['perfilEditable'] == true,
      correoVerificado: json['correoVerificado'] != false,
    );
  }
}

/// Negocio publicado dentro del plantel.
class Vendedor {
  /// Campos visibles en tarjetas y en el mapa.
  Vendedor({
    required this.id,
    required this.userId,
    required this.nombreNegocio,
    required this.categoria,
    this.subtipo,
    this.descripcion,
    required this.horarioTexto,
    required this.disponible,
    this.edificio,
    required this.destacado,
    this.horarioApertura,
    this.horarioCierre,
    this.diasAtencion,
    this.whatsapp,
    this.telegram,
    this.instagram,
    this.telefonoFijo,
    this.promedioEstrellas = 0,
    this.totalResenas = 0,
  });

  /// Id del negocio.
  final String id;

  /// Id de la cuenta dueña.
  final String userId;

  /// Nombre comercial.
  final String nombreNegocio;

  /// `producto`, `comida` o `servicio`.
  final String categoria;

  /// Especialidad, por ejemplo "comida mexicana".
  final String? subtipo;

  /// Texto corto del negocio.
  final String? descripcion;

  /// Horario ya formateado por la API.
  final String horarioTexto;

  /// Abierto en este momento.
  final bool disponible;

  /// Código del plano: A, Q, 8, Z…
  final String? edificio;

  /// Pagó por aparecer destacado.
  final bool destacado;

  /// Hora de apertura `HH:mm`, si el vendedor la definió.
  final String? horarioApertura;

  /// Hora de cierre `HH:mm`.
  final String? horarioCierre;

  /// Días en texto libre, por ejemplo `Lun-Vie`.
  final String? diasAtencion;

  /// WhatsApp, si lo publicó.
  final String? whatsapp;

  /// Telegram, si lo publicó.
  final String? telegram;

  /// Instagram, si lo publicó.
  final String? instagram;

  /// Teléfono fijo, si lo publicó.
  final String? telefonoFijo;

  /// Promedio de estrellas de todos sus productos (0 si no tiene reseñas).
  final double promedioEstrellas;

  /// Reseñas recibidas en todos sus productos.
  final int totalResenas;

  /// Canales de contacto publicados, en orden de preferencia: (canal, valor).
  List<(String, String)> get contactos => [
        if ((whatsapp ?? '').isNotEmpty) ('WhatsApp', whatsapp!),
        if ((telegram ?? '').isNotEmpty) ('Telegram', telegram!),
        if ((instagram ?? '').isNotEmpty) ('Instagram', instagram!),
        if ((telefonoFijo ?? '').isNotEmpty) ('Teléfono', telefonoFijo!),
      ];

  /// Nombre legible de la categoría.
  String get categoriaEtiqueta {
    switch (categoria) {
      case 'comida':
        return 'Comida';
      case 'servicio':
        return 'Servicio';
      default:
        return 'Producto';
    }
  }

  /// Construye desde el JSON de la API.
  factory Vendedor.fromJson(Map<String, dynamic> json) {
    return Vendedor(
      id: json['id'] as String,
      userId: json['userId'] as String,
      nombreNegocio: json['nombreNegocio'] as String,
      categoria: json['categoria'] as String,
      subtipo: json['subtipo'] as String?,
      descripcion: json['descripcion'] as String?,
      horarioTexto: (json['horarioTexto'] ?? 'Horario no especificado') as String,
      disponible: json['disponible'] == true,
      edificio: json['edificio'] as String?,
      destacado: json['destacado'] == true,
      horarioApertura: json['horarioApertura'] as String?,
      horarioCierre: json['horarioCierre'] as String?,
      diasAtencion: json['diasAtencion'] as String?,
      whatsapp: json['whatsapp'] as String?,
      telegram: json['telegram'] as String?,
      instagram: json['instagram'] as String?,
      telefonoFijo: json['telefonoFijo'] as String?,
      promedioEstrellas: (json['promedioEstrellas'] as num?)?.toDouble() ?? 0,
      totalResenas: (json['totalResenas'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Producto, platillo o servicio de un vendedor.
class Producto {
  /// Datos de catálogo y de calificación.
  Producto({
    required this.id,
    required this.sellerId,
    required this.nombre,
    this.descripcion,
    this.fotoUrl,
    required this.precio,
    required this.agotado,
    required this.vecesVendido,
    required this.promedioEstrellas,
    required this.totalResenas,
  });

  /// Id del producto.
  final String id;

  /// Negocio al que pertenece.
  final String sellerId;

  /// Nombre que ve el comprador.
  final String nombre;

  /// Detalle opcional.
  final String? descripcion;

  /// Fotografía `/medios/...`, o null si el vendedor no subió una.
  final String? fotoUrl;

  /// Precio en pesos.
  final double precio;

  /// Ya no se puede pedir.
  final bool agotado;

  /// Veces registrado como vendido.
  final int vecesVendido;

  /// Promedio de 1 a 5.
  final double promedioEstrellas;

  /// Cuántas reseñas forman el promedio.
  final int totalResenas;

  /// Precio con dos decimales.
  String get precioFormateado => '\$${precio.toStringAsFixed(2)} MXN';

  /// Copia con los campos que el vendedor puede editar.
  Producto copyWith({String? nombre, String? descripcion, double? precio, bool? agotado}) {
    return Producto(
      id: id,
      sellerId: sellerId,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      fotoUrl: fotoUrl,
      precio: precio ?? this.precio,
      agotado: agotado ?? this.agotado,
      vecesVendido: vecesVendido,
      promedioEstrellas: promedioEstrellas,
      totalResenas: totalResenas,
    );
  }

  /// Construye desde el JSON de la API.
  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'] as String,
      sellerId: json['sellerId'] as String,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      fotoUrl: json['fotoUrl'] as String?,
      precio: (json['precio'] as num).toDouble(),
      agotado: json['agotado'] == true,
      vecesVendido: json['vecesVendido'] as int? ?? 0,
      promedioEstrellas: (json['promedioEstrellas'] as num?)?.toDouble() ?? 0,
      totalResenas: json['totalResenas'] as int? ?? 0,
    );
  }
}

/// Un vendedor y los productos que coincidieron con la búsqueda.
class ResultadoBusqueda {
  /// Agrupa la ficha y el tipo de coincidencia.
  ResultadoBusqueda({
    required this.vendedor,
    required this.productos,
    required this.coincidenciaExacta,
  });

  /// Negocio encontrado.
  final Vendedor vendedor;

  /// Productos cuyo nombre contiene el término.
  final List<Producto> productos;

  /// El nombre del negocio o de un producto es idéntico al término.
  final bool coincidenciaExacta;

  /// Construye desde el JSON de `GET /api/buscar`.
  factory ResultadoBusqueda.fromJson(Map<String, dynamic> json) {
    return ResultadoBusqueda(
      vendedor: Vendedor.fromJson(json['vendedor'] as Map<String, dynamic>),
      productos: (json['productos'] as List<dynamic>)
          .map((item) => Producto.fromJson(item as Map<String, dynamic>))
          .toList(),
      coincidenciaExacta: json['coincidenciaExacta'] == true,
    );
  }
}

/// Textos, iconos y fotografías que el administrador puede cambiar.
class Apariencia {
  /// Valores ya resueltos, con predeterminados si la API no contestó.
  Apariencia({
    required this.titulo,
    required this.menuInicio,
    required this.menuBusqueda,
    required this.menuMapa,
    required this.menuPerfil,
    required this.iconoInicio,
    required this.iconoBusqueda,
    required this.iconoMapa,
    required this.iconoPerfil,
    required this.logoUrl,
    required this.iconoUrl,
    required this.fotoPortadaUrl,
    this.publicidad1Url = '',
    this.publicidad1Enlace = '',
    this.publicidad2Url = '',
    this.publicidad2Enlace = '',
  });

  /// Nombre de la app en la barra superior.
  final String titulo;

  /// Etiqueta de la pestaña de inicio.
  final String menuInicio;

  /// Etiqueta de la pestaña de búsqueda.
  final String menuBusqueda;

  /// Etiqueta de la pestaña del mapa.
  final String menuMapa;

  /// Etiqueta de la pestaña de perfil.
  final String menuPerfil;

  /// Clave del icono de inicio.
  final String iconoInicio;

  /// Clave del icono de búsqueda.
  final String iconoBusqueda;

  /// Clave del icono del mapa.
  final String iconoMapa;

  /// Clave del icono de perfil.
  final String iconoPerfil;

  /// URL del logo, vacía si no hay.
  final String logoUrl;

  /// URL del icono de la marca, vacía si no hay.
  final String iconoUrl;

  /// URL de la fotografía de portada, vacía si no hay.
  final String fotoPortadaUrl;

  /// Imagen del anuncio de arriba en la barra lateral. Vacía muestra "Anúnciate aquí".
  final String publicidad1Url;

  /// Página que abre el anuncio de arriba, vacía si no abre nada.
  final String publicidad1Enlace;

  /// Imagen del anuncio de abajo en la barra lateral.
  final String publicidad2Url;

  /// Página que abre el anuncio de abajo.
  final String publicidad2Enlace;

  /// Apariencia de fábrica, usada si la API no responde.
  factory Apariencia.predeterminada() {
    return Apariencia(
      titulo: 'Mercado Liebre',
      menuInicio: 'Inicio',
      menuBusqueda: 'Búsqueda',
      menuMapa: 'Mapa',
      menuPerfil: 'Perfil',
      iconoInicio: 'home',
      iconoBusqueda: 'search',
      iconoMapa: 'map',
      iconoPerfil: 'person',
      logoUrl: '',
      iconoUrl: '',
      fotoPortadaUrl: '',
    );
  }

  /// Construye desde `GET /api/apariencia`.
  factory Apariencia.fromJson(Map<String, dynamic> json) {
    final base = Apariencia.predeterminada();
    String texto(String clave, String respaldo) {
      final valor = json[clave];
      if (valor is! String || valor.trim().isEmpty) {
        return respaldo;
      }
      return valor;
    }

    return Apariencia(
      titulo: texto('titulo', base.titulo),
      menuInicio: texto('menuInicio', base.menuInicio),
      menuBusqueda: texto('menuBusqueda', base.menuBusqueda),
      menuMapa: texto('menuMapa', base.menuMapa),
      menuPerfil: texto('menuPerfil', base.menuPerfil),
      iconoInicio: texto('iconoInicio', base.iconoInicio),
      iconoBusqueda: texto('iconoBusqueda', base.iconoBusqueda),
      iconoMapa: texto('iconoMapa', base.iconoMapa),
      iconoPerfil: texto('iconoPerfil', base.iconoPerfil),
      logoUrl: json['logoUrl'] as String? ?? '',
      iconoUrl: json['iconoUrl'] as String? ?? '',
      fotoPortadaUrl: json['fotoPortadaUrl'] as String? ?? '',
      publicidad1Url: json['publicidad1Url'] as String? ?? '',
      publicidad1Enlace: json['publicidad1Enlace'] as String? ?? '',
      publicidad2Url: json['publicidad2Url'] as String? ?? '',
      publicidad2Enlace: json['publicidad2Enlace'] as String? ?? '',
    );
  }

  /// Cuerpo para guardar los cambios.
  Map<String, dynamic> toJson() {
    return {
      'titulo': titulo,
      'menuInicio': menuInicio,
      'menuBusqueda': menuBusqueda,
      'menuMapa': menuMapa,
      'menuPerfil': menuPerfil,
      'iconoInicio': iconoInicio,
      'iconoBusqueda': iconoBusqueda,
      'iconoMapa': iconoMapa,
      'iconoPerfil': iconoPerfil,
      'logoUrl': logoUrl,
      'iconoUrl': iconoUrl,
      'fotoPortadaUrl': fotoPortadaUrl,
      'publicidad1Url': publicidad1Url,
      'publicidad1Enlace': publicidad1Enlace,
      'publicidad2Url': publicidad2Url,
      'publicidad2Enlace': publicidad2Enlace,
    };
  }
}

/// Aviso institucional de la pantalla de inicio.
class Aviso {
  /// Título y cuerpo publicados por la administración.
  Aviso({required this.titulo, required this.contenido});

  /// Encabezado corto.
  final String titulo;

  /// Texto del aviso.
  final String contenido;

  /// Construye desde el JSON de la API.
  factory Aviso.fromJson(Map<String, dynamic> json) {
    return Aviso(
      titulo: json['titulo'] as String,
      contenido: json['contenido'] as String,
    );
  }
}

/// Reseña de un producto, tal como la muestra `GET /api/calificaciones`.
class Calificacion {
  /// Estrellas, comentario opcional y quién la escribió.
  Calificacion({required this.estrellas, required this.nombre, this.comentario, this.creadoEn});

  /// De 1 a 5.
  final int estrellas;

  /// Nombre de pila de quien calificó.
  final String nombre;

  /// Texto libre, puede faltar.
  final String? comentario;

  /// Fecha de la reseña.
  final DateTime? creadoEn;

  /// Construye desde el JSON de la API.
  factory Calificacion.fromJson(Map<String, dynamic> json) {
    return Calificacion(
      estrellas: (json['estrellas'] as num?)?.toInt() ?? 0,
      nombre: json['nombre'] as String? ?? 'Anónimo',
      comentario: json['comentario'] as String?,
      creadoEn: DateTime.tryParse(json['creadoEn'] as String? ?? ''),
    );
  }
}
