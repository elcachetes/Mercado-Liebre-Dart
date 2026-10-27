import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/datos_opcionales.dart';
import '../widgets/tarjeta_vendedor.dart';
import 'detalle_vendedor.dart';
import 'panel_admin.dart';
import 'panel_negocio.dart';
import 'sesion_dialogo.dart';

/// Perfil, favoritos, panel del negocio, administración y moderación.
///
/// Qué secciones aparecen depende del rol de la cuenta:
/// vendedor → "Mi negocio"; admin → "Administración"; admin o moderador → "Moderación".
class PerfilPantalla extends StatefulWidget {
  /// [estado] decide si se muestra la invitación a entrar o la cuenta.
  const PerfilPantalla({super.key, required this.estado});

  /// Sesión actual.
  final EstadoApp estado;

  @override
  State<PerfilPantalla> createState() => _PerfilPantallaState();
}

class _PerfilPantallaState extends State<PerfilPantalla> {
  List<Vendedor> _vendedores = [];
  Vendedor? _negocio;
  List<Usuario> _cuentas = [];
  String? _cuentaCargada;

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

  /// Solo recarga si cambió la cuenta, no por cambios de tema o favoritos.
  void _alCambiarEstado() {
    if (widget.estado.usuario?.id != _cuentaCargada) {
      _cargar();
    }
  }

  Future<void> _cargar() async {
    final usuario = widget.estado.usuario;
    _cuentaCargada = usuario?.id;
    if (usuario == null) {
      setState(() {
        _vendedores = [];
        _negocio = null;
        _cuentas = [];
      });
      return;
    }
    final api = widget.estado.api;
    try {
      final (vendedores, negocio, cuentas) = await (
        api.vendedores(),
        usuario.esVendedor ? api.miNegocio() : Future<Vendedor?>.value(),
        usuario.esModerador ? api.usuariosModeracion() : Future.value(const <Usuario>[]),
      ).wait;
      if (!mounted || widget.estado.usuario?.id != usuario.id) {
        return;
      }
      setState(() {
        _vendedores = vendedores;
        _negocio = negocio;
        _cuentas = cuentas.where((cuenta) => cuenta.id != usuario.id).toList();
      });
    } on ParallelWaitError<dynamic, dynamic> {
      // La pantalla sigue usable aunque falle un panel secundario.
      if (mounted) {
        mostrarAviso(context, 'No se pudo cargar todo tu perfil. Desliza para reintentar.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = widget.estado.usuario;
    if (usuario == null) {
      return _Invitado(estado: widget.estado);
    }
    final favoritos = _vendedores.where((vendedor) => widget.estado.esFavorito(vendedor.id)).toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xl),
        children: [
          _Encabezado(
            usuario: usuario,
            alEditar: () => showDialog<void>(
              context: context,
              builder: (_) => _EditarDatos(estado: widget.estado),
            ),
          ),
          const TituloSeccion('Favoritos', icono: Icons.favorite_outline),
          if (favoritos.isEmpty)
            Text(
              'Aún no tienes favoritos. Abre un negocio y toca el corazón para guardarlo aquí.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          else
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
          if (_negocio != null) ...[
            const TituloSeccion('Mi negocio', icono: Icons.storefront_outlined),
            PanelNegocio(estado: widget.estado, negocio: _negocio!, alCambiar: _cargar),
          ],
          if (usuario.esAdmin) ...[
            const TituloSeccion('Administración', icono: Icons.admin_panel_settings_outlined),
            PanelAdmin(estado: widget.estado, alCambiar: _cargar),
          ],
          if (usuario.esModerador) ...[
            TituloSeccion(
              'Moderación',
              icono: Icons.shield_outlined,
              accion: Text('${_cuentas.length} cuentas', style: Theme.of(context).textTheme.labelLarge),
            ),
            Card(
              child: Column(
                children: [
                  for (final cuenta in _cuentas) _FilaCuenta(cuenta: cuenta, actor: usuario, estado: widget.estado, alCambiar: _cargar),
                  if (_cuentas.isEmpty) const ListTile(title: Text('No hay otras cuentas.')),
                ],
              ),
            ),
          ],
          const SizedBox(height: Espacio.xl),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirmar(context, titulo: 'Cerrar sesión', mensaje: '¿Quieres salir de tu cuenta?', accion: 'Salir')) {
                await widget.estado.salir();
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

class _Invitado extends StatelessWidget {
  const _Invitado({required this.estado});

  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Espacio.xl),
      children: [
        Icon(Icons.account_circle_outlined, size: 72, color: tema.colorScheme.primary),
        const SizedBox(height: Espacio.l),
        Text('Tu perfil', style: tema.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: Espacio.s),
        Text(
          'Puedes explorar sin cuenta. Entra para calificar productos, guardar favoritos o administrar tu negocio.',
          textAlign: TextAlign.center,
          style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Espacio.xl),
        FilledButton.icon(
          onPressed: () => mostrarDialogoSesion(context, estado),
          icon: const Icon(Icons.login),
          label: const Text('Iniciar sesión'),
        ),
        const SizedBox(height: Espacio.s),
        OutlinedButton.icon(
          onPressed: () => mostrarDialogoSesion(context, estado, registro: true),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Crear cuenta'),
        ),
      ],
    );
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
