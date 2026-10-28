import 'dart:convert';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mercado_liebre_api/base_datos.dart';
import 'package:mercado_liebre_api/configuracion.dart';
import 'package:mercado_liebre_api/correo.dart';
import 'package:mercado_liebre_api/reportes.dart';
import 'package:mercado_liebre_api/repositorio.dart';
import 'package:mercado_liebre_api/rutas.dart';
import 'package:mercado_liebre_api/token_sesion.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Guarda los mensajes en lugar de abrir una conexión SMTP.
class CorreoFalso extends Correo {
  CorreoFalso()
      : super(const ConfiguracionCorreo(
          usuario: 'no.reply@ejemplo.com',
          contrasena: 'secreta',
          destinoReportes: 'buzon@ejemplo.com',
        ));

  final List<Message> enviados = [];

  @override
  Future<void> entregar(Message mensaje) async => enviados.add(mensaje);
}

/// PNG de 1×1 en base64.
const String pngMinimo =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

void main() {
  group('Reporte.desdeJson', () {
    test('acepta un número de control y lo pasa a mayúsculas', () {
      final reporte = Reporte.desdeJson({'contacto': 'c20111234', 'descripcion': 'El mapa no carga en mi celular.'});
      expect(reporte.contacto, 'C20111234');
      expect(reporte.foto, isNull);
    });

    test('rechaza un contacto que no es correo ni número de control', () {
      expect(
        () => Reporte.desdeJson({'contacto': 'hola', 'descripcion': 'El mapa no carga en mi celular.'}),
        throwsA(isA<ErrorApi>().having((e) => e.estado, 'estado', 400)),
      );
    });

    test('exige una descripción', () {
      expect(
        () => Reporte.desdeJson({'contacto': 'ana@itcj.edu.mx', 'descripcion': '  '}),
        throwsA(isA<ErrorApi>()),
      );
    });

    test('decodifica la foto y rechaza extensiones que no son imagen', () {
      final conFoto = Reporte.desdeJson({
        'contacto': 'ana@itcj.edu.mx',
        'descripcion': 'El botón de enviar no responde.',
        'foto': {'nombre': 'captura.PNG', 'datos': pngMinimo},
      });
      expect(conFoto.foto!.tipo, 'image/png');
      expect(conFoto.foto!.bytes, base64Decode(pngMinimo));

      expect(
        () => Reporte.desdeJson({
          'contacto': 'ana@itcj.edu.mx',
          'descripcion': 'El botón de enviar no responde.',
          'foto': {'nombre': 'virus.exe', 'datos': pngMinimo},
        }),
        throwsA(isA<ErrorApi>()),
      );
    });
  });

  group('mensajes', () {
    test('la verificación escapa el nombre en HTML e incluye el enlace', () async {
      final correo = CorreoFalso();
      await correo.enviarVerificacion(
        para: 'ana@itcj.edu.mx',
        nombre: '<b>Ana</b>',
        enlace: 'https://mercadoliebre.shop/api/verificar-correo?token=abc',
      );
      final mensaje = correo.enviados.single;
      expect(mensaje.recipients, ['ana@itcj.edu.mx']);
      expect(mensaje.html, contains('&lt;b&gt;Ana'));
      expect(mensaje.html, isNot(contains('<b>Ana')));
      expect(mensaje.text, contains('https://mercadoliebre.shop/api/verificar-correo?token=abc'));
    });

    test('el reporte va al buzón, responde al correo de quien reporta y adjunta la foto', () async {
      final correo = CorreoFalso();
      final reporte = Reporte.desdeJson({
        'contacto': 'Ana@ITCJ.edu.mx',
        'descripcion': 'El botón de enviar no responde.',
        'foto': {'nombre': 'captura.png', 'datos': pngMinimo},
      });
      await correo.enviarReporte(contacto: reporte.contacto, descripcion: reporte.descripcion, foto: reporte.foto);
      final mensaje = correo.enviados.single;
      expect(mensaje.recipients, ['buzon@ejemplo.com']);
      expect(mensaje.headers['Reply-To'], 'ana@itcj.edu.mx');
      expect(mensaje.text, contains('El botón de enviar no responde.'));
      expect(mensaje.attachments, hasLength(1));
    });

    test('sin credenciales SMTP responde 503 en lugar de intentar conectar', () {
      expect(
        () => Correo(const ConfiguracionCorreo()).entregar(Message()),
        throwsA(isA<ErrorApi>().having((e) => e.estado, 'estado', 503)),
      );
    });
  });

  group('rutas', () {
    late Handler handler;
    late CorreoFalso correo;
    late Directory temporal;

    setUp(() async {
      temporal = await Directory.systemTemp.createTemp('mercado_liebre_correo');
      correo = CorreoFalso();
      final configuracion = Configuracion(
        urlBaseDatos: 'postgres://u:p@localhost:5432/x',
        urlEntorno: 'postgres://u:p@localhost:5432/x',
        ssl: false,
        sslEntorno: false,
        llaveSesion: 'llave-de-prueba-larga',
        puertoHttp: 0,
        aplicarEsquema: false,
        rutaEsquema: '',
        rutaDatos: temporal.path,
        adminCorreo: '',
        adminPassword: '',
      );
      handler = const Pipeline().addMiddleware(capturarErrores()).addHandler(
            construirRutas(Repositorio(BaseDatos(configuracion)), TokenSesion(configuracion.llaveSesion), correo: correo)
                .call,
          );
    });

    tearDown(() => temporal.delete(recursive: true));

    Future<Response> reportar(Map<String, dynamic> cuerpo, {String ip = '10.0.0.1'}) async {
      return handler(Request(
        'POST',
        Uri.parse('http://localhost/api/reportes'),
        body: jsonEncode(cuerpo),
        headers: {'x-real-ip': ip},
      ));
    }

    test('un reporte válido se envía sin iniciar sesión', () async {
      final respuesta = await reportar({'contacto': '20111234', 'descripcion': 'No puedo subir la foto del producto.'});
      expect(respuesta.statusCode, 200);
      expect(correo.enviados, hasLength(1));
    });

    test('más de 5 reportes por hora desde la misma IP responde 429', () async {
      final cuerpo = {'contacto': '20111234', 'descripcion': 'No puedo subir la foto del producto.'};
      for (var i = 0; i < 5; i++) {
        expect((await reportar(cuerpo)).statusCode, 200);
      }
      expect((await reportar(cuerpo)).statusCode, 429);
      expect((await reportar(cuerpo, ip: '10.0.0.2')).statusCode, 200);
    });

    test('un enlace de verificación falso muestra una página de error, sin tocar la base', () async {
      final respuesta = await handler(Request('GET', Uri.parse('http://localhost/api/verificar-correo?token=falso')));
      expect(respuesta.statusCode, 400);
      expect(respuesta.headers['content-type'], startsWith('text/html'));
      expect(await respuesta.readAsString(), contains('Enlace no válido'));
    });

    test('un token de sesión no sirve como enlace de verificación', () async {
      final sesion = const TokenSesion('llave-de-prueba-larga').emitir('00000000-0000-0000-0000-000000000000');
      final respuesta = await handler(Request('GET', Uri.parse('http://localhost/api/verificar-correo?token=$sesion')));
      expect(respuesta.statusCode, 400);
    });
  });
}
