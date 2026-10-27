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
}
