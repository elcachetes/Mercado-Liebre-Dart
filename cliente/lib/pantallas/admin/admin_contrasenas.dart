import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import 'admin_usuarios.dart';
import 'comun_admin.dart';

/// Restablecimientos de contraseña: historial, anular enlaces pendientes y
/// restablecer la contraseña de cualquier cuenta.
///
/// Las personas piden el enlace con "¿Olvidaste tu contraseña?" al entrar;
/// el enlace vence en una hora y sirve una sola vez.
class AdminContrasenas extends StatelessWidget {
  /// Sesión de administrador.
  const AdminContrasenas({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  /// (texto, color) del estado de una solicitud.
  static (String, Color) _estado(BuildContext context, String estado) {
    final esquema = Theme.of(context).colorScheme;
    return switch (estado) {
      'pendiente' => ('Pendiente', esquema.tertiary),
      'usado' => ('Usado', ColoresLiebre.abierto(Theme.of(context).brightness)),
      'vencido' => ('Vencido', esquema.outline),
      _ => ('Anulado', esquema.error),
    };
  }

  /// Busca una cuenta y abre las opciones para restablecer su contraseña.
  Future<void> _restablecerA(BuildContext context, Future<void> Function() recargar) async {
    final List<Usuario> cuentas;
    try {
      cuentas = await estado.api.usuariosModeracion();
    } on ErrorApi catch (error) {
      if (context.mounted) {
        mostrarAviso(context, error.mensaje);
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    final elegida = await showDialog<Usuario>(context: context, builder: (_) => _ElegirCuenta(cuentas: cuentas));
    if (elegida != null && context.mounted) {
      await mostrarRestablecerContrasena(context, estado, elegida);
      await recargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = estado.api;
    return CargaAdmin<List<Restablecimiento>>(
      cargar: api.restablecimientos,
      construir: (context, solicitudes, recargar) {
        final esquema = Theme.of(context).colorScheme;
        return [
          Text(
            'Cada vez que alguien pide "¿Olvidaste tu contraseña?" o que tú restableces una, queda aquí. '
            'Anular un enlace pendiente hace que deje de servir.',
            style: TextStyle(color: esquema.onSurfaceVariant),
          ),
          const SizedBox(height: Espacio.m),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _restablecerA(context, recargar),
              icon: const Icon(Icons.key_outlined),
              label: const Text('Restablecer la contraseña de una cuenta'),
            ),
          ),
          const TituloSeccion('Historial', icono: Icons.history),
          if (solicitudes.isEmpty) const EstadoVacio(icono: Icons.key_off_outlined, mensaje: 'Todavía no hay solicitudes.'),
          for (final solicitud in solicitudes)
            Card(
              child: ListTile(
                title: Text(solicitud.nombre),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(solicitud.correo),
                    const SizedBox(height: Espacio.xs),
                    Wrap(
                      spacing: Espacio.xs,
                      runSpacing: Espacio.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Etiqueta(_estado(context, solicitud.estado).$1, color: _estado(context, solicitud.estado).$2),
                        Etiqueta(solicitud.origen == 'admin' ? 'Por administración' : 'Pedido por la persona'),
                        Text(
                          solicitud.usadoEn != null
                              ? 'Usado ${fechaCorta(solicitud.usadoEn)}'
                              : 'Pedido ${fechaCorta(solicitud.creadoEn)} · vence ${fechaCorta(solicitud.venceEn)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                isThreeLine: true,
                trailing: solicitud.pendiente
                    ? TextButton(
                        onPressed: () async {
                          if (await intentar(context, () => api.anularRestablecimiento(solicitud.id),
                              exito: 'Enlace anulado.')) {
                            await recargar();
                          }
                        },
                        child: const Text('Anular'),
                      )
                    : null,
              ),
            ),
        ];
      },
    );
  }
}

/// Lista con buscador para elegir una cuenta.
class _ElegirCuenta extends StatefulWidget {
  const _ElegirCuenta({required this.cuentas});

  final List<Usuario> cuentas;

  @override
  State<_ElegirCuenta> createState() => _ElegirCuentaState();
}

class _ElegirCuentaState extends State<_ElegirCuenta> {
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final visibles = widget.cuentas
        .where((c) => _filtro.isEmpty || '${c.nombreCompleto} ${c.correo}'.toLowerCase().contains(_filtro))
        .take(50)
        .toList();
    return AlertDialog(
      title: const Text('Elige la cuenta'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            BuscadorAdmin(pista: 'Nombre o correo', alCambiar: (texto) => setState(() => _filtro = texto)),
            Expanded(
              child: ListView(
                children: [
                  for (final cuenta in visibles)
                    ListTile(
                      leading: AvatarUsuario(nombre: cuenta.nombre, fotoUrl: cuenta.fotoPerfilUrl),
                      title: Text(cuenta.nombreCompleto),
                      subtitle: Text(cuenta.correo),
                      onTap: () => Navigator.pop(context, cuenta),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
