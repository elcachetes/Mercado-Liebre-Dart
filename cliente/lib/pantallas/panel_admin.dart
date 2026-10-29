import 'package:flutter/material.dart';

import '../servicios/estado.dart';
import 'admin/admin_apariencia.dart';
import 'admin/admin_avisos.dart';
import 'admin/admin_base_datos.dart';
import 'admin/admin_contrasenas.dart';
import 'admin/admin_mapa.dart';
import 'admin/admin_publicidad.dart';
import 'admin/admin_resenas.dart';
import 'admin/admin_resumen.dart';
import 'admin/admin_usuarios.dart';
import 'admin/admin_vendedores.dart';

/// Una pestaña del panel de administración: (título, icono, contenido).
typedef PestanaAdmin = (String, IconData, Widget Function(EstadoApp estado));

/// Panel del administrador: una página completa con una pestaña por tema.
///
/// Cada pestaña vive en `pantallas/admin/` y carga sus datos al abrirse.
/// Para agregar una: crea el widget en esa carpeta (usa `CargaAdmin` de
/// `admin/comun_admin.dart`), agrégalo a [pestanas] y, si necesita rutas
/// nuevas, sigue la receta "Agregar un endpoint" de AGENTS.md.
///
/// El servidor exige el rol `admin` en todas las rutas `/api/admin/...`;
/// esconder el menú en la app no es la protección.
class PanelAdmin extends StatelessWidget {
  /// [estado] debe tener una sesión de administrador.
  const PanelAdmin({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  /// Pestañas en el orden en que aparecen.
  static final List<PestanaAdmin> pestanas = [
    ('Resumen', Icons.dashboard_outlined, (estado) => AdminResumen(estado: estado)),
    ('Usuarios', Icons.people_outline, (estado) => AdminUsuarios(estado: estado)),
    ('Negocios', Icons.storefront_outlined, (estado) => AdminVendedores(estado: estado)),
    ('Mapa', Icons.map_outlined, (estado) => AdminMapa(estado: estado)),
    ('Publicidad', Icons.view_carousel_outlined, (estado) => AdminPublicidad(estado: estado)),
    ('Avisos', Icons.campaign_outlined, (estado) => AdminAvisos(estado: estado)),
    ('Reseñas', Icons.reviews_outlined, (estado) => AdminResenas(estado: estado)),
    ('Contraseñas', Icons.key_outlined, (estado) => AdminContrasenas(estado: estado)),
    ('Base de datos', Icons.storage_outlined, (estado) => AdminBaseDatos(estado: estado)),
    ('Apariencia', Icons.palette_outlined, (estado) => AdminApariencia(estado: estado)),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: pestanas.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // La barra es roja: texto e indicador en blanco.
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            dividerColor: Colors.transparent,
            tabs: [for (final (titulo, icono, _) in pestanas) Tab(icon: Icon(icono), text: titulo)],
          ),
        ),
        body: TabBarView(
          children: [for (final (_, _, construir) in pestanas) construir(estado)],
        ),
      ),
    );
  }
}
