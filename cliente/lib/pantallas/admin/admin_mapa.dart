import 'package:flutter/material.dart';

import '../../mapa/puntos_campus.dart';
import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import 'comun_admin.dart';

/// Mapa: qué negocios hay en cada punto del plano y cuáles no tienen punto.
///
/// Los puntos (edificios y su dibujo) están fijos en el código
/// (`mapa/puntos_campus.dart` y `servidor/lib/plano.dart`); aquí solo se
/// asigna o se quita el punto de cada negocio.
class AdminMapa extends StatelessWidget {
  /// Sesión de administrador.
  const AdminMapa({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  Future<void> _mover(BuildContext context, Vendedor negocio, String codigo, Future<void> Function() recargar) async {
    final ok = await intentar(
      context,
      () => estado.api.actualizarVendedorAdmin(negocio.id, {'edificio': codigo}),
      exito: codigo.isEmpty ? 'Se quitó el punto de ${negocio.nombreNegocio}.' : '${negocio.nombreNegocio} ahora está en $codigo.',
    );
    if (ok) {
      await recargar();
    }
  }

  /// Pide un punto del plano. Devuelve su código o null si se canceló.
  Future<String?> _elegirPunto(BuildContext context, Vendedor negocio) {
    return showDialog<String>(
      context: context,
      builder: (contexto) => SimpleDialog(
        title: Text('¿Dónde vende ${negocio.nombreNegocio}?'),
        children: [
          for (final punto in puntosCampus)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(contexto, punto.codigo),
              child: Text('${punto.codigo} · ${punto.nombre}'),
            ),
        ],
      ),
    );
  }

  /// Pide uno de [negocios]. Devuelve null si se canceló.
  Future<Vendedor?> _elegirNegocio(BuildContext context, PuntoCampus punto, List<Vendedor> negocios) {
    return showDialog<Vendedor>(
      context: context,
      builder: (contexto) => SimpleDialog(
        title: Text('Agregar a ${punto.codigo} · ${punto.nombre}'),
        children: [
          for (final negocio in negocios)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(contexto, negocio),
              child: Text(negocio.edificio == null ? negocio.nombreNegocio : '${negocio.nombreNegocio} (ahora en ${negocio.edificio})'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CargaAdmin<List<Vendedor>>(
      cargar: estado.api.vendedores,
      construir: (context, negocios, recargar) {
        final esquema = Theme.of(context).colorScheme;
        final sinPunto = negocios.where((v) => puntoPorCodigo(v.edificio) == null).toList();
        return [
          Text(
            'Toca la X de un negocio para quitarlo de un punto, o "Agregar" para poner uno ahí. '
            'Los vendedores también pueden elegir su punto tocando el plano en la pestaña Mapa.',
            style: TextStyle(color: esquema.onSurfaceVariant),
          ),
          const TituloSeccion('Sin punto en el mapa', icono: Icons.wrong_location_outlined),
          if (sinPunto.isEmpty)
            const Text('Todos los negocios tienen punto.')
          else
            Wrap(
              spacing: Espacio.s,
              runSpacing: Espacio.s,
              children: [
                for (final negocio in sinPunto)
                  ActionChip(
                    avatar: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: Text(negocio.nombreNegocio),
                    onPressed: () async {
                      final codigo = await _elegirPunto(context, negocio);
                      if (codigo != null && context.mounted) {
                        await _mover(context, negocio, codigo, recargar);
                      }
                    },
                  ),
              ],
            ),
          const TituloSeccion('Puntos del plano', icono: Icons.map_outlined),
          for (final punto in puntosCampus)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(radius: 16, child: Text(punto.codigo, style: const TextStyle(fontSize: 12))),
                        const SizedBox(width: Espacio.s),
                        Expanded(child: Text(punto.nombre, style: Theme.of(context).textTheme.titleSmall)),
                        TextButton.icon(
                          onPressed: () async {
                            final otros = negocios.where((v) => v.edificio != punto.codigo).toList();
                            final elegido = await _elegirNegocio(context, punto, otros);
                            if (elegido != null && context.mounted) {
                              await _mover(context, elegido, punto.codigo, recargar);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: Espacio.s,
                      runSpacing: Espacio.xs,
                      children: [
                        for (final negocio in negocios.where((v) => v.edificio == punto.codigo))
                          InputChip(
                            label: Text(negocio.nombreNegocio),
                            onDeleted: () => _mover(context, negocio, '', recargar),
                            deleteButtonTooltipMessage: 'Quitar de ${punto.codigo}',
                          ),
                      ],
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
