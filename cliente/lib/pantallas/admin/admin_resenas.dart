import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import 'comun_admin.dart';

/// Reseñas de toda la app: aprobar las de vendedores y borrar las ofensivas o falsas.
///
/// Las reseñas que escribe un vendedor llegan pendientes y no se publican
/// hasta aprobarlas aquí (evita opiniones de la competencia). Van primero.
class AdminResenas extends StatefulWidget {
  /// Sesión de administrador.
  const AdminResenas({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  @override
  State<AdminResenas> createState() => _AdminResenasState();
}

class _AdminResenasState extends State<AdminResenas> {
  String _filtro = '';
  bool _soloPendientes = false;

  @override
  Widget build(BuildContext context) {
    final api = widget.estado.api;
    return CargaAdmin<List<ResenaAdmin>>(
      cargar: api.resenasAdmin,
      construir: (context, resenas, recargar) {
        final esquema = Theme.of(context).colorScheme;
        final pendientes = resenas.where((r) => !r.aprobada).length;
        final visibles = resenas
            .where((r) => !_soloPendientes || !r.aprobada)
            .where((r) =>
                _filtro.isEmpty ||
                '${r.producto} ${r.nombreNegocio} ${r.autor} ${r.correo} ${r.negocioAutor ?? ''} ${r.comentario ?? ''}'
                    .toLowerCase()
                    .contains(_filtro))
            .toList();

        Future<void> aprobar(ResenaAdmin resena) async {
          if (await intentar(context, () => api.aprobarResena(resena.productoId, resena.autorId),
              exito: 'Reseña aprobada y publicada.')) {
            await recargar();
          }
        }

        Future<void> eliminar(ResenaAdmin resena) async {
          final pendiente = !resena.aprobada;
          if (!await confirmar(
            context,
            titulo: pendiente ? 'Rechazar reseña' : 'Eliminar reseña',
            mensaje: 'Se borrará la reseña de ${resena.autor} sobre "${resena.producto}".',
            accion: pendiente ? 'Rechazar' : 'Eliminar',
          )) {
            return;
          }
          if (context.mounted &&
              await intentar(context, () => api.eliminarResena(resena.productoId, resena.autorId),
                  exito: pendiente ? 'Reseña rechazada.' : 'Reseña eliminada.')) {
            await recargar();
          }
        }

        return [
          BuscadorAdmin(pista: 'Producto, negocio, autor o texto', alCambiar: (texto) => setState(() => _filtro = texto)),
          Padding(
            padding: const EdgeInsets.only(bottom: Espacio.s),
            child: Wrap(
              spacing: Espacio.s,
              children: [
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: !_soloPendientes,
                  onSelected: (_) => setState(() => _soloPendientes = false),
                ),
                ChoiceChip(
                  label: Text('Por aprobar ($pendientes)'),
                  selected: _soloPendientes,
                  onSelected: (_) => setState(() => _soloPendientes = true),
                ),
              ],
            ),
          ),
          if (visibles.isEmpty)
            EstadoVacio(
              icono: Icons.reviews_outlined,
              mensaje: _soloPendientes ? 'No hay reseñas por aprobar.' : 'No hay reseñas que mostrar.',
            ),
          for (final resena in visibles)
            Card(
              color: resena.aprobada ? null : esquema.tertiaryContainer,
              child: ListTile(
                title: Text('${resena.producto} · ${resena.nombreNegocio}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!resena.aprobada) ...[
                      const SizedBox(height: Espacio.xs),
                      Etiqueta('Por aprobar', color: esquema.tertiary),
                    ],
                    const SizedBox(height: Espacio.xs),
                    Estrellas(promedio: resena.estrellas.toDouble()),
                    if ((resena.comentario ?? '').isNotEmpty) ...[
                      const SizedBox(height: Espacio.xs),
                      Text(resena.comentario!),
                    ],
                    const SizedBox(height: Espacio.xs),
                    Text(
                      [
                        '${resena.autor} (${resena.correo})',
                        if ((resena.negocioAutor ?? '').isNotEmpty) 'Negocio: ${resena.negocioAutor}',
                        fechaCorta(resena.creadoEn),
                      ].join(' · '),
                      style: TextStyle(color: esquema.onSurfaceVariant),
                    ),
                  ],
                ),
                trailing: Wrap(
                  children: [
                    if (!resena.aprobada)
                      IconButton(
                        tooltip: 'Aprobar y publicar',
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: () => aprobar(resena),
                      ),
                    IconButton(
                      tooltip: resena.aprobada ? 'Eliminar reseña' : 'Rechazar reseña',
                      icon: Icon(resena.aprobada ? Icons.delete_outline : Icons.block, color: esquema.error),
                      onPressed: () => eliminar(resena),
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
    );
  }
}
