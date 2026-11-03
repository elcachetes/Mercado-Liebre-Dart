import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mercado_liebre/servicios/imagenes.dart';

/// comprimirFoto debe funcionar también en web. Córrela en el navegador:
/// `flutter test test/imagenes_test.dart --platform chrome`.
void main() {
  testWidgets('comprimirFoto reduce un JPG y un PNG (también en el navegador)', (tester) async {
    final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 2000, height: 3000)));
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 400, height: 300)));
    final deJpg = await tester.runAsync(() => comprimirFoto(jpg));
    final dePng = await tester.runAsync(() => comprimirFoto(png));
    final leidaJpg = img.decodeJpg(deJpg!)!;
    expect([leidaJpg.width, leidaJpg.height], [853, 1280]);
    // Más chica que el límite: no se agranda.
    final leidaPng = img.decodeJpg(dePng!)!;
    expect([leidaPng.width, leidaPng.height], [400, 300]);
  });
}
