import 'dart:async';

import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/publicidad.dart';
import '../widgets/tarjeta_producto.dart';
import '../widgets/tarjeta_vendedor.dart';
import 'detalle_producto.dart';
import 'detalle_vendedor.dart';

/// Criterios de orden de los resultados.
enum OrdenBusqueda {
  /// Coincidencias exactas y destacados primero (orden del servidor).
  relevancia('Relevancia', Icons.auto_awesome_outlined),

  /// Alfabético por nombre del negocio, ignorando acentos.
  nombre('Nombre (A–Z)', Icons.sort_by_alpha),

  /// Promedio de estrellas, de mayor a menor.
  masEstrellas('Más estrellas', Icons.star_rounded),

  /// Promedio de estrellas, de menor a mayor.
  menosEstrellas('Menos estrellas', Icons.star_outline_rounded),

  /// Número de reseñas, de mayor a menor.
  masResenas('Más reseñas', Icons.forum),

  /// Número de reseñas, de menor a mayor.
  menosResenas('Menos reseñas', Icons.forum_outlined);

  const OrdenBusqueda(this.etiqueta, this.icono);

  /// Texto del menú.
  final String etiqueta;

  /// Icono del menú.
  final IconData icono;
}

/// Ordena [resultados] según [orden] sin modificar la lista original.
///
/// Al ordenar por estrellas, quien no tiene reseñas va siempre al final
/// (no es "el peor calificado", simplemente no tiene calificación).
/// Los empates se resuelven por nombre y luego por el orden original.
List<ResultadoBusqueda> ordenarResultados(List<ResultadoBusqueda> resultados, OrdenBusqueda orden) {
  if (orden == OrdenBusqueda.relevancia) {
    return resultados;
  }
  String clave(ResultadoBusqueda r) => _normalizar(r.vendedor.nombreNegocio);
  int criterio(ResultadoBusqueda a, ResultadoBusqueda b) {
    final va = a.vendedor;
    final vb = b.vendedor;
    switch (orden) {
      case OrdenBusqueda.masEstrellas || OrdenBusqueda.menosEstrellas:
        final sinA = va.totalResenas == 0;
        final sinB = vb.totalResenas == 0;
        if (sinA != sinB) {
          return sinA ? 1 : -1;
        }
        final porEstrellas = orden == OrdenBusqueda.masEstrellas
            ? vb.promedioEstrellas.compareTo(va.promedioEstrellas)
            : va.promedioEstrellas.compareTo(vb.promedioEstrellas);
        return porEstrellas != 0 ? porEstrellas : vb.totalResenas.compareTo(va.totalResenas);
      case OrdenBusqueda.masResenas:
        return vb.totalResenas.compareTo(va.totalResenas);
      case OrdenBusqueda.menosResenas:
        return va.totalResenas.compareTo(vb.totalResenas);
      case OrdenBusqueda.nombre || OrdenBusqueda.relevancia:
        return 0;
    }
  }

  final indexados = [for (var i = 0; i < resultados.length; i++) (i, resultados[i])];
  indexados.sort((a, b) {
    final primero = criterio(a.$2, b.$2);
    if (primero != 0) {
      return primero;
    }
    final porNombre = clave(a.$2).compareTo(clave(b.$2));
    return porNombre != 0 ? porNombre : a.$1.compareTo(b.$1);
  });
  return [for (final (_, resultado) in indexados) resultado];
}

String _normalizar(String texto) {
  const acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n~'};
  return texto.toLowerCase().split('').map((c) => acentos[c] ?? c).join();
}

/// Búsqueda y exploración por categoría.
///
/// En pantallas sin barra lateral de publicidad intercala [AnunciosEnLista]
/// entre los resultados (ver [intercalarAnuncios]).
///
/// Sin texto lista todo lo de la categoría elegida (por defecto, solo lo
/// abierto ahora). Con texto espera [_pausa] tras la última tecla antes de
/// pedir a la API y descarta respuestas de búsquedas anteriores.
class BusquedaPantalla extends StatefulWidget {
  /// [estado] aporta el cliente HTTP.
  const BusquedaPantalla({super.key, required this.estado});

  /// Sesión y cliente HTTP.
  final EstadoApp estado;

  @override
  State<BusquedaPantalla> createState() => _BusquedaPantallaState();
}

class _BusquedaPantallaState extends State<BusquedaPantalla> {
  static const Duration _pausa = Duration(milliseconds: 350);

  static const List<(String?, String)> _filtros = [
    (null, 'Todo'),
    ('comida', 'Comida'),
    ('producto', 'Productos'),
    ('servicio', 'Servicios'),
  ];

  final TextEditingController _campo = TextEditingController();
  Timer? _espera;
  int _peticion = 0;
  String? _categoria;
  bool _soloAbiertos = true;
  OrdenBusqueda _orden = OrdenBusqueda.relevancia;
  List<ResultadoBusqueda> _resultados = [];
  String? _error;
  bool _buscando = false;
  bool _listo = false;

  String get _termino => _campo.text.trim();

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _campo.dispose();
    super.dispose();
  }

  void _programar() {
    _espera?.cancel();
    _espera = Timer(_pausa, _buscar);
    setState(() {}); // Muestra u oculta el botón de borrar.
  }

  Future<void> _buscar() async {
    _espera?.cancel();
    final numero = ++_peticion;
    if (_termino.length == 1) {
      return; // Una sola letra: se espera a la siguiente.
    }
    setState(() => _buscando = true);
    try {
      final resultados = await widget.estado.api.buscar(
        _termino,
        categoria: _categoria,
        soloDisponibles: _soloAbiertos,
      );
      if (!mounted || numero != _peticion) {
        return;
      }
      setState(() {
        _resultados = resultados;
        _error = null;
      });
    } on ErrorApi catch (error) {
      if (mounted && numero == _peticion) {
        setState(() => _error = error.mensaje);
      }
    } finally {
      if (mounted && numero == _peticion) {
        setState(() {
          _buscando = false;
          _listo = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.s),
          child: TextField(
            controller: _campo,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tacos, café, impresiones, asesorías…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _campo.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _campo.clear();
                        _buscar();
                      },
                    ),
            ),
            onSubmitted: (_) => _buscar(),
            onChanged: (_) => _programar(),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Espacio.l),
          child: Row(
            children: [
              for (final (valor, etiqueta) in _filtros)
                Padding(
                  padding: const EdgeInsets.only(right: Espacio.s),
                  child: ChoiceChip(
                    label: Text(etiqueta),
                    avatar: valor == null ? null : Icon(iconoCategoria(valor), size: 18),
                    selected: _categoria == valor,
                    onSelected: (_) {
                      setState(() => _categoria = valor);
                      _buscar();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.xs, Espacio.s, 0),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Solo abiertos'),
                avatar: Icon(Icons.circle, size: 10, color: ColoresLiebre.abierto(Theme.of(context).brightness)),
                selected: _soloAbiertos,
                showCheckmark: false,
                onSelected: (valor) {
                  setState(() => _soloAbiertos = valor);
                  _buscar();
                },
              ),
              const SizedBox(width: Espacio.s),
              Expanded(
                child: Text(
                  _listo && _error == null ? '${_resultados.length} resultado${_resultados.length == 1 ? '' : 's'}' : '',
                  style: TextStyle(color: esquema.onSurfaceVariant, fontSize: 13),
                ),
              ),
              PopupMenuButton<OrdenBusqueda>(
                tooltip: 'Ordenar',
                initialValue: _orden,
                onSelected: (orden) => setState(() => _orden = orden),
                itemBuilder: (_) => [
                  for (final orden in OrdenBusqueda.values)
                    PopupMenuItem(
                      value: orden,
                      child: Row(children: [
                        Icon(orden.icono, size: 20),
                        const SizedBox(width: Espacio.m),
                        Text(orden.etiqueta),
                      ]),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.s),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_vert, size: 20, color: esquema.primary),
                      const SizedBox(width: Espacio.xs),
                      Text(_orden.etiqueta, style: TextStyle(color: esquema.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 3, child: _buscando ? const LinearProgressIndicator() : null),
        Expanded(child: _contenido()),
      ],
    );
  }

  Widget _contenido() {
    if (_error != null) {
      return EstadoVacio.error(mensaje: _error!, alReintentar: _buscar);
    }
    if (!_listo) {
      return const SizedBox.shrink();
    }
    if (_termino.length == 1) {
      return const EstadoVacio(icono: Icons.keyboard_outlined, mensaje: 'Escribe al menos 2 letras');
    }
    if (_resultados.isEmpty) {
      final deCategoria = _categoria == null
          ? ''
          : ' de ${_filtros.firstWhere((filtro) => filtro.$1 == _categoria).$2.toLowerCase()}';
      return EstadoVacio(
        icono: _termino.isEmpty ? Icons.storefront_outlined : Icons.search_off,
        mensaje: _termino.isEmpty
            ? (_soloAbiertos
                ? 'No hay vendedores$deCategoria abiertos en este momento'
                : 'Aún no hay vendedores$deCategoria registrados')
            : 'Sin resultados para "$_termino"',
        detalle: _soloAbiertos ? 'Quita el filtro "Solo abiertos" para ver también los cerrados.' : 'Prueba con otra palabra.',
      );
    }
    final ordenados = ordenarResultados(_resultados, _orden);
    // Sin barra lateral (celular), la publicidad va entre los resultados.
    final orden = MediaQuery.sizeOf(context).width < anchoBarraLateral
        ? intercalarAnuncios(ordenados.length)
        : [for (var i = 0; i < ordenados.length; i++) i];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.xl),
      itemCount: orden.length,
      itemBuilder: (context, posicion) {
        final indice = orden[posicion];
        if (indice == null) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Espacio.l),
            child: AnunciosEnLista(
              anuncios: widget.estado.anuncios,
              alAbrirVendedor: (vendedor) => abrirVendedor(context, widget.estado, vendedor),
            ),
          );
        }
        return _Resultado(resultado: ordenados[indice], estado: widget.estado);
      },
    );
  }
}

/// Un vendedor encontrado y hasta tres de sus productos.
class _Resultado extends StatelessWidget {
  const _Resultado({required this.resultado, required this.estado});

  final ResultadoBusqueda resultado;
  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    final vendedor = resultado.vendedor;
    final productos = resultado.productos.take(3).toList();
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (resultado.coincidenciaExacta)
            Padding(
              padding: const EdgeInsets.only(bottom: Espacio.xs, left: Espacio.xs),
              child: Text('Coincidencia exacta',
                  style: TextStyle(fontWeight: FontWeight.w700, color: esquema.primary, fontSize: 12)),
            ),
          TarjetaVendedor(
            vendedor: vendedor,
            favorito: estado.esFavorito(vendedor.id),
            alTocar: () => abrirVendedor(context, estado, vendedor),
          ),
          for (final producto in productos)
            Padding(
              padding: const EdgeInsets.only(left: Espacio.l, top: Espacio.xs),
              child: TarjetaProducto(producto: producto, alTocar: () => abrirProducto(context, estado, producto)),
            ),
          if (resultado.productos.length > productos.length)
            Padding(
              padding: const EdgeInsets.only(left: Espacio.l),
              child: TextButton(
                onPressed: () => abrirVendedor(context, estado, vendedor),
                child: Text('Ver ${resultado.productos.length - productos.length} más en el catálogo'),
              ),
            ),
        ],
      ),
    );
  }
}
