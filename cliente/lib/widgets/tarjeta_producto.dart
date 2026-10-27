import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../tema/tema_liebre.dart';
import 'comunes.dart';

/// Foto cuadrada del producto, o un icono si no tiene.
class MiniaturaProducto extends StatelessWidget {
  /// [lado] en píxeles lógicos.
  const MiniaturaProducto({super.key, required this.producto, this.lado = 56});

  /// Producto del que se toma `fotoUrl`.
  final Producto producto;

  /// Ancho y alto.
  final double lado;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final sinFoto = Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(color: esquema.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Icon(Icons.image_outlined, color: esquema.onSurfaceVariant, size: lado * 0.45),
    );
    final foto = producto.fotoUrl;
    if (foto == null || foto.isEmpty) {
      return sinFoto;
    }
    return ImagenRed(foto, alto: lado, ancho: lado, radio: 10, respaldo: sinFoto);
  }
}

/// Fila de catálogo: foto, nombre, precio, estrellas y si está agotado.
class TarjetaProducto extends StatelessWidget {
  /// [subtitulo] reemplaza la descripción, por ejemplo con el número de ventas.
  const TarjetaProducto({super.key, required this.producto, this.alTocar, this.subtitulo});

  /// Producto a mostrar.
  final Producto producto;

  /// Acción al tocar.
  final VoidCallback? alTocar;

  /// Texto bajo el nombre.
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final detalle = subtitulo ?? producto.descripcion;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.all(Espacio.m),
          child: Row(
            children: [
              MiniaturaProducto(producto: producto, lado: 64),
              const SizedBox(width: Espacio.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.titleSmall?.copyWith(
                        color: producto.agotado ? tema.colorScheme.onSurfaceVariant : null,
                        decoration: producto.agotado ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if ((detalle ?? '').isNotEmpty)
                      Text(
                        detalle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tema.colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    const SizedBox(height: Espacio.xs),
                    Estrellas(promedio: producto.promedioEstrellas, total: producto.totalResenas, tamano: 14),
                  ],
                ),
              ),
              const SizedBox(width: Espacio.s),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${producto.precio.toStringAsFixed(2)}',
                    style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.primary),
                  ),
                  if (producto.agotado)
                    Text('Agotado', style: TextStyle(color: tema.colorScheme.error, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
