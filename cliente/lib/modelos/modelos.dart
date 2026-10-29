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
    this.creadoEn,
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

  /// Fecha de registro, si la API la mandó.
  final DateTime? creadoEn;

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

  /// Copia de la cuenta con otro [rol].
  ///
  /// La usa la vista previa (`EstadoApp.vista`) para mostrar la app como la ve
  /// ese rol. No cambia nada en el servidor: la API sigue usando el rol real.
  Usuario conRol(String rol) {
    return Usuario(
      id: id,
      nombre: nombre,
      apellido: apellido,
      correo: correo,
      rol: rol,
      telefono: telefono,
      numeroControl: numeroControl,
      carrera: carrera,
      fotoPerfilUrl: fotoPerfilUrl,
      bloqueado: bloqueado,
      perfilEditable: perfilEditable,
      correoVerificado: correoVerificado,
      creadoEn: creadoEn,
    );
  }

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
      creadoEn: DateTime.tryParse(json['creadoEn'] as String? ?? ''),
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
    this.destacadoHasta,
    this.horarioApertura,
    this.horarioCierre,
    this.diasAtencion,
    this.whatsapp,
    this.telegram,
    this.instagram,
    this.telefonoFijo,
    this.promedioEstrellas = 0,
    this.totalResenas = 0,
    this.ultimoAcceso,
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

  /// Fin de la promoción; null = sin fecha de fin.
  final DateTime? destacadoHasta;

  /// Último uso de la app de la cuenta dueña. Solo lo manda `GET /api/admin/vendedores`.
  final DateTime? ultimoAcceso;

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
      destacadoHasta: DateTime.tryParse(json['destacadoHasta'] as String? ?? ''),
      horarioApertura: json['horarioApertura'] as String?,
      horarioCierre: json['horarioCierre'] as String?,
      diasAtencion: json['diasAtencion'] as String?,
      whatsapp: json['whatsapp'] as String?,
      telegram: json['telegram'] as String?,
      instagram: json['instagram'] as String?,
      telefonoFijo: json['telefonoFijo'] as String?,
      promedioEstrellas: (json['promedioEstrellas'] as num?)?.toDouble() ?? 0,
      totalResenas: (json['totalResenas'] as num?)?.toInt() ?? 0,
      ultimoAcceso: DateTime.tryParse(json['ultimoAcceso'] as String? ?? '')?.toLocal(),
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
  ///
  /// Los anuncios ya no son parte de la apariencia: ver [Anuncio].
  final String fotoPortadaUrl;

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
    };
  }
}

/// Aviso institucional de la pantalla de inicio.
class Aviso {
  /// Título y cuerpo publicados por la administración.
  Aviso({this.id = '', required this.titulo, required this.contenido, this.activo = true, this.publicadoEn});

  /// Id del aviso (lo usa el panel de administración para editarlo).
  final String id;

  /// Encabezado corto.
  final String titulo;

  /// Texto del aviso.
  final String contenido;

  /// Se muestra en Inicio. `GET /api/avisos` solo trae los activos.
  final bool activo;

  /// Fecha de publicación.
  final DateTime? publicadoEn;

  /// Construye desde el JSON de la API.
  factory Aviso.fromJson(Map<String, dynamic> json) {
    return Aviso(
      id: json['id'] as String? ?? '',
      titulo: json['titulo'] as String,
      contenido: json['contenido'] as String,
      activo: json['activo'] != false,
      publicadoEn: DateTime.tryParse(json['publicadoEn'] as String? ?? ''),
    );
  }
}

/// Un anuncio de los carruseles de publicidad (`GET /api/anuncios`).
///
/// Hay [Anuncio.secciones] carruseles con hasta [Anuncio.porSeccion] imágenes
/// cada uno. Si tiene [vendedor], tocarlo abre la ficha de ese negocio en la
/// app. Mismos límites que `seccionesPublicidad`/`anunciosPorSeccion` en
/// `servidor/lib/apariencia.dart`.
class Anuncio {
  /// Posición, imagen y negocio enlazado.
  Anuncio({required this.seccion, required this.posicion, required this.imagenUrl, this.vendedor});

  /// Carruseles de la barra lateral (1 = arriba, 2 = abajo).
  static const int secciones = 2;

  /// Imágenes por carrusel.
  static const int porSeccion = 3;

  /// 1 o 2.
  final int seccion;

  /// 1, 2 o 3: orden dentro del carrusel.
  final int posicion;

  /// `/medios/...` o URL completa.
  final String imagenUrl;

  /// Negocio anunciado, o null si el anuncio no abre nada.
  final Vendedor? vendedor;

  /// Construye desde el JSON de la API.
  factory Anuncio.fromJson(Map<String, dynamic> json) {
    final vendedor = json['vendedor'];
    return Anuncio(
      seccion: (json['seccion'] as num).toInt(),
      posicion: (json['posicion'] as num).toInt(),
      imagenUrl: json['imagenUrl'] as String? ?? '',
      vendedor: vendedor is Map<String, dynamic> ? Vendedor.fromJson(vendedor) : null,
    );
  }
}

/// Solicitud de restablecimiento de contraseña, para el panel de administración.
class Restablecimiento {
  /// Datos de `GET /api/admin/restablecimientos`.
  Restablecimiento({
    required this.id,
    required this.userId,
    required this.nombre,
    required this.correo,
    required this.origen,
    required this.estado,
    this.creadoEn,
    this.venceEn,
    this.usadoEn,
  });

  /// Id de la solicitud.
  final String id;

  /// Cuenta a la que pertenece.
  final String userId;

  /// Nombre completo de la cuenta.
  final String nombre;

  /// Correo de la cuenta.
  final String correo;

  /// `correo` (la pidió la persona) o `admin`.
  final String origen;

  /// `pendiente`, `usado`, `vencido` o `anulado`.
  final String estado;

  /// Cuándo se pidió.
  final DateTime? creadoEn;

  /// Cuándo deja de servir el enlace.
  final DateTime? venceEn;

  /// Cuándo se cambió la contraseña con ella.
  final DateTime? usadoEn;

  /// Todavía se puede anular.
  bool get pendiente => estado == 'pendiente';

  /// Construye desde el JSON de la API.
  factory Restablecimiento.fromJson(Map<String, dynamic> json) {
    DateTime? fecha(String clave) => DateTime.tryParse(json[clave] as String? ?? '');
    return Restablecimiento(
      id: json['id'] as String,
      userId: json['userId'] as String,
      nombre: json['nombre'] as String? ?? '',
      correo: json['correo'] as String? ?? '',
      origen: json['origen'] as String? ?? '',
      estado: json['estado'] as String? ?? '',
      creadoEn: fecha('creadoEn'),
      venceEn: fecha('venceEn'),
      usadoEn: fecha('usadoEn'),
    );
  }
}

/// Reseña vista desde el panel de administración, con producto, negocio y autor.
class ResenaAdmin {
  /// Datos de `GET /api/admin/calificaciones`.
  ResenaAdmin({
    required this.productoId,
    required this.autorId,
    required this.estrellas,
    required this.producto,
    required this.nombreNegocio,
    required this.autor,
    required this.correo,
    this.comentario,
    this.creadoEn,
  });

  /// Producto calificado.
  final String productoId;

  /// Cuenta que escribió la reseña.
  final String autorId;

  /// De 1 a 5.
  final int estrellas;

  /// Nombre del producto.
  final String producto;

  /// Negocio del producto.
  final String nombreNegocio;

  /// Nombre completo del autor.
  final String autor;

  /// Correo del autor.
  final String correo;

  /// Texto libre.
  final String? comentario;

  /// Fecha.
  final DateTime? creadoEn;

  /// Construye desde el JSON de la API.
  factory ResenaAdmin.fromJson(Map<String, dynamic> json) {
    return ResenaAdmin(
      productoId: json['productoId'] as String,
      autorId: json['autorId'] as String,
      estrellas: (json['estrellas'] as num?)?.toInt() ?? 0,
      producto: json['producto'] as String? ?? '',
      nombreNegocio: json['nombreNegocio'] as String? ?? '',
      autor: json['autor'] as String? ?? '',
      correo: json['correo'] as String? ?? '',
      comentario: json['comentario'] as String?,
      creadoEn: DateTime.tryParse(json['creadoEn'] as String? ?? ''),
    );
  }
}

/// Una página de una tabla del explorador de registros (solo lectura).
class PaginaTabla {
  /// Datos de `GET /api/admin/tablas/<tabla>`.
  PaginaTabla({
    required this.tabla,
    required this.columnas,
    required this.filas,
    required this.total,
    required this.pagina,
    required this.limite,
  });

  /// Nombre SQL de la tabla.
  final String tabla;

  /// Nombres de columna, en orden.
  final List<String> columnas;

  /// Valores de cada fila, en el orden de [columnas].
  final List<List<Object?>> filas;

  /// Filas totales en la tabla.
  final int total;

  /// Página actual, desde 1.
  final int pagina;

  /// Filas por página.
  final int limite;

  /// Número de páginas (al menos 1).
  int get paginas => total == 0 ? 1 : (total / limite).ceil();

  /// Construye desde el JSON de la API.
  factory PaginaTabla.fromJson(Map<String, dynamic> json) {
    return PaginaTabla(
      tabla: json['tabla'] as String,
      columnas: [for (final columna in json['columnas'] as List<dynamic>) columna.toString()],
      filas: [for (final fila in json['filas'] as List<dynamic>) List<Object?>.from(fila as List<dynamic>)],
      total: (json['total'] as num).toInt(),
      pagina: (json['pagina'] as num).toInt(),
      limite: (json['limite'] as num).toInt(),
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
