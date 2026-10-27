import 'package:flutter/material.dart';

import '../mapa/puntos_campus.dart';
import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/tarjeta_vendedor.dart';
import 'detalle_vendedor.dart';

/// Plano del plantel. Tocar un edificio o su nombre lista a quien vende ahí.
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
  double? _escalaEncuadre;

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

  /// Escala el plano para que quepa en [limites] sin recortar edificios.
  ///
  /// Se aplica una sola vez, después del primer layout, para no pelear
  /// con un gesto que la persona ya haya empezado.
  void _encuadrar(BoxConstraints limites) {
    if (!limites.hasBoundedWidth || !limites.hasBoundedHeight || limites.maxWidth <= 0 || limites.maxHeight <= 0) {
      return;
    }
    _vista = limites.biggest;
    if (_escalaEncuadre != null) {
      return;
    }
    final porAncho = limites.maxWidth / imagenAncho;
    final porAlto = limites.maxHeight / imagenAlto;
    _escalaEncuadre = porAncho < porAlto ? porAncho : porAlto;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _restablecer();
      }
    });
  }

  void _restablecer() {
    final escala = _escalaEncuadre ?? 1;
    _transformacion.value = Matrix4.diagonal3Values(escala, escala, 1);
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
    final conVenta = [for (final punto in puntosCampus) if (_abiertosEn(punto.codigo) > 0) punto];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mapa del plantel', style: tema.textTheme.headlineSmall),
              const SizedBox(height: Espacio.xs),
              Text(
                'Toca un edificio o su nombre en la leyenda para ver quién vende ahí. '
                'Los recuadros rojos tienen vendedores abiertos.',
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
        if (conVenta.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Espacio.l),
              children: [
                for (final punto in conVenta)
                  Padding(
                    padding: const EdgeInsets.only(right: Espacio.s),
                    child: ActionChip(
                      avatar: CircleAvatar(
                        backgroundColor: ColoresLiebre.primario,
                        child: Text('${_abiertosEn(punto.codigo)}',
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(punto.titulo, overflow: TextOverflow.ellipsis),
                      ),
                      onPressed: () => _abrir(punto),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
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
                          width: imagenAncho.toDouble(),
                          height: imagenAlto.toDouble(),
                          child: Stack(
                            children: [
                              Image.asset(
                                'assets/mapa_plantel.jpg',
                                width: imagenAncho.toDouble(),
                                height: imagenAlto.toDouble(),
                                fit: BoxFit.fill,
                                semanticLabel: 'Plano del plantel del ITCJ',
                              ),
                              for (final punto in puntosCampus) ...[
                                for (final zona in punto.plano) _zona(zona, punto, enDibujo: true),
                                _zona(punto.leyenda, punto, enDibujo: false),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_cargando) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
                Positioned(
                  right: Espacio.m,
                  bottom: Espacio.m,
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
            ),
          ),
        ),
      ],
    );
  }

  Widget _zona(RectPlano zona, PuntoCampus punto, {required bool enDibujo}) {
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
                color: cantidad > 0 && enDibujo ? ColoresLiebre.primario.withValues(alpha: 0.15) : null,
                border: cantidad > 0 && enDibujo ? Border.all(color: ColoresLiebre.primario, width: 2) : null,
              ),
              child: cantidad == 0
                  ? null
                  : Align(
                      alignment: enDibujo ? Alignment.topRight : Alignment.centerLeft,
                      child: enDibujo
                          ? CircleAvatar(
                              radius: 9,
                              backgroundColor: ColoresLiebre.primario,
                              child: Text('$cantidad', style: const TextStyle(color: Colors.white, fontSize: 10)),
                            )
                          : Container(width: 6, height: zona.alto.toDouble(), color: ColoresLiebre.primario),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
