import 'package:flutter/material.dart';

import '../mapa/puntos_campus.dart';
import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/tarjeta_vendedor.dart';
import 'detalle_vendedor.dart';

/// Plano del plantel y su leyenda, cada uno en la mitad de la pantalla.
///
/// Tocar un edificio del plano o un lugar de la lista muestra a quien vende ahí.
class MapaPantalla extends StatefulWidget {
  /// [estado] decide si se ofrece "Registrar mi puesto aquí".
  const MapaPantalla({super.key, required this.estado});

  /// Sesión. Si hay un vendedor, puede registrar su puesto.
  final EstadoApp estado;

  @override
  State<MapaPantalla> createState() => _MapaPantallaState();
}

class _MapaPantallaState extends State<MapaPantalla> {
  static const double _escalaMinima = 0.05;
  static const double _escalaMaxima = 5;

  /// Transformación del plano. El primer encuadre lo deja entero en pantalla.
  final TransformationController _transformacion = TransformationController();

  /// Vendedores agrupados por código de punto (en mayúsculas).
  Map<String, List<Vendedor>> _porPunto = {};
  String? _error;
  bool _cargando = true;
  Size? _vista;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _transformacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final lista = await widget.estado.api.vendedores();
      if (!mounted) {
        return;
      }
      final agrupados = <String, List<Vendedor>>{};
      for (final vendedor in lista) {
        final codigo = vendedor.edificio?.toUpperCase();
        if (codigo != null) {
          agrupados.putIfAbsent(codigo, () => []).add(vendedor);
        }
      }
      setState(() {
        _porPunto = agrupados;
        _error = null;
        _cargando = false;
      });
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() {
          _error = error.mensaje;
          _cargando = false;
        });
      }
    }
  }

  int _abiertosEn(String codigo) => _porPunto[codigo]?.where((vendedor) => vendedor.disponible).length ?? 0;

  /// Guarda el tamaño del marco del plano y lo encuadra la primera vez.
  ///
  /// El primer encuadre se aplica una sola vez, después del primer layout,
  /// para no pelear con un gesto que la persona ya haya empezado.
  void _encuadrar(BoxConstraints limites) {
    if (!limites.hasBoundedWidth || !limites.hasBoundedHeight || limites.maxWidth <= 0 || limites.maxHeight <= 0) {
      return;
    }
    final primera = _vista == null;
    _vista = limites.biggest;
    if (primera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _restablecer();
        }
      });
    }
  }

  /// Escala el dibujo para que llene el marco sin recortar edificios, centrado.
  void _restablecer() {
    final vista = _vista;
    if (vista == null) {
      return;
    }
    final porAncho = vista.width / dibujoAncho;
    final porAlto = vista.height / imagenAlto;
    final escala = porAncho < porAlto ? porAncho : porAlto;
    final dx = (vista.width - dibujoAncho * escala) / 2;
    final dy = (vista.height - imagenAlto * escala) / 2;
    _transformacion.value = Matrix4.translationValues(dx, dy, 0)..multiply(Matrix4.diagonal3Values(escala, escala, 1));
  }

  /// Acerca o aleja manteniendo el centro de la vista.
  void _zoom(double factor) {
    final vista = _vista;
    if (vista == null) {
      return;
    }
    final actual = _transformacion.value.getMaxScaleOnAxis();
    final destino = (actual * factor).clamp(_escalaMinima, _escalaMaxima);
    final real = destino / actual;
    final cx = vista.width / 2;
    final cy = vista.height / 2;
    _transformacion.value = Matrix4.translationValues(cx, cy, 0)
      ..multiply(Matrix4.diagonal3Values(real, real, 1))
      ..multiply(Matrix4.translationValues(-cx, -cy, 0))
      ..multiply(_transformacion.value);
  }

  Future<void> _abrir(PuntoCampus punto) async {
    final enPunto = _porPunto[punto.codigo] ?? const <Vendedor>[];
    final abiertos = enPunto.where((vendedor) => vendedor.disponible).toList();
    final cerrados = enPunto.where((vendedor) => !vendedor.disponible).toList();
    final usuario = widget.estado.usuario;

    Widget tarjeta(BuildContext contexto, Vendedor vendedor) {
      return Padding(
        padding: const EdgeInsets.only(top: Espacio.s),
        child: TarjetaVendedor(
          vendedor: vendedor,
          favorito: widget.estado.esFavorito(vendedor.id),
          alTocar: () {
            Navigator.pop(contexto);
            abrirVendedor(context, widget.estado, vendedor);
          },
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (contexto) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(punto.titulo, style: Theme.of(contexto).textTheme.titleLarge),
              const SizedBox(height: Espacio.xs),
              Text(
                abiertos.isEmpty
                    ? 'Nadie está vendiendo en este punto ahora.'
                    : '${abiertos.length} vendedor${abiertos.length == 1 ? '' : 'es'} disponible${abiertos.length == 1 ? '' : 's'}',
                style: TextStyle(color: Theme.of(contexto).colorScheme.onSurfaceVariant),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final vendedor in abiertos) tarjeta(contexto, vendedor),
                    if (cerrados.isNotEmpty) ...[
                      const TituloSeccion('Registrados aquí, pero cerrados'),
                      for (final vendedor in cerrados) tarjeta(contexto, vendedor),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Espacio.m),
              if (usuario != null && usuario.esVendedor)
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(contexto);
                    await _registrar(punto);
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Registrar mi puesto aquí'),
                )
              else if (usuario == null)
                Text(
                  '¿Vendes aquí? Entra con una cuenta de vendedor para registrar tu puesto.',
                  style: TextStyle(color: Theme.of(contexto).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _registrar(PuntoCampus punto) async {
    final ok = await intentar(
      context,
      () => widget.estado.api.asignarPunto(punto.codigo),
      exito: 'Tu puesto quedó en ${punto.titulo}.',
    );
    if (ok) {
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.l, Espacio.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mapa del plantel', style: tema.textTheme.titleLarge),
              const SizedBox(height: Espacio.xs),
              Text(
                'Toca un edificio en el plano o un lugar de la lista para ver quién vende ahí. '
                'Lo marcado en rojo tiene vendedores abiertos.',
                style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
              ),
              if (_error != null) ...[
                const SizedBox(height: Espacio.s),
                Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: tema.colorScheme.error),
                    const SizedBox(width: Espacio.s),
                    Expanded(child: Text(_error!, style: TextStyle(color: tema.colorScheme.error))),
                    TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_cargando) const LinearProgressIndicator(),
        Expanded(
          child: LayoutBuilder(
            builder: (contexto, limites) {
              // Lado a lado si hay ancho; en el celular, el plano arriba y la lista abajo.
              final ladoALado = limites.maxWidth >= 720;
              return Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.m, 0, Espacio.m, Espacio.m),
                child: Flex(
                  direction: ladoALado ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _marco(_plano())),
                    SizedBox(width: ladoALado ? Espacio.m : 0, height: ladoALado ? 0 : Espacio.m),
                    Expanded(child: _marco(_leyenda())),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Recuadro con borde que contiene el plano o la leyenda.
  Widget _marco(Widget contenido) {
    final esquema = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: esquema.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: contenido),
    );
  }

  /// Solo el dibujo del plantel (la mitad izquierda de la imagen), con zoom.
  Widget _plano() {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            // Fondo claro como el de la imagen, también en modo oscuro.
            color: const Color(0xFFF3EEEE),
            child: LayoutBuilder(
              builder: (contexto, limites) {
                _encuadrar(limites);
                return InteractiveViewer(
                  transformationController: _transformacion,
                  alignment: Alignment.topLeft,
                  minScale: _escalaMinima,
                  maxScale: _escalaMaxima,
                  boundaryMargin: const EdgeInsets.all(80),
                  constrained: false,
                  child: SizedBox(
                    width: dibujoAncho.toDouble(),
                    height: imagenAlto.toDouble(),
                    // El Stack recorta la leyenda impresa, que queda fuera de dibujoAncho.
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          width: imagenAncho.toDouble(),
                          height: imagenAlto.toDouble(),
                          child: Image.asset(
                            'assets/mapa_plantel.jpg',
                            fit: BoxFit.fill,
                            semanticLabel: 'Plano del plantel del ITCJ',
                          ),
                        ),
                        for (final punto in puntosCampus)
                          for (final zona in punto.plano) _zona(zona, punto),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          right: Espacio.s,
          bottom: Espacio.s,
          child: Card(
            elevation: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: 'Acercar', icon: const Icon(Icons.add), onPressed: () => _zoom(1.5)),
                IconButton(tooltip: 'Alejar', icon: const Icon(Icons.remove), onPressed: () => _zoom(1 / 1.5)),
                IconButton(
                  tooltip: 'Ver el plano completo',
                  icon: const Icon(Icons.fit_screen_outlined),
                  onPressed: _restablecer,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Leyenda como texto de la app: más grande y nítida que la impresa en la imagen.
  Widget _leyenda() {
    final tema = Theme.of(context);
    final conVenta = puntosCampus.where((punto) => _abiertosEn(punto.codigo) > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.m, Espacio.m, Espacio.m, Espacio.s),
          child: Row(
            children: [
              Expanded(child: Text('Edificios y lugares', style: tema.textTheme.titleMedium)),
              Text(
                conVenta == 0 ? 'Sin ventas abiertas' : '$conVenta con ventas abiertas',
                style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(Espacio.s),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 52,
              crossAxisSpacing: Espacio.xs,
              mainAxisSpacing: Espacio.xs,
            ),
            itemCount: puntosCampus.length,
            itemBuilder: (contexto, indice) => _lugar(puntosCampus[indice]),
          ),
        ),
      ],
    );
  }

  /// Renglón de la leyenda: código, nombre y cuántos vendedores están abiertos.
  Widget _lugar(PuntoCampus punto) {
    final tema = Theme.of(context);
    final abiertos = _abiertosEn(punto.codigo);
    final activo = abiertos > 0;
    return Semantics(
      button: true,
      label: '${punto.titulo}, $abiertos abiertos',
      excludeSemantics: true,
      child: Material(
        color: activo ? ColoresLiebre.primario.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _abrir(punto),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espacio.s),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: activo ? ColoresLiebre.primario : tema.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    punto.codigo,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: activo ? Colors.white : tema.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: Espacio.s),
                Expanded(
                  child: Text(
                    punto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodyLarge,
                  ),
                ),
                if (activo)
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: ColoresLiebre.primario,
                    child: Text('$abiertos', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _zona(RectPlano zona, PuntoCampus punto) {
    final cantidad = _abiertosEn(punto.codigo);
    return Positioned(
      left: zona.x.toDouble(),
      top: zona.y.toDouble(),
      width: zona.ancho.toDouble(),
      height: zona.alto.toDouble(),
      child: Semantics(
        button: true,
        label: '${punto.titulo}, $cantidad abiertos',
        child: Material(
          color: Colors.white.withValues(alpha: 0.02),
          child: InkWell(
            onTap: () => _abrir(punto),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cantidad > 0 ? ColoresLiebre.primario.withValues(alpha: 0.15) : null,
                border: cantidad > 0 ? Border.all(color: ColoresLiebre.primario, width: 2) : null,
              ),
              child: cantidad == 0
                  ? null
                  : Align(
                      alignment: Alignment.topRight,
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: ColoresLiebre.primario,
                        child: Text('$cantidad', style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
