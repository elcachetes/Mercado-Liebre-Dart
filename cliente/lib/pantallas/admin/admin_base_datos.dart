import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';

/// Base de datos: conexión a PostgreSQL y explorador de registros (solo lectura).
///
/// El explorador muestra las tablas de `Repositorio.tablasVisibles` en el
/// servidor; nunca la columna `password_hash`. Para modificar registros se
/// usan las demás pestañas, que aplican las reglas de negocio.
class AdminBaseDatos extends StatelessWidget {
  /// Sesión de administrador.
  const AdminBaseDatos({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        AnchoLimitado(child: _Conexion(estado: estado)),
        const SizedBox(height: Espacio.l),
        _Registros(estado: estado),
      ],
    );
  }
}

/// Host, puerto, base, usuario y SSL. Probar, guardar o volver a la del servidor.
class _Conexion extends StatefulWidget {
  const _Conexion({required this.estado});

  final EstadoApp estado;

  @override
  State<_Conexion> createState() => _ConexionState();
}

class _ConexionState extends State<_Conexion> {
  final _host = TextEditingController();
  final _puerto = TextEditingController();
  final _base = TextEditingController();
  final _usuario = TextEditingController();
  final _contrasena = TextEditingController();
  bool _ssl = false;
  bool _conectada = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final campo in [_host, _puerto, _base, _usuario, _contrasena]) {
      campo.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final datos = await widget.estado.api.conexion();
      if (!mounted) {
        return;
      }
      setState(() {
        _host.text = datos['host']?.toString() ?? '';
        _puerto.text = datos['puerto']?.toString() ?? '';
        _base.text = datos['base']?.toString() ?? '';
        _usuario.text = datos['usuario']?.toString() ?? '';
        _ssl = datos['ssl'] == true;
        _conectada = datos['conectada'] == true;
      });
    } on ErrorApi catch (error) {
      if (mounted) {
        mostrarAviso(context, error.mensaje);
      }
    }
  }

  Map<String, dynamic> get _datos => {
        'host': _host.text.trim(),
        'puerto': int.tryParse(_puerto.text.trim()) ?? 0,
        'base': _base.text.trim(),
        'usuario': _usuario.text.trim(),
        'contrasena': _contrasena.text,
        'ssl': _ssl,
      };

  Future<bool> _ejecutar(Future<void> Function() accion, {String? exito}) async {
    setState(() => _ocupado = true);
    final ok = await intentar(context, accion, exito: exito);
    if (mounted) {
      setState(() => _ocupado = false);
    }
    return ok;
  }

  Future<void> _restaurar() async {
    if (!await confirmar(
      context,
      titulo: 'Usar la conexión del servidor',
      mensaje: 'Se descartará la conexión guardada aquí y se volverá a usar DATABASE_URL del entorno.',
      accion: 'Restaurar',
    )) {
      return;
    }
    if (await _ejecutar(() => widget.estado.api.guardarConexion({'restaurarEntorno': true}),
        exito: 'Se volvió a usar la conexión del servidor.')) {
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: Espacio.m);
    final esquema = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _conectada ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  color: _conectada ? ColoresLiebre.abierto(Theme.of(context).brightness) : esquema.error,
                ),
                const SizedBox(width: Espacio.s),
                Expanded(
                  child: Text('Conexión: ${_conectada ? 'conectada' : 'sin conexión'}',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            if (_ocupado) const LinearProgressIndicator(),
            separacion,
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
            TextField(controller: _usuario, decoration: const InputDecoration(labelText: 'Usuario')),
            separacion,
            TextField(
              controller: _contrasena,
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
                OutlinedButton(
                  onPressed: _ocupado
                      ? null
                      : () => _ejecutar(() => widget.estado.api.probarConexion(_datos), exito: 'La base de datos respondió.'),
                  child: const Text('Probar'),
                ),
                FilledButton(
                  onPressed: _ocupado
                      ? null
                      : () => _ejecutar(() async {
                            final datos = await widget.estado.api.guardarConexion(_datos);
                            _contrasena.clear();
                            _conectada = datos['conectada'] == true;
                          }, exito: 'Conexión guardada.'),
                  child: const Text('Guardar y reconectar'),
                ),
                TextButton(onPressed: _ocupado ? null : _restaurar, child: const Text('Usar la del servidor')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tablas con su número de filas y una tabla paginada de la elegida.
class _Registros extends StatefulWidget {
  const _Registros({required this.estado});

  final EstadoApp estado;

  @override
  State<_Registros> createState() => _RegistrosState();
}

class _RegistrosState extends State<_Registros> {
  /// Nombre visible de cada tabla SQL (los nombres en inglés son heredados).
  static const Map<String, String> _nombres = {
    'users': 'Cuentas (users)',
    'sellers': 'Negocios (sellers)',
    'products': 'Productos (products)',
    'ratings': 'Reseñas (ratings)',
    'favorites': 'Favoritos (favorites)',
    'announcements': 'Avisos (announcements)',
    'anuncios': 'Publicidad (anuncios)',
    'ajustes': 'Apariencia (ajustes)',
    'restablecimientos': 'Restablecimientos de contraseña',
  };

  List<(String, int)> _tablas = [];
  String? _tabla;
  PaginaTabla? _pagina;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarTablas();
  }

  Future<void> _cargarTablas() async {
    try {
      final tablas = await widget.estado.api.tablas();
      if (mounted) {
        setState(() => _tablas = tablas);
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() => _error = error.mensaje);
      }
    }
  }

  Future<void> _abrir(String tabla, {int pagina = 1}) async {
    setState(() {
      _tabla = tabla;
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await widget.estado.api.leerTabla(tabla, pagina: pagina);
      if (mounted) {
        setState(() => _pagina = datos);
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() => _error = error.mensaje);
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  /// Texto de una celda: recorta los valores largos (descripciones, URLs).
  String _celda(Object? valor) {
    if (valor == null) {
      return '—';
    }
    final texto = valor is bool ? (valor ? 'sí' : 'no') : valor.toString();
    return texto.length > 60 ? '${texto.substring(0, 57)}…' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final pagina = _pagina;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Registros', style: tema.textTheme.titleMedium),
            const SizedBox(height: Espacio.xs),
            Text(
              'Consulta de solo lectura. Para cambiar o borrar registros usa las pestañas Usuarios, Negocios, '
              'Publicidad, Avisos y Reseñas: así se respetan las reglas y se borran también las fotos.',
              style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Espacio.m),
            Wrap(
              spacing: Espacio.s,
              runSpacing: Espacio.s,
              children: [
                for (final (tabla, filas) in _tablas)
                  ChoiceChip(
                    label: Text('${_nombres[tabla] ?? tabla} · $filas'),
                    selected: _tabla == tabla,
                    onSelected: (_) => _abrir(tabla),
                  ),
              ],
            ),
            if (_cargando) ...[const SizedBox(height: Espacio.m), const LinearProgressIndicator()],
            if (_error != null) ...[
              const SizedBox(height: Espacio.m),
              Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
            ],
            if (pagina != null && pagina.tabla == _tabla) ...[
              const SizedBox(height: Espacio.m),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: tema.textTheme.labelLarge,
                  columns: [for (final columna in pagina.columnas) DataColumn(label: Text(columna))],
                  rows: [
                    for (final fila in pagina.filas)
                      DataRow(cells: [
                        for (final valor in fila)
                          DataCell(
                            Tooltip(message: valor?.toString() ?? '', child: Text(_celda(valor))),
                          ),
                      ]),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Página ${pagina.pagina} de ${pagina.paginas} · ${pagina.total} filas'),
                  IconButton(
                    tooltip: 'Página anterior',
                    onPressed: _cargando || pagina.pagina <= 1 ? null : () => _abrir(pagina.tabla, pagina: pagina.pagina - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Página siguiente',
                    onPressed: _cargando || pagina.pagina >= pagina.paginas
                        ? null
                        : () => _abrir(pagina.tabla, pagina: pagina.pagina + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
