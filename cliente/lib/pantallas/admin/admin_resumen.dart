import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import 'comun_admin.dart';

/// Tablero: cuántos registros hay de cada cosa y qué necesita atención.
///
/// Las claves vienen de `GET /api/admin/resumen` (`Repositorio.resumen`).
class AdminResumen extends StatelessWidget {
  /// Sesión de administrador.
  const AdminResumen({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  /// (clave del resumen, etiqueta, icono). El orden es el de la cuadrícula.
  static const List<(String, String, IconData)> _totales = [
    ('usuarios', 'Cuentas', Icons.people_outline),
    ('vendedores', 'Negocios', Icons.storefront_outlined),
    ('abiertos', 'Abiertos ahora', Icons.store),
    ('productos', 'Productos', Icons.inventory_2_outlined),
    ('calificaciones', 'Reseñas', Icons.star_outline),
    ('favoritos', 'Favoritos', Icons.favorite_outline),
    ('avisosActivos', 'Avisos activos', Icons.campaign_outlined),
  ];

  /// Lo que conviene revisar: (clave, etiqueta, icono).
  static const List<(String, String, IconData)> _pendientes = [
    ('resenasPendientes', 'Reseñas de vendedores por aprobar', Icons.rate_review_outlined),
    ('sinVerificar', 'Cuentas sin verificar el correo', Icons.mark_email_unread_outlined),
    ('bloqueados', 'Cuentas bloqueadas', Icons.block),
    ('sinPunto', 'Negocios sin punto en el mapa', Icons.wrong_location_outlined),
    ('restablecimientosPendientes', 'Enlaces de contraseña pendientes', Icons.key_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return CargaAdmin<Map<String, dynamic>>(
      cargar: estado.api.resumenAdmin,
      construir: (context, datos, _) {
        int numero(String clave) => (datos[clave] as num?)?.toInt() ?? 0;
        final tema = Theme.of(context);
        return [
          Wrap(
            spacing: Espacio.m,
            runSpacing: Espacio.m,
            children: [
              for (final (clave, etiqueta, icono) in _totales) _Cifra(icono: icono, valor: '${numero(clave)}', etiqueta: etiqueta),
              _Cifra(
                icono: Icons.view_carousel_outlined,
                valor: '${numero('anuncios')}/${Anuncio.secciones * Anuncio.porSeccion}',
                etiqueta: 'Anuncios',
              ),
            ],
          ),
          const TituloSeccion('Cuentas por rol', icono: Icons.badge_outlined),
          Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.s,
            children: [
              Chip(label: Text('${numero('compradores')} compradores')),
              Chip(label: Text('${numero('cuentasVendedor')} vendedores')),
              Chip(label: Text('${numero('moderadores')} moderadores')),
              Chip(label: Text('${numero('administradores')} administradores')),
            ],
          ),
          const TituloSeccion('Para revisar', icono: Icons.checklist),
          Card(
            child: Column(
              children: [
                for (final (clave, etiqueta, icono) in _pendientes)
                  ListTile(
                    leading: Icon(icono, color: numero(clave) > 0 ? tema.colorScheme.error : null),
                    title: Text(etiqueta),
                    trailing: Text('${numero(clave)}', style: tema.textTheme.titleMedium),
                  ),
              ],
            ),
          ),
        ];
      },
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.icono, required this.valor, required this.etiqueta});

  final IconData icono;
  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: tema.colorScheme.primary),
              const SizedBox(height: Espacio.s),
              Text(valor, style: tema.textTheme.headlineSmall),
              Text(etiqueta, style: TextStyle(color: tema.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
