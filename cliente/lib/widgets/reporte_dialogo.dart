import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../servicios/imagenes.dart';
import '../tema/tema_liebre.dart';
import 'comunes.dart';
import 'datos_opcionales.dart';

/// Abre el formulario para reportar una falla, una queja o una sugerencia.
///
/// Llega por correo a la administración. No necesita sesión; si la hay,
/// el contacto se llena con el correo de la cuenta.
Future<void> mostrarReporte(BuildContext context, EstadoApp estado) {
  return showDialog<void>(
    context: context,
    builder: (_) => FormularioReporte(estado: estado),
  );
}

/// Largo máximo de la descripción. Igual que `Reporte.maximoDescripcion` en el servidor.
const int maximoDescripcionReporte = 1000;

/// Valida el contacto del reporte: un correo o un número de control (obligatorio).
String? validarContactoReporte(String? valor) {
  final texto = (valor ?? '').trim();
  if (texto.isEmpty) {
    return 'Escribe tu correo o tu número de control';
  }
  if (texto.contains('@')) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(texto) ? null : 'Escribe un correo válido';
  }
  return ValidarOpcional.numeroControl(texto);
}

/// Formulario del reporte: contacto, descripción, foto opcional, Cancelar y Enviar.
class FormularioReporte extends StatefulWidget {
  /// [estado] da la API y, si hay sesión, el correo para el contacto.
  const FormularioReporte({super.key, required this.estado});

  /// Sesión actual (puede ser invitada).
  final EstadoApp estado;

  @override
  State<FormularioReporte> createState() => _FormularioReporteState();
}

class _FormularioReporteState extends State<FormularioReporte> {
  final _formulario = GlobalKey<FormState>();
  late final _contacto = TextEditingController(text: widget.estado.usuario?.correo ?? '');
  final _descripcion = TextEditingController();
  Uint8List? _foto;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _contacto.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    final elegido = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = elegido?.files.single.bytes;
    if (bytes == null || !mounted) {
      return;
    }
    try {
      // Mismo tratamiento que las fotos de productos: ≤1280 px en JPEG, muy por debajo de 1.5 MB.
      final reducida = await comprimirFoto(bytes);
      if (mounted) {
        setState(() => _foto = reducida);
      }
    } on Exception {
      if (mounted) {
        mostrarAviso(context, 'No se pudo leer esa imagen. Prueba con otra.');
      }
    }
  }

  Future<void> _enviar() async {
    if (_enviando || !(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final foto = _foto;
      await widget.estado.api.enviarReporte(
        contacto: _contacto.text.trim(),
        descripcion: _descripcion.text.trim(),
        foto: foto == null ? null : (nombre: 'reporte.jpg', datos: base64Encode(foto)),
      );
      if (mounted) {
        Navigator.pop(context);
        mostrarAviso(context, 'Gracias. Recibimos tu reporte y lo revisaremos pronto.');
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() {
          _error = error.mensaje;
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final foto = _foto;
    return AlertDialog(
      title: const Text('Reportar falla, queja o sugerencia'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _contacto,
                  enabled: !_enviando,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico o número de control',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: validarContactoReporte,
                ),
                const SizedBox(height: Espacio.m),
                TextFormField(
                  controller: _descripcion,
                  enabled: !_enviando,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: maximoDescripcionReporte,
                  decoration: const InputDecoration(
                    labelText: 'Describe brevemente el problema',
                    alignLabelWithHint: true,
                  ),
                  validator: (valor) =>
                      (valor ?? '').trim().length < 10 ? 'Cuéntanos qué pasó (mínimo 10 caracteres)' : null,
                ),
                const SizedBox(height: Espacio.s),
                if (foto == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _enviando ? null : _elegirFoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Adjuntar foto (opcional)'),
                    ),
                  )
                else
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(foto, width: 72, height: 72, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: Espacio.m),
                      const Expanded(child: Text('Foto adjunta')),
                      IconButton(
                        tooltip: 'Quitar foto',
                        onPressed: _enviando ? null : () => setState(() => _foto = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
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
        TextButton(onPressed: _enviando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: const Text('Enviar'),
        ),
      ],
    );
  }
}
