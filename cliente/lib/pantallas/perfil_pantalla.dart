import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/datos_opcionales.dart';
import '../widgets/eliminar_cuenta.dart';
import '../widgets/tarjeta_vendedor.dart';
import '../widgets/verificacion.dart';
import 'detalle_vendedor.dart';
import 'panel_admin.dart';
import 'panel_negocio.dart';

/// Secciones de la cuenta. Aparecen en el menú que se abre al tocar el
/// nombre en la barra superior; cada una se abre en su propia página.
enum SeccionCuenta {
  /// Datos personales y estado de la verificación del correo.
  datos('Mis datos', Icons.badge_outlined),

  /// Negocios guardados con el corazón.
  favoritos('Favoritos', Icons.favorite_outline),

  /// Panel del vendedor.
  negocio('Mi negocio', Icons.storefront_outlined),

  /// Panel del administrador (página propia con pestañas, ver [PanelAdmin]).
  administracion('Administración', Icons.admin_panel_settings_outlined),

  /// Bloqueo y borrado de cuentas.
  moderacion('Moderación', Icons.shield_outlined);

  const SeccionCuenta(this.titulo, this.icono);

  /// Texto del menú y de la barra de la página.
  final String titulo;

  /// Icono del menú.
  final IconData icono;

  /// Secciones del menú de la cuenta para [usuario], en orden.
  ///
  /// vendedor → "Mi negocio"; admin → "Administración"; admin o moderador → "Moderación".
  /// "Favoritos" no va aquí: tiene su propio botón en la barra roja.
  static List<SeccionCuenta> para(Usuario usuario) {
    return [
      datos,
      if (usuario.esVendedor) negocio,
      if (usuario.esAdmin) administracion,
      if (usuario.esModerador) moderacion,
    ];
  }
}

/// Abre [seccion] en una página nueva con flecha para volver.
///
/// "Administración" abre [PanelAdmin], que tiene su propia barra con pestañas.
Future<void> abrirSeccionCuenta(BuildContext context, EstadoApp estado, SeccionCuenta seccion) {
  if (seccion == SeccionCuenta.administracion) {
    return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PanelAdmin(estado: estado)));
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(seccion.titulo)),
        body: AnchoLimitado(child: PerfilPantalla(estado: estado, seccion: seccion)),
      ),
    ),
  );
}

/// Contenido de una [SeccionCuenta]. Solo carga lo que esa sección necesita.
class PerfilPantalla extends StatefulWidget {
  /// [seccion] decide qué se muestra y qué se pide a la API.
  const PerfilPantalla({super.key, required this.estado, required this.seccion});

  /// Sesión actual.
  final EstadoApp estado;

  /// Parte de la cuenta que se muestra.
  final SeccionCuenta seccion;

  @override
  State<PerfilPantalla> createState() => _PerfilPantallaState();
}

class _PerfilPantallaState extends State<PerfilPantalla> {
  List<Vendedor> _vendedores = [];
  Vendedor? _negocio;
  List<Usuario> _cuentas = [];
  String? _cuentaCargada;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    widget.estado.addListener(_alCambiarEstado);
    _cargar();
  }

  @override
  void dispose() {
    widget.estado.removeListener(_alCambiarEstado);
    super.dispose();
  }

  /// Recarga si cambió la cuenta; redibuja con cualquier otro cambio (favoritos, verificación).
  void _alCambiarEstado() {
    if (widget.estado.usuario?.id != _cuentaCargada) {
      _cargar();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _cargar() async {
    final usuario = widget.estado.usuario;
    _cuentaCargada = usuario?.id;
    if (usuario == null) {
      setState(() => _cargando = false);
      return;
    }
    final api = widget.estado.api;
    setState(() => _cargando = true);
    try {
      switch (widget.seccion) {
        case SeccionCuenta.favoritos:
          final vendedores = await api.vendedores();
          if (mounted) {
            setState(() => _vendedores = vendedores);
          }
        case SeccionCuenta.negocio:
          final negocio = await api.miNegocio();
          if (mounted) {
            setState(() => _negocio = negocio);
          }
        case SeccionCuenta.moderacion:
          final cuentas = await api.usuariosModeracion();
          if (mounted) {
            setState(() => _cuentas = cuentas.where((cuenta) => cuenta.id != usuario.id).toList());
          }
        case SeccionCuenta.datos:
        case SeccionCuenta.administracion:
          break;
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        mostrarAviso(context, error.mensaje);
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = widget.estado.usuario;
    if (usuario == null) {
      return const EstadoVacio(icono: Icons.lock_outline, mensaje: 'Inicia sesión para ver esta sección.');
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xl),
        children: [
          if (_cargando) const LinearProgressIndicator(),
          ..._contenido(context, usuario),
        ],
      ),
    );
  }

  List<Widget> _contenido(BuildContext context, Usuario usuario) {
    final tenue = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    switch (widget.seccion) {
      case SeccionCuenta.datos:
        return [
          AvisoVerificacion(estado: widget.estado),
          _Encabezado(
            usuario: usuario,
            alEditar: () => showDialog<void>(
              context: context,
              builder: (_) => _EditarDatos(estado: widget.estado),
            ),
          ),
          // El administrador no puede borrarse a sí mismo (lo impide también el servidor).
          if (!usuario.esAdmin) TarjetaEliminarCuenta(estado: widget.estado, vendedor: usuario.esVendedor),
        ];
      case SeccionCuenta.favoritos:
        final favoritos = _vendedores.where((vendedor) => widget.estado.esFavorito(vendedor.id)).toList();
        if (favoritos.isEmpty) {
          return [
            if (!_cargando)
              Text('Aún no tienes favoritos. Abre un negocio y toca el corazón para guardarlo aquí.', style: tenue),
          ];
        }
        return [
          for (final vendedor in favoritos)
            Padding(
              padding: const EdgeInsets.only(bottom: Espacio.s),
              child: TarjetaVendedor(
                vendedor: vendedor,
                compacta: true,
                favorito: true,
                alTocar: () => abrirVendedor(context, widget.estado, vendedor),
              ),
            ),
        ];
      case SeccionCuenta.negocio:
        final negocio = _negocio;
        if (negocio == null) {
          if (_cargando) {
            return [];
          }
          // Un admin en "vista de vendedor" ve el menú del vendedor, pero no tiene negocio propio.
          return [
            Text(
              usuario.esAdmin
                  ? 'Estás en la vista de vendedor. Tu cuenta de administrador no tiene un negocio propio; '
                      'para revisar el de alguien, vuelve a tu vista y ábrelo en Administración → Negocios → Ver ficha.'
                  : 'Tu cuenta todavía no tiene un perfil de negocio.',
              style: tenue,
            ),
          ];
        }
        return [PanelNegocio(estado: widget.estado, negocio: negocio, alCambiar: _cargar)];
      case SeccionCuenta.administracion:
        // Normalmente se abre con abrirSeccionCuenta; esto cubre cualquier otro camino.
        return [
          FilledButton.icon(
            onPressed: () => abrirSeccionCuenta(context, widget.estado, SeccionCuenta.administracion),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Abrir el panel de administración'),
          ),
        ];
      case SeccionCuenta.moderacion:
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: Espacio.s),
            child: Text('${_cuentas.length} cuentas', style: Theme.of(context).textTheme.labelLarge),
          ),
          Card(
            child: Column(
              children: [
                for (final cuenta in _cuentas)
                  _FilaCuenta(cuenta: cuenta, actor: usuario, estado: widget.estado, alCambiar: _cargar),
                if (_cuentas.isEmpty && !_cargando) const ListTile(title: Text('No hay otras cuentas.')),
              ],
            ),
          ),
        ];
    }
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.usuario, required this.alEditar});

  final Usuario usuario;
  final VoidCallback alEditar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final datos = [
      (Icons.mail_outline, 'Correo', usuario.correo),
      (Icons.badge_outlined, 'Número de control', usuario.numeroControl),
      (Icons.school_outlined, 'Carrera', usuario.carrera),
      (Icons.phone_outlined, 'Teléfono', usuario.telefono),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: ColoresLiebre.primario,
                  child: Text(usuario.inicial, style: const TextStyle(color: Colors.white, fontSize: 26)),
                ),
                const SizedBox(width: Espacio.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(usuario.nombreCompleto, style: tema.textTheme.titleLarge),
                      const SizedBox(height: Espacio.xs),
                      Chip(label: Text(usuario.rolEtiqueta), visualDensity: VisualDensity.compact),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.s),
            Row(
              children: [
                Expanded(child: Text('Mis datos', style: tema.textTheme.titleSmall)),
                TextButton.icon(onPressed: alEditar, icon: const Icon(Icons.edit_outlined), label: const Text('Editar')),
              ],
            ),
            for (final (icono, etiqueta, valor) in datos)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icono),
                title: Text(valor == null || valor.isEmpty ? 'No especificado' : valor),
                subtitle: Text(etiqueta),
              ),
            Text(
              avisoDatosOpcionales,
              style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuenta en el panel de moderación, con bloqueo y (solo admin) borrado.
class _FilaCuenta extends StatelessWidget {
  const _FilaCuenta({required this.cuenta, required this.actor, required this.estado, required this.alCambiar});

  final Usuario cuenta;
  final Usuario actor;
  final EstadoApp estado;
  final Future<void> Function() alCambiar;

  Future<void> _bloquear(BuildContext context) async {
    final bloquear = !cuenta.bloqueado;
    if (bloquear &&
        !await confirmar(
          context,
          titulo: 'Bloquear cuenta',
          mensaje: '${cuenta.nombreCompleto} no podrá entrar hasta que la desbloquees.',
          accion: 'Bloquear',
        )) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final ok = await intentar(
      context,
      () => estado.api.bloquear(cuenta.id, bloquear),
      exito: bloquear ? 'Cuenta bloqueada.' : 'Cuenta desbloqueada.',
    );
    if (ok) {
      await alCambiar();
    }
  }

  Future<void> _eliminar(BuildContext context) async {
    if (!await confirmar(
      context,
      titulo: 'Eliminar cuenta',
      mensaje: 'Se borrará ${cuenta.nombreCompleto}, su negocio, productos y favoritos. Esta acción no se puede deshacer.',
    )) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final ok = await intentar(context, () => estado.api.eliminarUsuario(cuenta.id), exito: 'Cuenta eliminada.');
    if (ok) {
      await alCambiar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    // Igual que el servidor: un moderador no bloquea a moderadores ni al admin.
    final puedeBloquear = actor.esAdmin || !cuenta.esModerador;
    return ListTile(
      leading: CircleAvatar(child: Text(cuenta.inicial)),
      title: Text(cuenta.nombreCompleto),
      subtitle: Text(cuenta.bloqueado ? '${cuenta.rolEtiqueta} · Bloqueada' : '${cuenta.rolEtiqueta} · ${cuenta.correo}'),
      trailing: Wrap(
        children: [
          if (puedeBloquear)
            IconButton(
              tooltip: cuenta.bloqueado ? 'Desbloquear' : 'Bloquear',
              onPressed: () => _bloquear(context),
              icon: Icon(cuenta.bloqueado ? Icons.lock_open : Icons.block, color: cuenta.bloqueado ? null : esquema.error),
            ),
          if (actor.esAdmin)
            IconButton(
              tooltip: 'Eliminar cuenta',
              onPressed: () => _eliminar(context),
              icon: Icon(Icons.delete_outline, color: esquema.error),
            ),
        ],
      ),
    );
  }
}

/// Formulario para cambiar teléfono, número de control y carrera.
class _EditarDatos extends StatefulWidget {
  const _EditarDatos({required this.estado});

  final EstadoApp estado;

  @override
  State<_EditarDatos> createState() => _EditarDatosState();
}

class _EditarDatosState extends State<_EditarDatos> {
  final _formulario = GlobalKey<FormState>();
  late final Usuario _usuario = widget.estado.usuario!;
  late final _telefono = TextEditingController(text: _usuario.telefono);
  late final _numeroControl = TextEditingController(text: _usuario.numeroControl);
  late final _carrera = TextEditingController(text: _usuario.carrera);
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _telefono.dispose();
    _numeroControl.dispose();
    _carrera.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.estado.actualizarPerfil(
        telefono: _telefono.text.trim(),
        numeroControl: _numeroControl.text.trim(),
        carrera: _carrera.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        mostrarAviso(context, 'Datos actualizados.');
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() {
          _error = error.mensaje;
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Mis datos'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CamposOpcionales(telefono: _telefono, numeroControl: _numeroControl, carrera: _carrera),
                if (_error != null) ...[
                  const SizedBox(height: Espacio.m),
                  Text(_error!, style: TextStyle(color: esquema.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
