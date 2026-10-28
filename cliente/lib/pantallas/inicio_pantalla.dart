import 'dart:async';

import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/tarjeta_producto.dart';
import '../widgets/tarjeta_vendedor.dart';
import 'detalle_producto.dart';
import 'detalle_vendedor.dart';

/// Inicio: avisos, destacados, vendedores abiertos y más vendidos.
class InicioPantalla extends StatefulWidget {
  /// [alBuscar] lleva a la pestaña de búsqueda.
  const InicioPantalla({super.key, required this.estado, required this.alBuscar});

  /// Sesión y cliente HTTP.
  final EstadoApp estado;

  /// Cambia a la pestaña de búsqueda.
  final VoidCallback alBuscar;

  @override
  State<InicioPantalla> createState() => _InicioPantallaState();
}

class _InicioPantallaState extends State<InicioPantalla> {
  List<Vendedor> _activos = [];
  List<Vendedor> _destacados = [];
  List<Producto> _vendidos = [];
  List<Aviso> _avisos = [];
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _activos.isEmpty;
      _error = null;
    });
    final api = widget.estado.api;
    try {
      // Las cuatro peticiones van en paralelo.
      final (activos, destacados, vendidos, avisos) = await (
        api.vendedores(soloDisponibles: true),
        api.destacados(),
        api.masVendidos(),
        api.avisos(),
      ).wait;
      if (!mounted) {
        return;
      }
      setState(() {
        _activos = activos;
        _destacados = destacados;
        _vendidos = vendidos;
        _avisos = avisos;
        _cargando = false;
      });
    } on ParallelWaitError<dynamic, dynamic> catch (error) {
      if (!mounted) {
        return;
      }
      final primero = [error.errors.$1, error.errors.$2, error.errors.$3, error.errors.$4]
          .whereType<AsyncError>()
          .map((fallo) => fallo.error)
          .firstOrNull;
      setState(() {
        _error = primero is ErrorApi ? primero.mensaje : 'No se pudo cargar el inicio.';
        _cargando = false;
      });
    }
  }

  void _abrirVendedor(Vendedor vendedor) => abrirVendedor(context, widget.estado, vendedor);

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EstadoVacio.error(mensaje: _error!, alReintentar: _cargar);
    }
    final tema = Theme.of(context);
    final usuario = widget.estado.usuario;
    final portada = widget.estado.apariencia.fotoPortadaUrl;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xl),
        children: [
          Text(usuario == null ? '¿Qué se te antoja hoy?' : 'Hola, ${usuario.nombre}', style: tema.textTheme.headlineSmall),
          const SizedBox(height: Espacio.xs),
          Text(
            usuario == null
                ? 'Explora los puestos del plantel sin cuenta. Entra solo para calificar o guardar favoritos.'
                : 'Esto es lo que hay en el plantel ahora mismo.',
            style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Espacio.l),
          _AtajoBusqueda(alTocar: widget.alBuscar),
          if (portada.isNotEmpty) ...[
            const SizedBox(height: Espacio.l),
            ImagenRed(portada, alto: 180, ancho: double.infinity, radio: 16),
          ],
          for (final aviso in _avisos) ...[
            const SizedBox(height: Espacio.m),
            _TarjetaAviso(aviso: aviso),
          ],
          if (_destacados.isNotEmpty) ...[
            const TituloSeccion('Destacados', icono: Icons.workspace_premium_outlined),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _destacados.length,
                separatorBuilder: (_, __) => const SizedBox(width: Espacio.m),
                itemBuilder: (context, indice) {
                  final vendedor = _destacados[indice];
                  return SizedBox(
                    width: 270,
                    child: TarjetaVendedor(
                      vendedor: vendedor,
                      compacta: true,
                      favorito: widget.estado.esFavorito(vendedor.id),
                      alTocar: () => _abrirVendedor(vendedor),
                    ),
                  );
                },
              ),
            ),
          ],
          TituloSeccion(
            'Abiertos ahora',
            icono: Icons.storefront_outlined,
            accion: _activos.isEmpty ? null : Text('${_activos.length}', style: tema.textTheme.labelLarge),
          ),
          if (_activos.isEmpty)
            const EstadoVacio(
              icono: Icons.nightlight_outlined,
              mensaje: 'No hay vendedores abiertos en este momento.',
              detalle: 'Desliza hacia abajo para actualizar más tarde.',
            )
          else
            for (final vendedor in _activos)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacio.m),
                child: TarjetaVendedor(
                  vendedor: vendedor,
                  favorito: widget.estado.esFavorito(vendedor.id),
                  alTocar: () => _abrirVendedor(vendedor),
                ),
              ),
          if (_vendidos.isNotEmpty) ...[
            const TituloSeccion('Más vendidos', icono: Icons.local_fire_department_outlined),
            for (final producto in _vendidos)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacio.s),
                child: TarjetaProducto(
                  producto: producto,
                  subtitulo: '${producto.vecesVendido} ventas',
                  alTocar: () => abrirProducto(context, widget.estado, producto),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Campo de búsqueda falso: al tocarlo cambia a la pestaña de búsqueda.
class _AtajoBusqueda extends StatelessWidget {
  const _AtajoBusqueda({required this.alTocar});

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Buscar comida, productos o servicios',
      child: Material(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: esquema.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espacio.l, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search, color: esquema.onSurfaceVariant),
                const SizedBox(width: Espacio.m),
                Expanded(
                  child: Text(
                    'Buscar comida, productos o servicios',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: esquema.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaAviso extends StatelessWidget {
  const _TarjetaAviso({required this.aviso});

  final Aviso aviso;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Card(
      color: esquema.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.campaign_outlined, color: esquema.onPrimaryContainer),
            const SizedBox(width: Espacio.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(aviso.titulo, style: TextStyle(fontWeight: FontWeight.w700, color: esquema.onPrimaryContainer)),
                  const SizedBox(height: Espacio.xs),
                  Text(aviso.contenido, style: TextStyle(color: esquema.onPrimaryContainer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
