import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import '../../widgets/datos_opcionales.dart';
import '../sesion_dialogo.dart';
import 'comun_admin.dart';

/// Roles que acepta la API: (valor, etiqueta). Mismo orden que `user_role` en `db/schema.sql`.
const List<(String, String)> rolesCuenta = [
  ('comprador', 'Comprador'),
  ('vendedor', 'Vendedor'),
  ('moderador', 'Moderador'),
  ('admin', 'Administrador'),
];

/// Cuentas: buscar, crear, editar, bloquear, eliminar y restablecer contraseñas.
class AdminUsuarios extends StatefulWidget {
  /// Sesión de administrador.
  const AdminUsuarios({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  @override
  State<AdminUsuarios> createState() => _AdminUsuariosState();
}

class _AdminUsuariosState extends State<AdminUsuarios> {
  String _filtro = '';
  String? _rol;

  bool _coincide(Usuario cuenta) {
    if (_rol != null && cuenta.rol != _rol) {
      return false;
    }
    return _filtro.isEmpty ||
        cuenta.nombreCompleto.toLowerCase().contains(_filtro) ||
        cuenta.correo.toLowerCase().contains(_filtro) ||
        (cuenta.numeroControl ?? '').toLowerCase().contains(_filtro);
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    return CargaAdmin<List<Usuario>>(
      cargar: estado.api.usuariosModeracion,
      construir: (context, cuentas, recargar) {
        final visibles = cuentas.where(_coincide).toList();
        return [
          Row(
            children: [
              Expanded(child: Text('${cuentas.length} cuentas', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.icon(
                onPressed: () async {
                  if (await showDialog<bool>(context: context, builder: (_) => _CrearCuenta(estado: estado)) == true) {
                    await recargar();
                  }
                },
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Crear cuenta'),
              ),
            ],
          ),
          const SizedBox(height: Espacio.m),
          BuscadorAdmin(pista: 'Nombre, correo o número de control', alCambiar: (texto) => setState(() => _filtro = texto)),
          Wrap(
            spacing: Espacio.s,
            children: [
              ChoiceChip(label: const Text('Todas'), selected: _rol == null, onSelected: (_) => setState(() => _rol = null)),
              for (final (valor, etiqueta) in rolesCuenta)
                ChoiceChip(label: Text(etiqueta), selected: _rol == valor, onSelected: (_) => setState(() => _rol = valor)),
            ],
          ),
          const SizedBox(height: Espacio.m),
          Card(
            child: Column(
              children: [
                for (final cuenta in visibles)
                  _FilaUsuario(cuenta: cuenta, estado: estado, alCambiar: recargar),
                if (visibles.isEmpty) const ListTile(title: Text('Ninguna cuenta coincide.')),
              ],
            ),
          ),
        ];
      },
    );
  }
}

class _FilaUsuario extends StatelessWidget {
  const _FilaUsuario({required this.cuenta, required this.estado, required this.alCambiar});

  final Usuario cuenta;
  final EstadoApp estado;
  final Future<void> Function() alCambiar;

  bool get _propia => cuenta.id == estado.usuario?.id;

  Future<void> _elegir(BuildContext context, String opcion) async {
    final api = estado.api;
    switch (opcion) {
      case 'editar':
        if (await showDialog<bool>(context: context, builder: (_) => _EditarCuenta(estado: estado, cuenta: cuenta)) == true) {
          await alCambiar();
        }
      case 'contrasena':
        await mostrarRestablecerContrasena(context, estado, cuenta);
        await alCambiar();
      case 'bloquear':
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
        if (context.mounted &&
            await intentar(context, () => api.bloquear(cuenta.id, bloquear),
                exito: bloquear ? 'Cuenta bloqueada.' : 'Cuenta desbloqueada.')) {
          await alCambiar();
        }
      case 'eliminar':
        if (!await confirmar(
          context,
          titulo: 'Eliminar cuenta',
          mensaje: 'Se borrará ${cuenta.nombreCompleto} con su negocio, productos, fotos, reseñas y favoritos. '
              'Esta acción no se puede deshacer.',
        )) {
          return;
        }
        if (context.mounted &&
            await intentar(context, () => api.eliminarUsuario(cuenta.id), exito: 'Cuenta eliminada.')) {
          await alCambiar();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(child: Text(cuenta.inicial)),
      title: Text(cuenta.nombreCompleto + (_propia ? ' (tú)' : '')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cuenta.correo),
          const SizedBox(height: Espacio.xs),
          Wrap(
            spacing: Espacio.xs,
            runSpacing: Espacio.xs,
            children: [
              Etiqueta(cuenta.rolEtiqueta),
              if (!cuenta.correoVerificado) Etiqueta('Sin verificar', color: esquema.tertiary),
              if (cuenta.bloqueado) Etiqueta('Bloqueada', color: esquema.error),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => _elegir(context, 'editar'),
      trailing: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (opcion) => _elegir(context, opcion),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'editar', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar datos'))),
          const PopupMenuItem(
            value: 'contrasena',
            child: ListTile(leading: Icon(Icons.key_outlined), title: Text('Restablecer contraseña')),
          ),
          if (!_propia) ...[
            PopupMenuItem(
              value: 'bloquear',
              child: ListTile(
                leading: Icon(cuenta.bloqueado ? Icons.lock_open : Icons.block),
                title: Text(cuenta.bloqueado ? 'Desbloquear' : 'Bloquear'),
              ),
            ),
            PopupMenuItem(
              value: 'eliminar',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: esquema.error),
                title: Text('Eliminar cuenta', style: TextStyle(color: esquema.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ofrece fijar una contraseña nueva o mandar un enlace al correo de [cuenta].
Future<void> mostrarRestablecerContrasena(BuildContext context, EstadoApp estado, Usuario cuenta) {
  return showDialog<void>(context: context, builder: (_) => _RestablecerContrasena(estado: estado, cuenta: cuenta));
}

class _RestablecerContrasena extends StatefulWidget {
  const _RestablecerContrasena({required this.estado, required this.cuenta});

  final EstadoApp estado;
  final Usuario cuenta;

  @override
  State<_RestablecerContrasena> createState() => _RestablecerContrasenaState();
}

class _RestablecerContrasenaState extends State<_RestablecerContrasena> {
  final _formulario = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _ocupado = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion, String exito) async {
    setState(() => _ocupado = true);
    final ok = await intentar(context, accion, exito: exito);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuenta = widget.cuenta;
    final api = widget.estado.api;
    final tenue = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return AlertDialog(
      title: Text('Contraseña de ${cuenta.nombre}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formulario,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Opción 1: mandar un enlace a ${cuenta.correo} para que elija su contraseña. Vence en una hora.',
                  style: tenue),
              const SizedBox(height: Espacio.s),
              OutlinedButton.icon(
                onPressed: _ocupado
                    ? null
                    : () => _ejecutar(() => api.enviarRestablecimiento(cuenta.id), 'Enlace enviado a ${cuenta.correo}.'),
                icon: const Icon(Icons.forward_to_inbox_outlined),
                label: const Text('Enviar enlace por correo'),
              ),
              const Divider(height: Espacio.xl),
              Text('Opción 2: fijar una contraseña ahora y comunicársela en persona.', style: tenue),
              const SizedBox(height: Espacio.s),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña nueva'),
                validator: Validar.password,
              ),
              const SizedBox(height: Espacio.s),
              FilledButton.icon(
                onPressed: _ocupado
                    ? null
                    : () {
                        if (_formulario.currentState?.validate() ?? false) {
                          _ejecutar(() => api.fijarContrasena(cuenta.id, _password.text), 'Contraseña cambiada.');
                        }
                      },
                icon: const Icon(Icons.password),
                label: const Text('Fijar contraseña'),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}

/// Alta de cuentas de cualquier rol. Devuelve true si se creó.
class _CrearCuenta extends StatefulWidget {
  const _CrearCuenta({required this.estado});

  final EstadoApp estado;

  @override
  State<_CrearCuenta> createState() => _CrearCuentaState();
}

class _CrearCuentaState extends State<_CrearCuenta> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _correo = TextEditingController();
  final _password = TextEditingController();
  final _negocio = TextEditingController();
  String _rol = 'comprador';
  String _categoria = 'comida';
  bool _ocupado = false;

  @override
  void dispose() {
    for (final campo in [_nombre, _apellido, _correo, _password, _negocio]) {
      campo.dispose();
    }
    super.dispose();
  }

  Future<void> _crear() async {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _ocupado = true);
    final ok = await intentar(
      context,
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
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: Espacio.m);
    return AlertDialog(
      title: const Text('Crear cuenta'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Las cuentas que crea el administrador ya nacen con el correo verificado.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                separacion,
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
                  items: [for (final (valor, etiqueta) in rolesCuenta) DropdownMenuItem(value: valor, child: Text(etiqueta))],
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
                      for (final (valor, etiqueta) in categoriasNegocio) DropdownMenuItem(value: valor, child: Text(etiqueta)),
                    ],
                    onChanged: _ocupado ? null : (valor) => setState(() => _categoria = valor ?? 'comida'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ocupado ? null : _crear, child: const Text('Crear cuenta')),
      ],
    );
  }
}

/// Edición de nombre, correo, rol, verificación y datos opcionales. Devuelve true si guardó.
class _EditarCuenta extends StatefulWidget {
  const _EditarCuenta({required this.estado, required this.cuenta});

  final EstadoApp estado;
  final Usuario cuenta;

  @override
  State<_EditarCuenta> createState() => _EditarCuentaState();
}

class _EditarCuentaState extends State<_EditarCuenta> {
  final _formulario = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.cuenta.nombre);
  late final _apellido = TextEditingController(text: widget.cuenta.apellido);
  late final _correo = TextEditingController(text: widget.cuenta.correo);
  late final _telefono = TextEditingController(text: widget.cuenta.telefono);
  late final _numeroControl = TextEditingController(text: widget.cuenta.numeroControl);
  late final _carrera = TextEditingController(text: widget.cuenta.carrera);
  late String _rol = widget.cuenta.rol;
  late bool _verificado = widget.cuenta.correoVerificado;
  bool _ocupado = false;

  @override
  void dispose() {
    for (final campo in [_nombre, _apellido, _correo, _telefono, _numeroControl, _carrera]) {
      campo.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _ocupado = true);
    final ok = await intentar(
      context,
      () => widget.estado.api.actualizarUsuarioAdmin(widget.cuenta.id, {
        'nombre': _nombre.text,
        'apellido': _apellido.text,
        'correo': _correo.text,
        'rol': _rol,
        'correoVerificado': _verificado,
        'telefono': _telefono.text,
        'numeroControl': _numeroControl.text,
        'carrera': _carrera.text,
      }),
      exito: 'Cuenta actualizada.',
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      // Si el admin se editó a sí mismo, refresca su nombre en la barra.
      if (widget.cuenta.id == widget.estado.usuario?.id) {
        await widget.estado.refrescarUsuario();
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } else {
      setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: Espacio.m);
    final propia = widget.cuenta.id == widget.estado.usuario?.id;
    return AlertDialog(
      title: const Text('Editar cuenta'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                DropdownButtonFormField<String>(
                  initialValue: _rol,
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    helperText: propia ? 'No puedes quitarte el rol de administrador.' : null,
                  ),
                  items: [for (final (valor, etiqueta) in rolesCuenta) DropdownMenuItem(value: valor, child: Text(etiqueta))],
                  onChanged: _ocupado || propia ? null : (valor) => setState(() => _rol = valor ?? _rol),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _verificado,
                  title: const Text('Correo verificado'),
                  subtitle: const Text('Sin verificar no califica ni comenta.'),
                  onChanged: _ocupado ? null : (valor) => setState(() => _verificado = valor),
                ),
                CamposOpcionales(telefono: _telefono, numeroControl: _numeroControl, carrera: _carrera),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
