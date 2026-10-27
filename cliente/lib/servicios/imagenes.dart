import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Reduce una foto a [ladoMaximo] px por su lado mayor y la codifica en JPEG.
///
/// Una foto de celular pesa 3–6 MB y la API acepta hasta 1.5 MB; el
/// resultado típico ronda 150–300 KB. La decodificación usa el motor de
/// Flutter (rápido, funciona en web) y `package:image` solo codifica.
/// Las zonas transparentes de un PNG quedan en blanco.
Future<Uint8List> comprimirFoto(Uint8List original, {int ladoMaximo = 1280, int calidad = 82}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(original);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final escala = min(1.0, ladoMaximo / max(descriptor.width, descriptor.height));
  final codec = await descriptor.instantiateCodec(
    targetWidth: max(1, (descriptor.width * escala).round()),
    targetHeight: max(1, (descriptor.height * escala).round()),
  );
  final cuadro = await codec.getNextFrame();
  final ancho = cuadro.image.width;
  final alto = cuadro.image.height;
  final rgba = await cuadro.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  cuadro.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  if (rgba == null) {
    throw const FormatException('No se pudo leer la imagen.');
  }

  final foto = img.Image.fromBytes(width: ancho, height: alto, bytes: rgba.buffer, numChannels: 4);
  final fondo = img.fill(img.Image(width: ancho, height: alto), color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(fondo, foto);
  return Uint8List.fromList(img.encodeJpg(fondo, quality: calidad));
}
