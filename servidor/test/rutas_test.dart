import 'dart:convert';
import 'dart:io';

import 'package:mercado_liebre_api/base_datos.dart';
import 'package:mercado_liebre_api/configuracion.dart';
import 'package:mercado_liebre_api/repositorio.dart';
import 'package:mercado_liebre_api/rutas.dart';
import 'package:mercado_liebre_api/token_sesion.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Pruebas de las rutas que responden antes de tocar PostgreSQL.
///
/// La base nunca se abre: si una ruta intentara consultarla, el pool
/// lanzaría `StateError` y la respuesta sería 500.
void main() {
  late Handler handler;
  late Directory temporal;

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('mercado_liebre_test');
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
    final repositorio = Repositorio(BaseDatos(configuracion));
    handler = const Pipeline()
        .addMiddleware(capturarErrores())
        .addHandler(construirRutas(repositorio, TokenSesion(configuracion.llaveSesion)).call);
  });

  tearDown(() => temporal.delete(recursive: true));

  Future<(int, Map<String, dynamic>)> pedir(String metodo, String ruta, {String? cuerpo, String? token}) async {
    final respuesta = await handler(Request(
      metodo,
      Uri.parse('http://localhost$ruta'),
      body: cuerpo,
      headers: {if (token != null) 'authorization': 'Bearer $token'},
    ));
    return (respuesta.statusCode, jsonDecode(await respuesta.readAsString()) as Map<String, dynamic>);
  }

  test('/salud responde ok', () async {
    final (estado, cuerpo) = await pedir('GET', '/salud');
    expect(estado, 200);
    expect(cuerpo['estado'], 'ok');
  });

  test('una ruta privada sin token responde 401', () async {
    final (estado, cuerpo) = await pedir('GET', '/api/yo');
    expect(estado, 401);
    expect(cuerpo['error'], contains('Inicia sesión'));
  });

  test('un token con firma falsa responde 401', () async {
    final (estado, _) = await pedir('GET', '/api/favoritos', token: 'a.b.c');
    expect(estado, 401);
  });

  test('un cuerpo que no es JSON responde 400, no 500', () async {
    final (estado, cuerpo) = await pedir('POST', '/api/sesion', cuerpo: '{no es json');
    expect(estado, 400);
    expect(cuerpo['error'], contains('JSON'));
  });

  test('un cuerpo JSON que no es objeto responde 400', () async {
    final (estado, _) = await pedir('POST', '/api/usuarios', cuerpo: '[1, 2]');
    expect(estado, 400);
  });

  test('/medios rechaza nombres con rutas', () async {
    final (estado, _) = await pedir('GET', '/medios/..%2Fconexion.json');
    expect(estado, 404);
  });

  test('borrar una cuenta sin sesión responde 401', () async {
    final (estado, _) = await pedir('DELETE', '/api/moderacion/usuarios/no-es-uuid');
    expect(estado, 401);
  });

  test('el plano del servidor incluye Z y ZZ', () {
    expect(codigosDelPlano, containsAll(['Z', 'ZZ', 'F1', '8']));
  });

  group('cuenta propia y contraseña', () {
    /// Respuesta HTML (las páginas del enlace del correo).
    Future<(int, String)> pedirHtml(String metodo, String ruta, {String? cuerpo}) async {
      final respuesta = await handler(Request(
        metodo,
        Uri.parse('http://localhost$ruta'),
        body: cuerpo,
        headers: {if (cuerpo != null) 'content-type': 'application/x-www-form-urlencoded'},
      ));
      return (respuesta.statusCode, await respuesta.readAsString());
    }

    test('eliminar la cuenta propia sin sesión responde 401', () async {
      final (estado, _) = await pedir('DELETE', '/api/yo', cuerpo: '{"password": "12345678"}');
      expect(estado, 401);
    });

    test('olvidé mi contraseña exige un correo', () async {
      final (estado, cuerpo) = await pedir('POST', '/api/contrasena/olvido', cuerpo: '{"correo": "ana"}');
      expect(estado, 400);
      expect(cuerpo['error'], contains('correo'));
    });

    test('olvidé mi contraseña sin SMTP responde 503 sin revelar si la cuenta existe', () async {
      final (estado, _) = await pedir('POST', '/api/contrasena/olvido', cuerpo: '{"correo": "ana@itcj.edu.mx"}');
      expect(estado, 503);
    });

    test('un enlace de restablecimiento falso muestra la página de error', () async {
      final (estado, html) = await pedirHtml('GET', '/api/restablecer?token=a.b.c');
      expect(estado, 400);
      expect(html, contains('Enlace no válido'));
    });

    test('un token de sesión no sirve para restablecer la contraseña', () async {
      final sesion = const TokenSesion('llave-de-prueba-larga').emitir('00000000-0000-0000-0000-000000000000');
      final (estado, _) = await pedirHtml('POST', '/api/restablecer', cuerpo: 'token=$sesion&password=12345678&confirmacion=12345678');
      expect(estado, 400);
    });

    test('con un enlace válido valida la contraseña antes de tocar la base', () async {
      final token = const TokenSesion('llave-de-prueba-larga|restablecer-contrasena')
          .emitir('00000000-0000-0000-0000-000000000000');
      final (corta, html) = await pedirHtml('POST', '/api/restablecer', cuerpo: 'token=$token&password=123&confirmacion=123');
      expect(corta, 200);
      expect(html, contains('al menos 8 caracteres'));
      final (distinta, otra) =
          await pedirHtml('POST', '/api/restablecer', cuerpo: 'token=$token&password=12345678&confirmacion=87654321');
      expect(distinta, 200);
      expect(otra, contains('no coinciden'));
    });
  });

  group('administración', () {
    for (final (metodo, ruta) in [
      ('GET', '/api/admin/resumen'),
      ('GET', '/api/admin/tablas'),
      ('GET', '/api/admin/tablas/users'),
      ('GET', '/api/admin/restablecimientos'),
      ('PATCH', '/api/admin/usuarios/x'),
      ('POST', '/api/admin/usuarios/x/contrasena'),
      ('GET', '/api/admin/vendedores'),
      ('PATCH', '/api/admin/vendedores/x'),
      ('DELETE', '/api/admin/productos/x'),
      ('PUT', '/api/admin/anuncios/1/1'),
      ('GET', '/api/admin/avisos'),
      ('DELETE', '/api/admin/calificaciones/x/y'),
    ]) {
      test('$metodo $ruta sin sesión responde 401', () async {
        final (estado, _) = await pedir(metodo, ruta, cuerpo: metodo == 'GET' ? null : '{}');
        expect(estado, 401);
      });
    }

    test('el explorador nunca expone password_hash', () {
      for (final tabla in Repositorio.tablasVisibles.values) {
        expect(tabla.columnas, isNot(contains('password')));
      }
    });
  });
}
