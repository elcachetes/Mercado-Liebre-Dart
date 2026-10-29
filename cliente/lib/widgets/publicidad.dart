import 'dart:async';

import 'package:flutter/material.dart';

import '../configuracion.dart';
import '../modelos/modelos.dart';
import '../tema/tema_liebre.dart';
import 'comunes.dart';

/// Ancho de la barra lateral de publicidad en pantallas amplias.
const double anchoBarraPublicidad = 180;

/// Desde este ancho de pantalla la publicidad va en [BarraPublicidad];
/// más angosto (celulares), va entre los resultados de búsqueda ([AnunciosEnLista]).
const double anchoBarraLateral = 840;

/// Resultados de búsqueda antes del primer bloque de anuncios en pantallas angostas.
const int resultadosAntesDeAnuncio = 3;

/// Resultados entre un bloque de anuncios y el siguiente.
const int resultadosEntreAnuncios = 6;

/// Tiempo que se muestra cada imagen de un carrusel. Todas duran lo mismo.
const Duration duracionAnuncio = Duration(seconds: 6);

/// Barra lateral con [Anuncio.secciones] carruseles del mismo alto (arriba y abajo).
///
/// El administrador elige las imágenes y el negocio de cada una en
/// "Administración → Publicidad". Un carrusel sin imágenes muestra "Anúnciate aquí".
class BarraPublicidad extends StatelessWidget {
  /// [anuncios] suele ser `EstadoApp.anuncios`.
  const BarraPublicidad({super.key, required this.anuncios, required this.alAbrirVendedor});

  /// Todos los anuncios publicados (de ambas secciones).
  final List<Anuncio> anuncios;

  /// Abre la ficha del negocio anunciado dentro de la app.
  final ValueChanged<Vendedor> alAbrirVendedor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: anchoBarraPublicidad,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.s),
        child: Column(
          children: [
            for (var seccion = 1; seccion <= Anuncio.secciones; seccion++) ...[
              if (seccion > 1) const SizedBox(height: Espacio.s),
              Expanded(
                child: EspacioPublicitario(
                  anuncios: anunciosDeSeccion(anuncios, seccion),
                  alAbrirVendedor: alAbrirVendedor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Orden de una lista de [total] resultados con bloques de anuncios intercalados.
///
/// Cada elemento es el índice de un resultado, o null donde va un bloque de
/// anuncios: el primero tras [antes] resultados (tras el último si hay menos)
/// y luego uno cada [cada]. Sin resultados no hay anuncios.
List<int?> intercalarAnuncios(
  int total, {
  int antes = resultadosAntesDeAnuncio,
  int cada = resultadosEntreAnuncios,
}) {
  final orden = <int?>[];
  for (var i = 0; i < total; i++) {
    orden.add(i);
    final mostrados = i + 1;
    if (mostrados == antes || (mostrados > antes && (mostrados - antes) % cada == 0)) {
      orden.add(null);
    }
  }
  if (total > 0 && total < antes) {
    orden.add(null);
  }
  return orden;
}

/// Bloque de anuncios dentro de una lista (In-Feed), para pantallas sin [BarraPublicidad].
///
/// Pone los [Anuncio.secciones] carruseles lado a lado. El alto sigue la
/// proporción de las imágenes recomendadas (320 × 600 px) hasta [altoMaximo],
/// para que se recorten lo menos posible.
class AnunciosEnLista extends StatelessWidget {
  /// [anuncios] suele ser `EstadoApp.anuncios`.
  const AnunciosEnLista({super.key, required this.anuncios, required this.alAbrirVendedor});

  /// Alto máximo del bloque, para no ocupar toda la pantalla en tabletas.
  static const double altoMaximo = 320;

  /// Alto entre ancho de las imágenes recomendadas.
  static const double proporcion = 600 / 320;

  /// Todos los anuncios publicados (de ambas secciones).
  final List<Anuncio> anuncios;

  /// Abre la ficha del negocio anunciado dentro de la app.
  final ValueChanged<Vendedor> alAbrirVendedor;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Publicidad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Espacio.xs, bottom: Espacio.xs),
            child: Text('Publicidad', style: TextStyle(color: esquema.onSurfaceVariant, fontSize: 12)),
          ),
          LayoutBuilder(
            builder: (context, limites) {
              const separacion = Espacio.s;
              final ancho = (limites.maxWidth - separacion * (Anuncio.secciones - 1)) / Anuncio.secciones;
              return SizedBox(
                height: (ancho * proporcion).clamp(120.0, altoMaximo),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var seccion = 1; seccion <= Anuncio.secciones; seccion++) ...[
                      if (seccion > 1) const SizedBox(width: separacion),
                      Expanded(
                        child: EspacioPublicitario(
                          anuncios: anunciosDeSeccion(anuncios, seccion),
                          alAbrirVendedor: alAbrirVendedor,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Anuncios con imagen de [seccion], en el orden de su posición.
List<Anuncio> anunciosDeSeccion(List<Anuncio> anuncios, int seccion) {
  return anuncios.where((anuncio) => anuncio.seccion == seccion && anuncio.imagenUrl.isNotEmpty).toList()
    ..sort((a, b) => a.posicion.compareTo(b.posicion));
}

/// Un carrusel: rota sus imágenes cada [duracion] y al tocarlo abre el negocio anunciado.
///
/// Con una sola imagen no rota; sin imágenes muestra el espacio disponible.
class EspacioPublicitario extends StatefulWidget {
  /// [anuncios] ya filtrados y ordenados (ver [anunciosDeSeccion]).
  const EspacioPublicitario({
    super.key,
    required this.anuncios,
    required this.alAbrirVendedor,
    this.duracion = duracionAnuncio,
  });

  /// Imágenes del carrusel, de 0 a [Anuncio.porSeccion].
  final List<Anuncio> anuncios;

  /// Se llama con el negocio del anuncio visible al tocarlo.
  final ValueChanged<Vendedor> alAbrirVendedor;

  /// Tiempo de exhibición de cada imagen.
  final Duration duracion;

  @override
  State<EspacioPublicitario> createState() => _EspacioPublicitarioState();
}

class _EspacioPublicitarioState extends State<EspacioPublicitario> {
  int _indice = 0;
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _programar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precargar();
  }

  @override
  void didUpdateWidget(EspacioPublicitario anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.anuncios.length != widget.anuncios.length || anterior.duracion != widget.duracion) {
      _indice = 0;
      _programar();
      _precargar();
    }
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  /// Reinicia el reloj. Se llama también al elegir una imagen con los puntos,
  /// para que esa imagen dure lo mismo que las demás.
  void _programar() {
    _temporizador?.cancel();
    _temporizador = null;
    if (widget.anuncios.length < 2) {
      return;
    }
    _temporizador = Timer.periodic(widget.duracion, (_) {
      if (mounted) {
        setState(() => _indice = (_indice + 1) % widget.anuncios.length);
      }
    });
  }

  /// Descarga todas las imágenes de una vez para que el cambio no parpadee.
  void _precargar() {
    for (final anuncio in widget.anuncios) {
      precacheImage(NetworkImage(ConfiguracionApp.urlPublica(anuncio.imagenUrl)), context, onError: (_, __) {});
    }
  }

  void _ir(int indice) {
    setState(() => _indice = indice);
    _programar();
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final vacio = _Disponible(esquema: esquema);
    final anuncios = widget.anuncios;
    if (anuncios.isEmpty) {
      return Semantics(label: 'Espacio publicitario disponible', child: _marco(esquema, vacio, null));
    }
    final actual = anuncios[_indice.clamp(0, anuncios.length - 1)];
    final vendedor = actual.vendedor;
    final imagen = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 450),
      child: KeyedSubtree(
        key: ValueKey('${actual.seccion}-${actual.posicion}-${actual.imagenUrl}'),
        child: ImagenRed(actual.imagenUrl, alto: double.infinity, ancho: double.infinity, radio: 0, respaldo: vacio),
      ),
    );
    return Semantics(
      label: vendedor == null ? 'Anuncio' : 'Anuncio de ${vendedor.nombreNegocio}',
      button: vendedor != null,
      child: Tooltip(
        message: vendedor == null ? '' : 'Ver ${vendedor.nombreNegocio}',
        child: _marco(
          esquema,
          Stack(
            fit: StackFit.expand,
            children: [
              imagen,
              if (anuncios.length > 1)
                Positioned(left: 0, right: 0, bottom: Espacio.s, child: _puntos(anuncios.length)),
            ],
          ),
          vendedor == null ? null : () => widget.alAbrirVendedor(vendedor),
        ),
      ),
    );
  }

  Widget _marco(ColorScheme esquema, Widget contenido, VoidCallback? alTocar) {
    return Material(
      color: esquema.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(onTap: alTocar, child: SizedBox.expand(child: contenido)),
    );
  }

  /// Un punto por imagen; el de la imagen visible va relleno. Tocarlo salta a esa imagen.
  Widget _puntos(int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Semantics(
            label: 'Anuncio ${i + 1} de $total',
            selected: i == _indice,
            button: true,
            child: GestureDetector(
              onTap: () => _ir(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _indice ? 16 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: i == _indice ? 0.95 : 0.6),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                  ),
                ),
              ),
            ),
          ),
      ],
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
