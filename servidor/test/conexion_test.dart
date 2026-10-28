import 'dart:io';

import 'package:mercado_liebre_api/base_datos.dart';
import 'package:mercado_liebre_api/configuracion.dart';
import 'package:test/test.dart';

/// Arranque contra una base que no responde: reintenta y da una pista útil.
void main() {
  test('la pista de "Failed host lookup" habla de la red de Docker', () {
    final texto = describirErrorConexion(
      const SocketException("Failed host lookup: 'olnvwfuraw4m5maauwuldus1'"),
    );
    expect(texto, contains('misma red de Docker'));
  });

  test('el mensaje usa solo la primera línea del error', () {
    expect(describirErrorConexion(Exception('uno\ndos')), 'Exception: uno');
  });

  test('esperarConexion reintenta y al final lanza el error', () async {
    // Un puerto libre que nadie escucha: la conexión se rechaza al instante.
    final libre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final puerto = libre.port;
    await libre.close();
    final url = 'postgres://u:clave-secreta@127.0.0.1:$puerto/x';
    final base = BaseDatos(Configuracion(
      urlBaseDatos: url,
      urlEntorno: url,
      ssl: false,
      sslEntorno: false,
      llaveSesion: 'llave-de-prueba-larga',
      puertoHttp: 0,
      aplicarEsquema: false,
      rutaEsquema: '',
      rutaDatos: '',
      adminCorreo: '',
      adminPassword: '',
    ));
    await base.abrir();
    final inicio = DateTime.now();
    await expectLater(
      base.esperarConexion(intentos: 2, espera: const Duration(milliseconds: 200)),
      throwsA(anything),
    );
    expect(DateTime.now().difference(inicio), greaterThanOrEqualTo(const Duration(milliseconds: 200)));
    await base.cerrar();
  });
}
