import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../configuracion.dart';
import '../modelos/modelos.dart';
import 'comunes.dart';

/// Enlace público que abre la ficha de [vendedor] en la app (`/?vendedor=<id>`).
///
/// Al abrirlo, `abrirEnlaceCompartido` (detalle_vendedor.dart) muestra el negocio.
Uri enlaceVendedor(Vendedor vendedor) => _enlace({'vendedor': vendedor.id});

/// Enlace público que abre [producto] sobre la ficha de su negocio (`/?producto=<id>`).
Uri enlaceProducto(Producto producto) => _enlace({'producto': producto.id});

Uri _enlace(Map<String, String> consulta) =>
    Uri.parse(ConfiguracionApp.urlApp).replace(path: '/', queryParameters: consulta);

/// Dirección que publica [enlace] en Facebook (el texto lo escribe la persona allá).
Uri enFacebook(Uri enlace) => Uri.https('www.facebook.com', '/sharer/sharer.php', {'u': '$enlace'});

/// Dirección que envía [enlace] con [texto] por Telegram.
Uri enTelegram(Uri enlace, String texto) => Uri.https('t.me', '/share/url', {'url': '$enlace', 'text': texto});

/// Comparte la tienda [vendedor] por Facebook, Telegram o copiando el enlace.
Future<void> compartirVendedor(BuildContext context, Vendedor vendedor) {
  return compartir(
    context,
    titulo: 'Compartir tienda',
    texto: 'Mira ${vendedor.nombreNegocio} en Mercado Liebre',
    enlace: enlaceVendedor(vendedor),
  );
}

/// Comparte [producto] por Facebook, Telegram o copiando el enlace.
Future<void> compartirProducto(BuildContext context, Producto producto) {
  return compartir(
    context,
    titulo: 'Compartir producto',
    texto: '${producto.nombre} · ${producto.precioFormateado} en Mercado Liebre',
    enlace: enlaceProducto(producto),
  );
}

/// Hoja inferior con Facebook, Telegram y "Copiar enlace" para [enlace].
Future<void> compartir(BuildContext context, {required String titulo, required String texto, required Uri enlace}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (contexto) {
      Future<void> abrir(String red, Uri direccion) async {
        Navigator.pop(contexto);
        var abierto = false;
        try {
          abierto = await launchUrl(direccion, mode: LaunchMode.externalApplication);
        } catch (_) {
          abierto = false;
        }
        if (!abierto && context.mounted) {
          mostrarAviso(context, 'No se pudo abrir $red. Copia el enlace y pégalo allá.');
        }
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(titulo, style: Theme.of(contexto).textTheme.titleMedium),
              subtitle: Text(texto),
            ),
            ListTile(
              leading: const Icon(Icons.facebook, color: Color(0xFF1877F2)),
              title: const Text('Facebook'),
              onTap: () => abrir('Facebook', enFacebook(enlace)),
            ),
            ListTile(
              leading: const Icon(Icons.send, color: Color(0xFF229ED9)),
              title: const Text('Telegram'),
              onTap: () => abrir('Telegram', enTelegram(enlace, texto)),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copiar enlace'),
              onTap: () async {
                Navigator.pop(contexto);
                await Clipboard.setData(ClipboardData(text: '$enlace'));
                if (context.mounted) {
                  mostrarAviso(context, 'Enlace copiado.');
                }
              },
            ),
          ],
        ),
      );
    },
  );
}
