import 'package:flutter/material.dart';

import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import 'comunes.dart';

/// Aviso para cuentas que aún no abren el enlace del correo de verificación.
///
/// Ofrece reenviar el correo y volver a leer la cuenta cuando la persona
/// ya lo abrió en otra pestaña. No se muestra si el correo está verificado.
class AvisoVerificacion extends StatefulWidget {
  /// [motivo] completa "Verifica tu correo para …".
  const AvisoVerificacion({super.key, required this.estado, this.motivo = 'calificar y comentar productos'});

  /// Sesión con la cuenta a verificar.
  final EstadoApp estado;

  /// Qué se desbloquea al verificar.
  final String motivo;

  @override
  State<AvisoVerificacion> createState() => _AvisoVerificacionState();
}

class _AvisoVerificacionState extends State<AvisoVerificacion> {
  bool _ocupado = false;

  Future<void> _reenviar() async {
    setState(() => _ocupado = true);
    await intentar(
      context,
      widget.estado.api.reenviarVerificacion,
      exito: 'Te enviamos otro correo a ${widget.estado.usuario?.correo}. Revisa también la carpeta de spam.',
    );
    if (mounted) {
      setState(() => _ocupado = false);
    }
  }

  Future<void> _comprobar() async {
    setState(() => _ocupado = true);
    await intentar(context, widget.estado.refrescarUsuario);
    if (!mounted) {
      return;
    }
    setState(() => _ocupado = false);
    final verificado = widget.estado.usuario?.correoVerificado ?? false;
    mostrarAviso(
      context,
      verificado ? '¡Listo! Tu correo está verificado.' : 'Aún no vemos la verificación. Abre el enlace del correo.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = widget.estado.usuario;
    if (usuario == null || usuario.correoVerificado) {
      return const SizedBox.shrink();
    }
    final esquema = Theme.of(context).colorScheme;
    return Card(
      color: esquema.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mark_email_unread_outlined, color: esquema.onSecondaryContainer),
                const SizedBox(width: Espacio.s),
                Expanded(
                  child: Text(
                    'Verifica tu correo para ${widget.motivo}.',
                    style: TextStyle(color: esquema.onSecondaryContainer, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.xs),
            Text(
              'Te enviamos un enlace a ${usuario.correo}.',
              style: TextStyle(color: esquema.onSecondaryContainer),
            ),
            const SizedBox(height: Espacio.s),
            Wrap(
              spacing: Espacio.s,
              runSpacing: Espacio.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _reenviar,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Reenviar correo'),
                ),
                TextButton.icon(
                  onPressed: _ocupado ? null : _comprobar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ya lo verifiqué'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
