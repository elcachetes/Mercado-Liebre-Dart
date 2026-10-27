import 'package:flutter/material.dart';

import '../mapa/puntos_campus.dart';
import '../modelos/modelos.dart';
import '../tema/tema_liebre.dart';
import 'comunes.dart';

/// Icono Material de una categoría de negocio.
IconData iconoCategoria(String categoria) {
  switch (categoria) {
    case 'comida':
      return Icons.restaurant;
    case 'servicio':
      return Icons.handyman_outlined;
    default:
      return Icons.shopping_bag_outlined;
  }
}

/// Texto de ubicación: "Edificio Z · Nodo de Creatividad…", o null sin punto.
String? ubicacionDe(Vendedor vendedor) {
  final punto = puntoPorCodigo(vendedor.edificio);
  if (punto != null) {
    return 'Edificio ${punto.codigo} · ${punto.nombre}';
  }
  return vendedor.edificio == null ? null : 'Edificio ${vendedor.edificio}';
}

/// Ficha de un negocio: avatar, ubicación, horario y si está abierto.
class TarjetaVendedor extends StatelessWidget {
  /// [alTocar] abre el detalle. Si es null, la tarjeta no es un botón.
  const TarjetaVendedor({super.key, required this.vendedor, this.alTocar, this.compacta = false, this.favorito = false});

  /// Negocio a mostrar.
  final Vendedor vendedor;

  /// Acción al pulsar la tarjeta.
  final VoidCallback? alTocar;

  /// Oculta la descripción y el horario, para carruseles de altura fija.
  final bool compacta;

  /// Muestra un corazón junto al nombre.
  final bool favorito;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final secundario = TextStyle(color: tema.colorScheme.onSurfaceVariant, fontSize: 13);
    final ubicacion = ubicacionDe(vendedor);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: ColoresLiebre.primario,
                    child: Icon(iconoCategoria(vendedor.categoria), color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: Espacio.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendedor.nombreNegocio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleMedium,
                        ),
                        Text(vendedor.subtipo ?? vendedor.categoriaEtiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
                      ],
                    ),
                  ),
                  if (favorito) Icon(Icons.favorite, size: 18, color: tema.colorScheme.primary),
                  if (vendedor.destacado)
                    const Tooltip(
                      message: 'Destacado',
                      child: Icon(Icons.workspace_premium, color: ColoresLiebre.estrella),
                    ),
                ],
              ),
              if (!compacta && (vendedor.descripcion ?? '').isNotEmpty) ...[
                const SizedBox(height: Espacio.s),
                Text(vendedor.descripcion!, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: Espacio.s),
              if (ubicacion != null)
                _Linea(icono: Icons.place_outlined, texto: ubicacion, estilo: secundario),
              if (!compacta) _Linea(icono: Icons.schedule, texto: vendedor.horarioTexto, estilo: secundario),
              const SizedBox(height: Espacio.s),
              Row(
                children: [
                  EstadoAbierto(abierto: vendedor.disponible),
                  const Spacer(),
                  if (vendedor.totalResenas > 0)
                    Estrellas(promedio: vendedor.promedioEstrellas, total: vendedor.totalResenas, tamano: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Píldora verde "Abierto ahora" o gris "Cerrado".
class EstadoAbierto extends StatelessWidget {
  /// [abierto] decide el color y el texto.
  const EstadoAbierto({super.key, required this.abierto});

  /// Si el negocio atiende en este momento.
  final bool abierto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = abierto ? ColoresLiebre.abierto(tema.brightness) : tema.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            abierto ? 'Abierto ahora' : 'Cerrado',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.icono, required this.texto, required this.estilo});

  final IconData icono;
  final String texto;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icono, size: 14, color: estilo.color),
          const SizedBox(width: 6),
          Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo)),
        ],
      ),
    );
  }
}
