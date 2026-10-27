import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

import 'package:mercado_liebre_api/base_datos.dart';
import 'package:mercado_liebre_api/configuracion.dart';
import 'package:mercado_liebre_api/repositorio.dart';
import 'package:mercado_liebre_api/rutas.dart';
import 'package:mercado_liebre_api/token_sesion.dart';

/// Arranque de la API.
///
/// Orden: leer entorno, abrir PostgreSQL, aplicar el esquema si está
/// pedido, y escuchar HTTP. Los mensajes de consola no incluyen la URL
/// ni la contraseña de la base.
///
/// Al recibir SIGTERM (Docker/Coolify al redesplegar) o SIGINT (Ctrl+C)
/// deja de aceptar peticiones, espera las que están en curso y cierra el pool.
Future<void> main() async {
  final configuracion = await Configuracion.cargar();
  final base = BaseDatos(configuracion);
  await base.abrir();
  if (configuracion.aplicarEsquema) {
    stdout.writeln('Aplicando esquema de PostgreSQL…');
    await base.aplicarEsquema();
    stdout.writeln('Esquema listo.');
  }
  final repositorio = Repositorio(base);
  if (configuracion.adminCorreo.isNotEmpty && configuracion.adminPassword.isNotEmpty) {
    stdout.writeln('Comprobando la cuenta de administrador…');
    await repositorio.asegurarAdministrador(configuracion.adminCorreo, configuracion.adminPassword);
  }
  final tokens = TokenSesion(configuracion.llaveSesion);
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(capturarErrores())
      .addMiddleware(_cors(configuracion.origenCors))
      .addHandler(construirRutas(repositorio, tokens).call);

  final servidor = await serve(handler, InternetAddress.anyIPv4, configuracion.puertoHttp);
  stdout.writeln('API de Mercado Liebre en el puerto ${servidor.port}.');

  _alApagar(() async {
    stdout.writeln('Apagando la API…');
    await servidor.close();
    await base.cerrar();
  });
}

/// Ejecuta [cerrar] una sola vez al recibir SIGINT o SIGTERM.
void _alApagar(Future<void> Function() cerrar) {
  var cerrando = false;
  Future<void> alSenal(ProcessSignal _) async {
    if (cerrando) {
      return;
    }
    cerrando = true;
    await cerrar();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(alSenal);
  // Windows no admite escuchar SIGTERM; en Linux es la señal de `docker stop`.
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(alSenal);
  }
}

/// Permite que la app Flutter (web u otro origen) llame a la API.
Middleware _cors(String origen) {
  final cabeceras = {
    'Access-Control-Allow-Origin': origen,
    'Access-Control-Allow-Headers': 'origin, content-type, authorization',
    'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
    if (origen != '*') 'Vary': 'Origin',
  };
  return (Handler interno) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: cabeceras);
      }
      final respuesta = await interno(request);
      return respuesta.change(headers: cabeceras);
    };
  };
}
