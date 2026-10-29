import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import 'comun_admin.dart';

/// Últimas 100 reseñas de toda la app, para borrar las ofensivas o falsas.
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

  @override
  Widget build(BuildContext context) {
    final api = widget.estado.api;
    return CargaAdmin<List<ResenaAdmin>>(
      cargar: api.resenasAdmin,
      construir: (context, resenas, recargar) {
        final esquema = Theme.of(context).colorScheme;
        final visibles = resenas
            .where((r) =>
                _filtro.isEmpty ||
                '${r.producto} ${r.nombreNegocio} ${r.autor} ${r.correo} ${r.comentario ?? ''}'.toLowerCase().contains(_filtro))
            .toList();
        return [
          BuscadorAdmin(pista: 'Producto, negocio, autor o texto', alCambiar: (texto) => setState(() => _filtro = texto)),
          if (visibles.isEmpty) const EstadoVacio(icono: Icons.reviews_outlined, mensaje: 'No hay reseñas que mostrar.'),
          for (final resena in visibles)
            Card(
              child: ListTile(
                title: Text('${resena.producto} · ${resena.nombreNegocio}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Espacio.xs),
                    Estrellas(promedio: resena.estrellas.toDouble()),
                    if ((resena.comentario ?? '').isNotEmpty) ...[
                      const SizedBox(height: Espacio.xs),
                      Text(resena.comentario!),
                    ],
                    const SizedBox(height: Espacio.xs),
                    Text('${resena.autor} (${resena.correo}) · ${fechaCorta(resena.creadoEn)}',
                        style: TextStyle(color: esquema.onSurfaceVariant)),
                  ],
                ),
                trailing: IconButton(
                  tooltip: 'Eliminar reseña',
                  icon: Icon(Icons.delete_outline, color: esquema.error),
                  onPressed: () async {
                    if (!await confirmar(
                      context,
                      titulo: 'Eliminar reseña',
                      mensaje: 'Se borrará la reseña de ${resena.autor} sobre "${resena.producto}".',
                    )) {
                      return;
                    }
                    if (context.mounted &&
                        await intentar(context, () => api.eliminarResena(resena.productoId, resena.autorId),
                            exito: 'Reseña eliminada.')) {
                      await recargar();
                    }
                  },
                ),
              ),
            ),
        ];
      },
    );
  }
}
