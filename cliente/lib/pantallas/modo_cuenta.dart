import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import 'sesion_dialogo.dart';

/// Cambia la cuenta de modo usuario a modo vendedor, o al revés.
///
/// Usuario → vendedor: si ya tuvo un negocio (en pausa) solo confirma; si no,
/// pide nombre y categoría del negocio nuevo. Vendedor → usuario: confirma
/// que el negocio quedará en pausa (cerrado y oculto, sin borrar nada).
/// No hace nada si la cuenta no puede cambiar de modo (admin, moderador).
Future<void> cambiarModoCuenta(BuildContext context, EstadoApp estado) async {
  final usuario = estado.usuario;
  if (usuario == null || !usuario.puedeCambiarModo) {
    return;
  }
  if (usuario.esVendedor) {
    final seguro = await confirmar(
      context,
      titulo: 'Cambiar a modo usuario',
      mensaje: 'Tu negocio quedará en pausa: se cerrará y dejará de aparecer en búsquedas, en el mapa y en la '
          'publicidad. Tu catálogo, horario e imágenes se guardan; vuelve a modo vendedor cuando quieras.',
      accion: 'Cambiar',
    );
    if (seguro && context.mounted) {
      await intentar(
        context,
        () => estado.cambiarModo('comprador'),
        exito: 'Ahora estás en modo usuario. Tu negocio quedó en pausa.',
      );
    }
    return;
  }

  final Vendedor? enPausa;
  try {
    enPausa = await estado.api.miNegocio();
  } on ErrorApi catch (error) {
    if (context.mounted) {
      mostrarAviso(context, error.mensaje);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  var negocio = const <String, dynamic>{};
  if (enPausa != null) {
    final seguro = await confirmar(
      context,
      titulo: 'Cambiar a modo vendedor',
      mensaje: '"${enPausa.nombreNegocio}" volverá a aparecer en la app, cerrado hasta que lo abras desde "Mi negocio".',
      accion: 'Cambiar',
    );
    if (!seguro) {
      return;
    }
  } else {
    final datos = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const DialogoNuevoNegocio());
    if (datos == null) {
      return;
    }
    negocio = datos;
  }
  if (context.mounted) {
    await intentar(
      context,
      () => estado.cambiarModo('vendedor', negocio: negocio),
      exito: 'Ahora estás en modo vendedor. Configura tu negocio en "Mi negocio".',
    );
  }
}

/// Tarjeta de "Mis datos" que dice en qué modo está la cuenta y permite cambiarlo.
///
/// No se muestra a administradores ni moderadores (ver [Usuario.puedeCambiarModo]).
class TarjetaModoCuenta extends StatelessWidget {
  /// Usa la cuenta real de [estado], no la vista previa.
  const TarjetaModoCuenta({super.key, required this.estado});

  /// Sesión actual.
  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    final usuario = estado.usuario;
    if (usuario == null || !usuario.puedeCambiarModo) {
      return const SizedBox.shrink();
    }
    final tema = Theme.of(context);
    final vendedor = usuario.esVendedor;
    return Padding(
      padding: const EdgeInsets.only(top: Espacio.m),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(vendedor ? Icons.storefront_outlined : Icons.person_outline, color: tema.colorScheme.primary),
                  const SizedBox(width: Espacio.s),
                  Expanded(
                    child: Text(
                      vendedor ? 'Estás en modo vendedor' : 'Estás en modo usuario',
                      style: tema.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Espacio.s),
              Text(
                vendedor
                    ? 'Cambia a modo usuario si dejas de vender por un tiempo. Tu negocio quedará en pausa '
                        'y lo recuperas al volver a modo vendedor.'
                    : '¿Vendes comida, productos o servicios en el plantel? Cambia a modo vendedor para '
                        'publicar tu negocio.',
                style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () => cambiarModoCuenta(context, estado),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(vendedor ? 'Cambiar a modo usuario' : 'Cambiar a modo vendedor'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Datos del negocio nuevo al pasar a modo vendedor por primera vez.
///
/// Devuelve `{nombreNegocio, categoria, subtipo, descripcion}` o null si se cancela.
class DialogoNuevoNegocio extends StatefulWidget {
  /// Sin parámetros.
  const DialogoNuevoNegocio({super.key});

  @override
  State<DialogoNuevoNegocio> createState() => _DialogoNuevoNegocioState();
}

class _DialogoNuevoNegocioState extends State<DialogoNuevoNegocio> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _subtipo = TextEditingController();
  final _descripcion = TextEditingController();
  String _categoria = 'comida';

  @override
  void dispose() {
    _nombre.dispose();
    _subtipo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  void _aceptar() {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.pop(context, {
      'nombreNegocio': _nombre.text.trim(),
      'categoria': _categoria,
      'subtipo': _subtipo.text.trim(),
      'descripcion': _descripcion.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: Espacio.m);
    return AlertDialog(
      title: const Text('Tu negocio'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Podrás agregar productos, horario, logo y foto de la tienda en "Mi negocio".'),
                separacion,
                TextFormField(
                  controller: _nombre,
                  autofocus: true,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                  validator: Validar.requerido,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final (valor, etiqueta) in categoriasNegocio) DropdownMenuItem(value: valor, child: Text(etiqueta)),
                  ],
                  onChanged: (valor) => setState(() => _categoria = valor ?? 'comida'),
                ),
                separacion,
                TextFormField(
                  controller: _subtipo,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Especialidad (opcional)', hintText: 'Ej. comida mexicana'),
                ),
                TextFormField(
                  controller: _descripcion,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Cambiar a modo vendedor')),
      ],
    );
  }
}
