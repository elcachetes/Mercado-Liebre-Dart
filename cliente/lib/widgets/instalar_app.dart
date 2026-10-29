import 'package:flutter/material.dart';

import '../servicios/instalacion.dart';
import '../tema/tema_liebre.dart';
import 'comunes.dart';

/// Instala la app: abre el diálogo del navegador o, en iPhone/iPad, explica los pasos.
Future<void> instalarApp(BuildContext context) async {
  final instalacion = InstalacionApp.instancia;
  if (instalacion.disponible) {
    if (await instalacion.instalar() && context.mounted) {
      mostrarAviso(context, '¡Listo! Mercado Liebre quedó instalada en tu dispositivo.');
    }
    return;
  }
  if (instalacion.esIos) {
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        icon: const Icon(Icons.install_mobile),
        title: const Text('Instalar en iPhone o iPad'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Abre esta página en Safari.'),
            SizedBox(height: Espacio.s),
            Text('2. Toca el botón Compartir (el cuadro con una flecha hacia arriba).'),
            SizedBox(height: Espacio.s),
            Text('3. Elige "Agregar a pantalla de inicio" y toca "Agregar".'),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(contexto), child: const Text('Entendido'))],
      ),
    );
  }
}

/// "Instalar app" para la barra roja. Solo aparece si el navegador permite instalar.
class BotonInstalar extends StatelessWidget {
  /// [conTexto] muestra la etiqueta además del icono (pantallas amplias).
  const BotonInstalar({super.key, this.conTexto = true});

  /// Icono y texto, o solo icono.
  final bool conTexto;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InstalacionApp.instancia,
      builder: (context, _) {
        if (!InstalacionApp.instancia.mostrarBoton) {
          return const SizedBox.shrink();
        }
        if (!conTexto) {
          return IconButton(
            tooltip: 'Instalar app',
            onPressed: () => instalarApp(context),
            icon: const Icon(Icons.install_mobile),
          );
        }
        return TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: () => instalarApp(context),
          icon: const Icon(Icons.install_mobile),
          label: const Text('Instalar app'),
        );
      },
    );
  }
}

/// Tarjeta de Inicio en el celular: invita a instalar la app. Se puede cerrar.
class InvitacionInstalar extends StatefulWidget {
  /// Sin parámetros: lee [InstalacionApp.instancia].
  const InvitacionInstalar({super.key});

  @override
  State<InvitacionInstalar> createState() => _InvitacionInstalarState();
}

class _InvitacionInstalarState extends State<InvitacionInstalar> {
  /// Se cierra hasta la próxima vez que se abra la app.
  static bool _cerrada = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InstalacionApp.instancia,
      builder: (context, _) {
        if (_cerrada || !InstalacionApp.instancia.mostrarBoton) {
          return const SizedBox.shrink();
        }
        final esquema = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: Espacio.l),
          child: Card(
            color: esquema.primaryContainer,
            child: ListTile(
              leading: Icon(Icons.install_mobile, color: esquema.onPrimaryContainer),
              title: Text('Instala Mercado Liebre', style: TextStyle(color: esquema.onPrimaryContainer)),
              subtitle: Text(
                'Ábrela desde tu pantalla de inicio, como cualquier otra app.',
                style: TextStyle(color: esquema.onPrimaryContainer),
              ),
              onTap: () => instalarApp(context),
              trailing: IconButton(
                tooltip: 'Ahora no',
                onPressed: () => setState(() => _cerrada = true),
                icon: Icon(Icons.close, color: esquema.onPrimaryContainer),
              ),
            ),
          ),
        );
      },
    );
  }
}
