import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mercado_liebre_api/almacen_s3.dart';
import 'package:mercado_liebre_api/medios.dart';
import 'package:test/test.dart';

/// Pruebas del cliente S3 (firma SigV4) y de [Medios] con un S3 falso local.
void main() {
  test('firmarS3 coincide con el ejemplo GET Object de la documentación de AWS', () {
    final cabeceras = firmarS3(
      metodo: 'GET',
      host: 'examplebucket.s3.amazonaws.com',
      rutaCanonica: '/test.txt',
      cabeceras: {'Range': 'bytes=0-9'},
      hashCuerpo: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      fecha: DateTime.utc(2013, 5, 24),
      region: 'us-east-1',
      llaveAcceso: 'AKIAIOSFODNN7EXAMPLE',
      llaveSecreta: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    );
    expect(
      cabeceras['authorization'],
      'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
      'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, '
      'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
    );
  });

  group('ConfiguracionS3.desdeEntorno', () {
    test('sin variables S3 usa el disco', () {
      expect(ConfiguracionS3.desdeEntorno({}), isNull);
    });

    test('con todas las variables arma la configuración y región garage', () {
      final s3 = ConfiguracionS3.desdeEntorno({
        'S3_ENDPOINT': 'https://s3.ejemplo.io',
        'S3_BUCKET': 'mercado-liebre',
        'S3_ACCESS_KEY': 'GKabc',
        'S3_SECRET_KEY': 'secreto',
      })!;
      expect(s3.endpoint.host, 's3.ejemplo.io');
      expect(s3.region, 'garage');
    });

    test('si falta alguna lo dice sin mostrar valores', () {
      expect(
        () => ConfiguracionS3.desdeEntorno({'S3_ENDPOINT': 'https://s3.ejemplo.io', 'S3_SECRET_KEY': 'secreto'}),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'mensaje', contains('S3_BUCKET'))
            .having((e) => e.message, 'mensaje', isNot(contains('secreto')))),
      );
    });
  });

  group('Medios con S3', () {
    late HttpServer servidor;
    late Map<String, Uint8List> objetos;
    late Directory temporal;
    late Medios medios;
    late List<String> firmas;

    setUp(() async {
      objetos = {};
      firmas = [];
      temporal = await Directory.systemTemp.createTemp('medios_s3_test');
      // S3 falso: guarda objetos por ruta y anota la cabecera de firma.
      servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servidor.listen((peticion) async {
        firmas.add(peticion.headers.value('authorization') ?? '');
        final ruta = peticion.uri.path;
        final cuerpo = await peticion.fold<List<int>>([], (a, b) => a..addAll(b));
        final respuesta = peticion.response;
        switch (peticion.method) {
          case 'PUT':
            objetos[ruta] = Uint8List.fromList(cuerpo);
            respuesta.statusCode = 200;
          case 'GET':
            final objeto = objetos[ruta];
            respuesta.statusCode = objeto == null ? 404 : 200;
            if (objeto != null) {
              respuesta.add(objeto);
            }
          case 'DELETE':
            objetos.remove(ruta);
            respuesta.statusCode = 204;
        }
        await respuesta.close();
      });
      final almacen = AlmacenS3(ConfiguracionS3(
        endpoint: Uri.parse('http://127.0.0.1:${servidor.port}'),
        bucket: 'mercado-liebre',
        llaveAcceso: 'GKprueba',
        llaveSecreta: 'secreto-de-prueba',
      ));
      medios = Medios(Directory('${temporal.path}/medios'), almacen: almacen);
    });

    tearDown(() async {
      medios.almacen?.cerrar();
      await servidor.close(force: true);
      await temporal.delete(recursive: true);
    });

    test('guarda en el bucket, la lee y la borra', () async {
      final bytes = [0xFF, 0xD8, 0xFF, 1, 2, 3];
      final url = await medios.guardar('foto.jpg', base64Encode(bytes));
      expect(url, matches(RegExp(r'^/medios/[0-9a-f]{16}\.jpg$')));
      final nombre = url.substring('/medios/'.length);
      expect(objetos.keys, ['/mercado-liebre/medios/$nombre']);
      expect(firmas.first, startsWith('AWS4-HMAC-SHA256 Credential=GKprueba/'));
      expect(Directory('${temporal.path}/medios').existsSync(), isFalse);

      final leida = await medios.leer(nombre);
      expect(leida!.bytes, bytes);
      expect(leida.tipo, 'image/jpeg');

      await medios.borrar(url);
      expect(objetos, isEmpty);
      expect(await medios.leer(nombre), isNull);
    });

    test('migra las fotos del disco al bucket y sigue sirviendo las no migradas', () async {
      final carpeta = await Directory('${temporal.path}/medios').create(recursive: true);
      await File('${carpeta.path}/abc123.png').writeAsBytes([1, 2, 3]);
      await File('${carpeta.path}/no-es-imagen.txt').writeAsString('x');
      expect((await medios.leer('abc123.png'))!.bytes, [1, 2, 3]);

      expect(await medios.migrarDiscoAS3(), 1);
      expect(objetos['/mercado-liebre/medios/abc123.png'], [1, 2, 3]);
      expect(File('${carpeta.path}/abc123.png').existsSync(), isFalse);
      expect(File('${carpeta.path}/no-es-imagen.txt').existsSync(), isTrue);
      expect((await medios.leer('abc123.png'))!.tipo, 'image/png');
    });

    test('rechaza nombres con rutas sin llamar a S3', () async {
      expect(await medios.leer('../conexion.json'), isNull);
      expect(firmas, isEmpty);
    });
  });
}
