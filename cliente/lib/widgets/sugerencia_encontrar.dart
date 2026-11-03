import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../tema/tema_liebre.dart';

/// Lo que le falta a un negocio para que los compradores lo encuentren fácil.
enum FaltaParaEncontrar {
  /// Comida o producto sin punto en el mapa ni contacto: que diga dónde vende
  /// o, si no tiene un lugar fijo, deje un teléfono o red social.
  lugarOContacto,

  /// Comida o producto con contacto pero sin punto en el mapa: si vende en un
  /// lugar fijo, que lo indique.
  lugar,

  /// Servicio sin teléfono ni red social: es la única forma de localizarlo.
  contacto,
}

/// Qué sugerirle a [vendedor] en "Mi negocio"; null si ya se le puede encontrar.
///
/// Comida y producto se buscan por lugar (punto del mapa) o, si no hay lugar fijo,
/// por contacto. Un servicio se busca por contacto ([Vendedor.contactos]).
FaltaParaEncontrar? faltaParaEncontrar(Vendedor vendedor) {
  final tieneContacto = vendedor.contactos.isNotEmpty;
  if (vendedor.categoria == 'servicio') {
    return tieneContacto ? null : FaltaParaEncontrar.contacto;
  }
  if ((vendedor.edificio ?? '').isNotEmpty) {
    return null;
  }
  return tieneContacto ? FaltaParaEncontrar.lugar : FaltaParaEncontrar.lugarOContacto;
}

/// Consejo corto para el formulario de alta del negocio según su [categoria].
String consejoCategoria(String categoria) => categoria == 'servicio'
    ? 'Después agrega un teléfono o red social para que te localicen.'
    : 'Después indica dónde vendes o, si no tienes lugar fijo, un teléfono o red social.';

/// Tarjeta de "Ayuda a que te encuentren" al inicio de "Mi negocio".
///
/// No se muestra si [faltaParaEncontrar] no encuentra nada que sugerir.
class SugerenciaEncontrar extends StatelessWidget {
  /// [alElegirLugar] abre el selector de punto; [alAgregarContacto] lleva a la sección Contacto.
  const SugerenciaEncontrar({
    super.key,
    required this.vendedor,
    required this.alElegirLugar,
    required this.alAgregarContacto,
  });

  /// Negocio que se revisa.
  final Vendedor vendedor;

  /// Abre el selector del lugar donde vende.
  final VoidCallback? alElegirLugar;

  /// Lleva a los campos de contacto.
  final VoidCallback? alAgregarContacto;

  @override
  Widget build(BuildContext context) {
    final falta = faltaParaEncontrar(vendedor);
    if (falta == null) {
      return const SizedBox.shrink();
    }
    final esquema = Theme.of(context).colorScheme;
    final (titulo, mensaje) = switch (falta) {
      FaltaParaEncontrar.lugarOContacto => (
          'Ayuda a que te encuentren',
          'Indica el lugar del plantel donde vendes para que los compradores te ubiquen más fácil. '
              'Si no tienes un lugar fijo, agrega un teléfono o red social (WhatsApp, Telegram o Instagram) '
              'para que puedan localizarte.',
        ),
      FaltaParaEncontrar.lugar => (
          '¿Vendes en un lugar fijo?',
          'Indícalo para que los compradores te encuentren en el mapa. Si no, con tu contacto basta.',
        ),
      FaltaParaEncontrar.contacto => (
          'Ayuda a que te localicen',
          'Agrega un teléfono o red social (WhatsApp, Telegram o Instagram) para que los compradores '
              'puedan contactarte y contratar tu servicio más fácilmente.',
        ),
    };
    final pideLugar = falta != FaltaParaEncontrar.contacto;
    final pideContacto = falta != FaltaParaEncontrar.lugar;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.m),
      child: Card(
        color: esquema.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined, color: esquema.onSecondaryContainer),
                  const SizedBox(width: Espacio.s),
                  Expanded(
                    child: Text(
                      titulo,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: esquema.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Espacio.s),
              Text(mensaje, style: TextStyle(color: esquema.onSecondaryContainer)),
              const SizedBox(height: Espacio.s),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Espacio.s,
                children: [
                  if (pideLugar)
                    TextButton.icon(
                      onPressed: alElegirLugar,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Indicar lugar'),
                    ),
                  if (pideContacto)
                    TextButton.icon(
                      onPressed: alAgregarContacto,
                      icon: const Icon(Icons.contact_phone_outlined),
                      label: const Text('Agregar contacto'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
