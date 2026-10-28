import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/iconos_menu.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import 'sesion_dialogo.dart';

/// Herramientas exclusivas del administrador: cuentas, base de datos y apariencia.
class PanelAdmin extends StatefulWidget {
  /// [alCambiar] recarga la lista de cuentas del perfil.
  const PanelAdmin({super.key, required this.estado, required this.alCambiar});

  /// Sesión con token de administrador.
  final EstadoApp estado;

  /// Avisa al perfil que hay una cuenta nueva.
  final Future<void> Function() alCambiar;

  @override
  State<PanelAdmin> createState() => _PanelAdminState();
}

class _PanelAdminState extends State<PanelAdmin> {
  static const List<(String, String)> _roles = [
    ('comprador', 'Comprador'),
    ('vendedor', 'Vendedor'),
    ('moderador', 'Moderador'),
    ('admin', 'Administrador'),
  ];

  final _formularioCuenta = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _correo = TextEditingController();
  final _password = TextEditingController();
  final _negocio = TextEditingController();
  final _host = TextEditingController();
  final _puerto = TextEditingController();
  final _base = TextEditingController();
  final _usuarioDb = TextEditingController();
  final _contrasenaDb = TextEditingController();
  final _titulo = TextEditingController();
  final _menuInicio = TextEditingController();
  final _menuBusqueda = TextEditingController();
  final _menuMapa = TextEditingController();
  final _menuPerfil = TextEditingController();
  final _logo = TextEditingController();
  final _iconoImagen = TextEditingController();
  final _portada = TextEditingController();
  final _publicidad1 = TextEditingController();
  final _publicidad1Enlace = TextEditingController();
  final _publicidad2 = TextEditingController();
  final _publicidad2Enlace = TextEditingController();

  String _rol = 'comprador';
  String _categoria = 'comida';
  String _iconoInicio = 'home';
  String _iconoBusqueda = 'search';
  String _iconoMapa = 'map';
  String _iconoPerfil = 'person';
  bool _ssl = false;
  bool _conectada = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargarApariencia(widget.estado.apariencia);
    _cargarConexion();
  }

  @override
  void dispose() {
    for (final campo in [
      _nombre, _apellido, _correo, _password, _negocio, _host, _puerto, _base,
      _usuarioDb, _contrasenaDb, _titulo, _menuInicio, _menuBusqueda, _menuMapa,
      _menuPerfil, _logo, _iconoImagen, _portada, _publicidad1, _publicidad1Enlace,
      _publicidad2, _publicidad2Enlace,
    ]) {
      campo.dispose();
    }
    super.dispose();
  }

  void _cargarApariencia(Apariencia menu) {
    _titulo.text = menu.titulo;
    _menuInicio.text = menu.menuInicio;
    _menuBusqueda.text = menu.menuBusqueda;
    _menuMapa.text = menu.menuMapa;
    _menuPerfil.text = menu.menuPerfil;
    _logo.text = menu.logoUrl;
    _iconoImagen.text = menu.iconoUrl;
    _portada.text = menu.fotoPortadaUrl;
    _publicidad1.text = menu.publicidad1Url;
    _publicidad1Enlace.text = menu.publicidad1Enlace;
    _publicidad2.text = menu.publicidad2Url;
    _publicidad2Enlace.text = menu.publicidad2Enlace;
    _iconoInicio = menu.iconoInicio;
    _iconoBusqueda = menu.iconoBusqueda;
    _iconoMapa = menu.iconoMapa;
    _iconoPerfil = menu.iconoPerfil;
  }

  Future<void> _cargarConexion() async {
    try {
      final datos = await widget.estado.api.conexion();
      if (!mounted) {
        return;
      }
      setState(() {
        _host.text = datos['host']?.toString() ?? '';
        _puerto.text = datos['puerto']?.toString() ?? '';
        _base.text = datos['base']?.toString() ?? '';
        _usuarioDb.text = datos['usuario']?.toString() ?? '';
        _ssl = datos['ssl'] == true;
        _conectada = datos['conectada'] == true;
      });
    } on ErrorApi catch (error) {
      if (mounted) {
        mostrarAviso(context, error.mensaje);
      }
    }
  }

  Map<String, dynamic> _datosConexion() {
    return {
      'host': _host.text.trim(),
      'puerto': int.tryParse(_puerto.text.trim()) ?? 0,
      'base': _base.text.trim(),
      'usuario': _usuarioDb.text.trim(),
      'contrasena': _contrasenaDb.text,
      'ssl': _ssl,
    };
  }

  /// Bloquea los botones mientras corre [accion] y avisa el resultado.
  Future<bool> _ejecutar(Future<void> Function() accion, {String? exito}) async {
    setState(() => _ocupado = true);
    final ok = await intentar(context, accion, exito: exito);
    if (mounted) {
      setState(() => _ocupado = false);
    }
    return ok;
  }

  Future<void> _crearCuenta() async {
    if (!(_formularioCuenta.currentState?.validate() ?? false)) {
      return;
    }
    final ok = await _ejecutar(
      () => widget.estado.api.crearUsuario({
        'nombre': _nombre.text,
        'apellido': _apellido.text,
        'correo': _correo.text,
        'password': _password.text,
        'rol': _rol,
        if (_rol == 'vendedor') 'nombreNegocio': _negocio.text,
        if (_rol == 'vendedor') 'categoria': _categoria,
      }),
      exito: 'Cuenta creada.',
    );
    if (ok) {
      for (final campo in [_nombre, _apellido, _correo, _password, _negocio]) {
        campo.clear();
      }
      await widget.alCambiar();
    }
  }

  Future<void> _probar() async {
    await _ejecutar(() => widget.estado.api.probarConexion(_datosConexion()), exito: 'La base de datos respondió.');
  }

  Future<void> _guardarConexion() async {
    await _ejecutar(() async {
      final datos = await widget.estado.api.guardarConexion(_datosConexion());
      _contrasenaDb.clear();
      _conectada = datos['conectada'] == true;
    }, exito: 'Conexión guardada.');
  }

  Future<void> _restaurarEntorno() async {
    final seguro = await confirmar(
      context,
      titulo: 'Usar la conexión del servidor',
      mensaje: 'Se descartará la conexión guardada aquí y se volverá a usar DATABASE_URL del entorno.',
      accion: 'Restaurar',
    );
    if (!seguro) {
      return;
    }
    final ok = await _ejecutar(
      () => widget.estado.api.guardarConexion({'restaurarEntorno': true}),
      exito: 'Se volvió a usar la conexión del servidor.',
    );
    if (ok) {
      await _cargarConexion();
    }
  }

  Future<void> _guardarApariencia() async {
    await _ejecutar(() async {
      final guardada = await widget.estado.api.guardarApariencia(Apariencia(
        titulo: _titulo.text.trim(),
        menuInicio: _menuInicio.text.trim(),
        menuBusqueda: _menuBusqueda.text.trim(),
        menuMapa: _menuMapa.text.trim(),
        menuPerfil: _menuPerfil.text.trim(),
        iconoInicio: _iconoInicio,
        iconoBusqueda: _iconoBusqueda,
        iconoMapa: _iconoMapa,
        iconoPerfil: _iconoPerfil,
        logoUrl: _logo.text.trim(),
        iconoUrl: _iconoImagen.text.trim(),
        fotoPortadaUrl: _portada.text.trim(),
        publicidad1Url: _publicidad1.text.trim(),
        publicidad1Enlace: _publicidad1Enlace.text.trim(),
        publicidad2Url: _publicidad2.text.trim(),
        publicidad2Enlace: _publicidad2Enlace.text.trim(),
      ));
      widget.estado.aplicarApariencia(guardada);
    }, exito: 'Apariencia publicada.');
  }

  Future<void> _subir(TextEditingController destino) async {
    final elegido = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final archivo = elegido?.files.single;
    final bytes = archivo?.bytes;
    if (archivo == null || bytes == null || !mounted) {
      return;
    }
    // Mismo límite que servidor/lib/medios.dart.
    if (bytes.length > 1500000) {
      mostrarAviso(context, 'La imagen pesa más de 1.5 MB. Redúcela e inténtalo de nuevo.');
      return;
    }
    await _ejecutar(() async {
      destino.text = await widget.estado.api.subirMedio(archivo.name, base64Encode(bytes));
    }, exito: 'Imagen subida. Toca "Publicar apariencia" para mostrarla.');
  }

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: Espacio.m);
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_ocupado) const LinearProgressIndicator(),
        _Herramienta(
          icono: Icons.person_add_alt,
          titulo: 'Crear cuentas',
          subtitulo: 'Compradores, vendedores, moderadores o administradores',
          children: [
            Form(
              key: _formularioCuenta,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _nombre,
                          decoration: const InputDecoration(labelText: 'Nombre'),
                          validator: Validar.requerido,
                        ),
                      ),
                      const SizedBox(width: Espacio.s),
                      Expanded(
                        child: TextFormField(
                          controller: _apellido,
                          decoration: const InputDecoration(labelText: 'Apellido'),
                          validator: Validar.requerido,
                        ),
                      ),
                    ],
                  ),
                  separacion,
                  TextFormField(
                    controller: _correo,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: Validar.correo,
                  ),
                  separacion,
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña inicial'),
                    validator: Validar.password,
                  ),
                  separacion,
                  DropdownButtonFormField<String>(
                    initialValue: _rol,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: [for (final (valor, etiqueta) in _roles) DropdownMenuItem(value: valor, child: Text(etiqueta))],
                    onChanged: _ocupado ? null : (valor) => setState(() => _rol = valor ?? 'comprador'),
                  ),
                  if (_rol == 'vendedor') ...[
                    separacion,
                    TextFormField(
                      controller: _negocio,
                      decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                      validator: Validar.requerido,
                    ),
                    separacion,
                    DropdownButtonFormField<String>(
                      initialValue: _categoria,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: [
                        for (final (valor, etiqueta) in categoriasNegocio)
                          DropdownMenuItem(value: valor, child: Text(etiqueta)),
                      ],
                      onChanged: _ocupado ? null : (valor) => setState(() => _categoria = valor ?? 'comida'),
                    ),
                  ],
                ],
              ),
            ),
            separacion,
            FilledButton(onPressed: _ocupado ? null : _crearCuenta, child: const Text('Crear cuenta')),
          ],
        ),
        _Herramienta(
          icono: _conectada ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          color: _conectada ? ColoresLiebre.abierto(Theme.of(context).brightness) : esquema.error,
          titulo: 'Base de datos',
          subtitulo: _conectada ? 'Conectada' : 'Sin conexión',
          children: [
            Text(
              'Normalmente se configura con DATABASE_URL en Coolify. Cambiarla aquí solo hace falta para mover los datos a otro servidor.',
              style: TextStyle(color: esquema.onSurfaceVariant),
            ),
            separacion,
            Row(
              children: [
                Expanded(flex: 3, child: TextField(controller: _host, decoration: const InputDecoration(labelText: 'Host'))),
                const SizedBox(width: Espacio.s),
                Expanded(
                  child: TextField(
                    controller: _puerto,
                    decoration: const InputDecoration(labelText: 'Puerto'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            separacion,
            TextField(controller: _base, decoration: const InputDecoration(labelText: 'Base')),
            separacion,
            TextField(controller: _usuarioDb, decoration: const InputDecoration(labelText: 'Usuario')),
            separacion,
            TextField(
              controller: _contrasenaDb,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña', helperText: 'Vacía conserva la actual.'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ssl,
              title: const Text('Exigir SSL'),
              onChanged: _ocupado ? null : (valor) => setState(() => _ssl = valor),
            ),
            Wrap(
              spacing: Espacio.s,
              runSpacing: Espacio.s,
              children: [
                OutlinedButton(onPressed: _ocupado ? null : _probar, child: const Text('Probar')),
                FilledButton(onPressed: _ocupado ? null : _guardarConexion, child: const Text('Guardar y reconectar')),
                TextButton(onPressed: _ocupado ? null : _restaurarEntorno, child: const Text('Usar la del servidor')),
              ],
            ),
          ],
        ),
        _Herramienta(
          icono: Icons.palette_outlined,
          titulo: 'Apariencia',
          subtitulo: 'Nombre, menús, iconos y fotografías',
          children: [
            TextField(controller: _titulo, decoration: const InputDecoration(labelText: 'Nombre de la aplicación')),
            separacion,
            _filaMenu(_menuInicio, 'Menú inicio', _iconoInicio, (valor) => _iconoInicio = valor),
            _filaMenu(_menuBusqueda, 'Menú búsqueda', _iconoBusqueda, (valor) => _iconoBusqueda = valor),
            _filaMenu(_menuMapa, 'Menú mapa', _iconoMapa, (valor) => _iconoMapa = valor),
            _foto('Logo', _logo),
            _foto('Icono', _iconoImagen),
            _foto('Fotografía de portada', _portada),
            const Divider(),
            Text('Publicidad de la barra lateral', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Espacio.xs),
            Text(
              'Se ve en pantallas amplias, en dos espacios del mismo alto. Usa imágenes verticales '
              '(por ejemplo 160 × 300 px). Sin imagen se muestra "Anúnciate aquí".',
              style: TextStyle(color: esquema.onSurfaceVariant),
            ),
            separacion,
            _foto('anuncio de arriba', _publicidad1),
            _enlace(_publicidad1Enlace),
            _foto('anuncio de abajo', _publicidad2),
            _enlace(_publicidad2Enlace),
            separacion,
            FilledButton.icon(
              onPressed: _ocupado ? null : _guardarApariencia,
              icon: const Icon(Icons.publish),
              label: const Text('Publicar apariencia'),
            ),
          ],
        ),
      ],
    );
  }

  /// Texto de la pestaña y su icono en la misma fila.
  Widget _filaMenu(TextEditingController campo, String etiqueta, String icono, ValueChanged<String> alElegir) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.m),
      child: Row(
        children: [
          Expanded(child: TextField(controller: campo, decoration: InputDecoration(labelText: etiqueta))),
          const SizedBox(width: Espacio.s),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: nombresDeIcono.containsKey(icono) ? icono : 'home',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Icono'),
              items: [
                for (final entrada in nombresDeIcono.entries)
                  DropdownMenuItem(
                    value: entrada.key,
                    child: Row(children: [
                      Icon(iconoMenu(entrada.key, activo: true), size: 20),
                      const SizedBox(width: Espacio.s),
                      Flexible(child: Text(entrada.value, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
              ],
              onChanged: _ocupado ? null : (valor) => setState(() => alElegir(valor ?? icono)),
            ),
          ),
        ],
      ),
    );
  }

  /// Página que abre el anuncio al tocarlo. Vacío: el anuncio no abre nada.
  Widget _enlace(TextEditingController campo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.l),
      child: TextField(
        controller: campo,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Enlace del anuncio (opcional)',
          hintText: 'https://…',
          prefixIcon: Icon(Icons.link),
        ),
      ),
    );
  }

  Widget _foto(String etiqueta, TextEditingController campo) {
    final ruta = campo.text.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: campo,
            decoration: InputDecoration(
              labelText: 'URL de $etiqueta',
              suffixIcon: IconButton(
                tooltip: 'Subir $etiqueta',
                onPressed: _ocupado ? null : () => _subir(campo),
                icon: const Icon(Icons.upload_file),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (ruta.isNotEmpty) ...[
            const SizedBox(height: Espacio.s),
            ImagenRed(
              ruta,
              alto: 88,
              ancho: double.infinity,
              respaldo: const Text('No se pudo mostrar la imagen.'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta plegable de una herramienta del administrador.
class _Herramienta extends StatelessWidget {
  const _Herramienta({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.children,
    this.color,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.m),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: Icon(icono, color: color),
          title: Text(titulo),
          subtitle: Text(subtitulo),
          childrenPadding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.l),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
