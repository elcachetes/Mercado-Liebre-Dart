import 'package:flutter/foundation.dart' show Uint8List, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../servicios/imagenes.dart';
import 'comunes.dart';

/// Hay cámara que abrir: celulares y tabletas, en la app nativa o en el navegador.
/// En escritorio la "cámara" del selector solo abriría otra vez los archivos.
bool get hayCamara => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Abre la cámara ([ImageSource.camera]) o la galería / los archivos del
/// dispositivo ([ImageSource.gallery]) y devuelve la foto elegida ya
/// comprimida con [comprimirFoto] (JPEG de hasta [ladoMaximo] px).
///
/// Null si la persona canceló o si la imagen no sirvió (en ese caso ya lo avisó).
Future<Uint8List?> leerFoto(BuildContext context, ImageSource origen, {int ladoMaximo = 1280}) async {
  final Uint8List? bytes;
  try {
    bytes = await (await ImagePicker().pickImage(source: origen))?.readAsBytes();
  } catch (_) {
    // Sin permiso de cámara o sin cámara disponible.
    if (context.mounted) {
      mostrarAviso(
        context,
        origen == ImageSource.camera
            ? 'No se pudo abrir la cámara. Revisa el permiso de cámara o elige una foto de la galería.'
            : 'No se pudo abrir la galería.',
      );
    }
    return null;
  }
  if (bytes == null) {
    return null;
  }
  try {
    return await comprimirFoto(bytes, ladoMaximo: ladoMaximo);
  } catch (_) {
    if (context.mounted) {
      mostrarAviso(context, 'No se pudo leer esa imagen. Prueba con una foto JPG o PNG.');
    }
    return null;
  }
}

/// Lo que eligió la persona en [elegirImagen]: una [foto] nueva (JPEG) o [quitar] la actual.
typedef ImagenElegida = ({Uint8List? foto, bool quitar});

/// Hoja inferior para cambiar una imagen: galería (o archivo), cámara si
/// [hayCamara] y, con [puedeQuitar], "Quitar" (pide confirmación).
///
/// [titulo] nombra la imagen ("Foto de perfil", "Logo de la tienda"…).
/// Devuelve null si la persona canceló.
Future<ImagenElegida?> elegirImagen(
  BuildContext context, {
  required String titulo,
  bool puedeQuitar = false,
  int ladoMaximo = 1280,
}) async {
  const galeria = 'galeria';
  const camara = 'camara';
  const quitar = 'quitar';
  final opcion = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (contexto) {
      final esquema = Theme.of(contexto).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(titulo, style: Theme.of(contexto).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(hayCamara ? 'Elegir de la galería' : 'Elegir archivo'),
              onTap: () => Navigator.pop(contexto, galeria),
            ),
            if (hayCamara)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.pop(contexto, camara),
              ),
            if (puedeQuitar)
              ListTile(
                leading: Icon(Icons.delete_outline, color: esquema.error),
                title: Text('Quitar', style: TextStyle(color: esquema.error)),
                onTap: () => Navigator.pop(contexto, quitar),
              ),
          ],
        ),
      );
    },
  );
  if (opcion == null || !context.mounted) {
    return null;
  }
  if (opcion == quitar) {
    final seguro = await confirmar(
      context,
      titulo: 'Quitar imagen',
      mensaje: 'Se borrará "$titulo". Puedes subir otra cuando quieras.',
      accion: 'Quitar',
    );
    return seguro ? (foto: null, quitar: true) : null;
  }
  final foto = await leerFoto(
    context,
    opcion == camara ? ImageSource.camera : ImageSource.gallery,
    ladoMaximo: ladoMaximo,
  );
  return foto == null ? null : (foto: foto, quitar: false);
}
