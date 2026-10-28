import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../modelos/modelos.dart';
import '../tema/tema_liebre.dart';
import 'comunes.dart';

/// Ancho de la barra lateral de publicidad en pantallas amplias.
const double anchoBarraPublicidad = 180;

/// Barra lateral dividida en dos espacios publicitarios del mismo alto.
///
/// El administrador sube la imagen y el enlace de cada anuncio en
/// "Administración → Apariencia". Sin imagen se muestra "Anúnciate aquí".
class BarraPublicidad extends StatelessWidget {
  /// Lee los anuncios de [apariencia].
  const BarraPublicidad({super.key, required this.apariencia});

  /// Imágenes y enlaces publicados.
  final Apariencia apariencia;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: anchoBarraPublicidad,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.s),
        child: Column(
          children: [
            Expanded(child: EspacioPublicitario(imagen: apariencia.publicidad1Url, enlace: apariencia.publicidad1Enlace)),
            const SizedBox(height: Espacio.s),
            Expanded(child: EspacioPublicitario(imagen: apariencia.publicidad2Url, enlace: apariencia.publicidad2Enlace)),
          ],
        ),
      ),
    );
  }
}

/// Un anuncio: imagen que llena el espacio y, si hay enlace, lo abre en otra pestaña.
class EspacioPublicitario extends StatelessWidget {
  /// [imagen] y [enlace] pueden venir vacíos.
  const EspacioPublicitario({super.key, required this.imagen, required this.enlace});

  /// `/medios/...` o URL completa; vacía muestra el lugar disponible.
  final String imagen;

  /// Página http(s) del anunciante; vacía no abre nada.
  final String enlace;

  Future<void> _abrir(BuildContext context) async {
    final uri = Uri.tryParse(enlace);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      mostrarAviso(context, 'No se pudo abrir el anuncio.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final vacio = _Disponible(esquema: esquema);
    final contenido = imagen.isEmpty
        ? vacio
        : ImagenRed(imagen, alto: double.infinity, ancho: double.infinity, radio: 0, respaldo: vacio);
    return Semantics(
      label: imagen.isEmpty ? 'Espacio publicitario disponible' : 'Anuncio',
      link: enlace.isNotEmpty,
      child: Material(
        color: esquema.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: enlace.isEmpty ? null : () => _abrir(context),
          child: SizedBox.expand(child: contenido),
        ),
      ),
    );
  }
}

class _Disponible extends StatelessWidget {
  const _Disponible({required this.esquema});

  final ColorScheme esquema;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 36, color: esquema.onSurfaceVariant),
            const SizedBox(height: Espacio.s),
            Text(
              'Anúnciate aquí',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: esquema.onSurfaceVariant),
            ),
            const SizedBox(height: Espacio.xs),
            Text(
              'Espacio publicitario',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: esquema.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
