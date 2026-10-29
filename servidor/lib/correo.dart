import 'dart:convert';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'repositorio.dart';

/// Datos del servidor SMTP y de los destinatarios, leídos del entorno.
///
/// La contraseña solo vive en memoria y nunca se escribe en logs.
/// Si falta usuario o contraseña, [configurado] es falso y la API responde
/// 503 al intentar enviar, en lugar de fallar al arrancar.
class ConfiguracionCorreo {
  /// Valores ya resueltos. Ver [ConfiguracionCorreo.desdeEntorno].
  const ConfiguracionCorreo({
    this.host = 'smtppro.zoho.com',
    this.puerto = 465,
    this.usuario = '',
    this.contrasena = '',
    this.remitente = '',
    this.destinoReportes = '',
    this.urlPublica = '',
  });

  /// Lee `SMTP_HOST`, `SMTP_PUERTO`, `SMTP_USUARIO`, `SMTP_PASSWORD`,
  /// `CORREO_REMITENTE`, `CORREO_REPORTES` y `URL_PUBLICA`.
  factory ConfiguracionCorreo.desdeEntorno(Map<String, String> valores) {
    String texto(String clave) => (valores[clave] ?? '').trim();
    final host = texto('SMTP_HOST');
    return ConfiguracionCorreo(
      host: host.isEmpty ? 'smtppro.zoho.com' : host,
      puerto: int.tryParse(texto('SMTP_PUERTO')) ?? 465,
      usuario: texto('SMTP_USUARIO'),
      // Sin trim: los espacios podrían ser parte de la contraseña.
      contrasena: valores['SMTP_PASSWORD'] ?? '',
      remitente: texto('CORREO_REMITENTE'),
      destinoReportes: texto('CORREO_REPORTES'),
      urlPublica: texto('URL_PUBLICA'),
    );
  }

  /// Servidor SMTP saliente.
  final String host;

  /// 465 usa SSL directo; cualquier otro (587) usa STARTTLS.
  final int puerto;

  /// Cuenta con la que se autentica el envío.
  final String usuario;

  /// Contraseña SMTP. Solo en memoria.
  final String contrasena;

  /// Dirección "De:". Vacía usa [usuario].
  final String remitente;

  /// Buzón que recibe los reportes de fallas y sugerencias.
  final String destinoReportes;

  /// Origen público de la app (`https://mercadoliebre.shop`), para los enlaces.
  /// Vacío: se deduce del encabezado `Host` de la petición.
  final String urlPublica;

  /// Verdadero si hay credenciales para enviar.
  bool get configurado => usuario.isNotEmpty && contrasena.isNotEmpty;

  /// Dirección que aparece como remitente.
  String get direccionRemitente => remitente.isEmpty ? usuario : remitente;
}

/// Foto adjunta a un reporte, ya validada.
class FotoAdjunta {
  /// [bytes] ya decodificados de base64.
  const FotoAdjunta({required this.nombre, required this.tipo, required this.bytes});

  /// Nombre con extensión, por ejemplo `captura.jpg`.
  final String nombre;

  /// Tipo MIME (`image/jpeg`, `image/png`…).
  final String tipo;

  /// Contenido de la imagen.
  final List<int> bytes;
}

/// Envía los correos de la app por SMTP.
///
/// Las pruebas sobrescriben [entregar] para no abrir conexiones.
class Correo {
  /// Usa [configuracion] para conectarse en cada envío.
  Correo(this.configuracion);

  /// Servidor, cuenta y destinatarios.
  final ConfiguracionCorreo configuracion;

  /// Pide al usuario que confirme su correo con [enlace].
  Future<void> enviarVerificacion({required String para, required String nombre, required String enlace}) async {
    final seguro = const HtmlEscape();
    final mensaje = Message()
      ..from = Address(configuracion.direccionRemitente, 'Mercado Liebre')
      ..recipients.add(para)
      ..subject = 'Confirma tu correo en Mercado Liebre'
      ..text = 'Hola $nombre:\n\n'
          'Para calificar y comentar en Mercado Liebre confirma tu correo abriendo este enlace:\n\n'
          '$enlace\n\n'
          'El enlace vence en 48 horas. Si no creaste esta cuenta, ignora este mensaje.'
      ..html = '<p>Hola ${seguro.convert(nombre)}:</p>'
          '<p>Para calificar y comentar en Mercado Liebre confirma tu correo:</p>'
          '<p><a href="${seguro.convert(enlace)}" '
          'style="background:#d32f2f;color:#fff;padding:10px 18px;border-radius:6px;text-decoration:none">'
          'Confirmar mi correo</a></p>'
          '<p style="color:#666">El enlace vence en 48 horas. Si no creaste esta cuenta, ignora este mensaje.</p>';
    await entregar(mensaje);
  }

  /// Manda el enlace para elegir una contraseña nueva. Vence en [vigencia].
  Future<void> enviarRestablecimiento({
    required String para,
    required String nombre,
    required String enlace,
    required Duration vigencia,
  }) async {
    final seguro = const HtmlEscape();
    final plazo = vigencia.inMinutes >= 120 ? '${vigencia.inHours} horas' : '${vigencia.inMinutes} minutos';
    final mensaje = Message()
      ..from = Address(configuracion.direccionRemitente, 'Mercado Liebre')
      ..recipients.add(para)
      ..subject = 'Restablece tu contraseña de Mercado Liebre'
      ..text = 'Hola $nombre:\n\n'
          'Recibimos una solicitud para cambiar la contraseña de tu cuenta. Elige una nueva aquí:\n\n'
          '$enlace\n\n'
          'El enlace vence en $plazo y solo sirve una vez. Si no lo pediste, ignora este mensaje: '
          'tu contraseña actual sigue funcionando.'
      ..html = '<p>Hola ${seguro.convert(nombre)}:</p>'
          '<p>Recibimos una solicitud para cambiar la contraseña de tu cuenta.</p>'
          '<p><a href="${seguro.convert(enlace)}" '
          'style="background:#d32f2f;color:#fff;padding:10px 18px;border-radius:6px;text-decoration:none">'
          'Elegir contraseña nueva</a></p>'
          '<p style="color:#666">El enlace vence en $plazo y solo sirve una vez. Si no lo pediste, '
          'ignora este mensaje: tu contraseña actual sigue funcionando.</p>';
    await entregar(mensaje);
  }

  /// Manda un reporte de falla, queja o sugerencia al buzón de la administración.
  ///
  /// El cuerpo va en texto plano: lo que escribe la persona no se interpreta como HTML.
  Future<void> enviarReporte({
    required String contacto,
    required String descripcion,
    String? cuenta,
    FotoAdjunta? foto,
  }) async {
    if (configuracion.destinoReportes.isEmpty) {
      throw ErrorApi(503, 'El envío de reportes no está configurado.');
    }
    final fecha = DateTime.now().toUtc().toIso8601String();
    final mensaje = Message()
      ..from = Address(configuracion.direccionRemitente, 'Mercado Liebre')
      ..recipients.add(configuracion.destinoReportes)
      ..subject = 'Reporte de falla, queja o sugerencia'
      ..text = 'Contacto: $contacto\n'
          'Cuenta: ${cuenta ?? 'sin sesión'}\n'
          'Fecha (UTC): $fecha\n\n'
          '$descripcion\n';
    if (contacto.contains('@')) {
      mensaje.headers['Reply-To'] = contacto;
    }
    if (foto != null) {
      mensaje.attachments.add(StreamAttachment(Stream.value(foto.bytes), foto.tipo, fileName: foto.nombre));
    }
    await entregar(mensaje);
  }

  /// Conecta al SMTP y envía [mensaje].
  ///
  /// Un fallo se escribe en stderr sin la contraseña y llega al cliente
  /// como un mensaje genérico.
  Future<void> entregar(Message mensaje) async {
    if (!configuracion.configurado) {
      throw ErrorApi(503, 'El envío de correos no está configurado en el servidor.');
    }
    final servidor = SmtpServer(
      configuracion.host,
      port: configuracion.puerto,
      ssl: configuracion.puerto == 465,
      username: configuracion.usuario,
      password: configuracion.contrasena,
    );
    try {
      await send(mensaje, servidor, timeout: const Duration(seconds: 20));
    } on MailerException catch (error) {
      // Rechazo del servidor SMTP (por ejemplo, "535 Authentication failed").
      stderr.writeln('No se pudo enviar el correo "${mensaje.subject}": ${error.message}');
      throw ErrorApi(502, 'No se pudo enviar el correo. Inténtalo más tarde.');
    } on Exception catch (error) {
      // Red, TLS o tiempo agotado al hablar con el SMTP.
      stderr.writeln('Sin conexión con ${configuracion.host}:${configuracion.puerto}: $error');
      throw ErrorApi(502, 'No se pudo enviar el correo. Inténtalo más tarde.');
    }
  }
}
