import 'package:flutter/material.dart';

import '../servicios/estado.dart';
import '../tema/iconos_menu.dart';
import '../widgets/comunes.dart';
import 'busqueda_pantalla.dart';
import 'inicio_pantalla.dart';
import 'mapa_pantalla.dart';
import 'perfil_pantalla.dart';
import 'sesion_dialogo.dart';

/// Marco con barra superior y navegación que se adapta al ancho.
///
/// Debajo de 840 px usa barra inferior; arriba, un riel lateral. Cada
/// pestaña se construye la primera vez que se visita y después se
/// conserva (texto buscado, zoom del mapa, posición de scroll).
class MarcoPrincipal extends StatefulWidget {
  /// Recibe el estado ya restaurado.
  const MarcoPrincipal({super.key, required this.estado});

  /// Sesión compartida por todas las pestañas.
  final EstadoApp estado;

  @override
  State<MarcoPrincipal> createState() => _MarcoPrincipalState();
}

class _MarcoPrincipalState extends State<MarcoPrincipal> {
  static const int _pestanaPerfil = 3;

  int _indice = 0;
  final Set<int> _visitadas = {0};

  void _ir(int indice) {
    setState(() {
      _indice = indice;
      _visitadas.add(indice);
    });
  }

  List<_Destino> get _destinos {
    final menu = widget.estado.apariencia;
    return [
      _Destino(menu.iconoInicio, menu.menuInicio),
      _Destino(menu.iconoBusqueda, menu.menuBusqueda),
      _Destino(menu.iconoMapa, menu.menuMapa),
      _Destino(menu.iconoPerfil, menu.menuPerfil),
    ];
  }

  Widget _pestana(int indice) {
    final estado = widget.estado;
    switch (indice) {
      case 1:
        return BusquedaPantalla(estado: estado);
      case 2:
        return MapaPantalla(estado: estado);
      case 3:
        return PerfilPantalla(estado: estado);
      default:
        return InicioPantalla(estado: estado, alBuscar: () => _ir(1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final amplio = MediaQuery.sizeOf(context).width >= 840;
    final cuerpo = IndexedStack(
      index: _indice,
      children: [
        for (var i = 0; i < _destinos.length; i++)
          _visitadas.contains(i) ? _pestana(i) : const SizedBox.shrink(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: _Marca(estado: widget.estado),
        actions: [
          IconButton(
            tooltip: Theme.of(context).brightness == Brightness.dark ? 'Modo claro' : 'Modo oscuro',
            onPressed: () => widget.estado.alternarTema(Theme.of(context).brightness),
            icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
          ),
          _BotonCuenta(estado: widget.estado, alAbrirPerfil: () => _ir(_pestanaPerfil)),
          const SizedBox(width: 8),
        ],
      ),
      body: amplio
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _indice,
                  onDestinationSelected: _ir,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destino in _destinos)
                      NavigationRailDestination(
                        icon: Icon(iconoMenu(destino.icono)),
                        selectedIcon: Icon(iconoMenu(destino.icono, activo: true)),
                        label: Text(destino.etiqueta),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: AnchoLimitado(child: cuerpo)),
              ],
            )
          : cuerpo,
      bottomNavigationBar: amplio
          ? null
          : NavigationBar(
              selectedIndex: _indice,
              onDestinationSelected: _ir,
              destinations: [
                for (final destino in _destinos)
                  NavigationDestination(
                    icon: Icon(iconoMenu(destino.icono)),
                    selectedIcon: Icon(iconoMenu(destino.icono, activo: true)),
                    label: destino.etiqueta,
                  ),
              ],
            ),
    );
  }
}

/// Logo (si el admin subió uno) y título de la app.
class _Marca extends StatelessWidget {
  const _Marca({required this.estado});

  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    final menu = estado.apariencia;
    final imagen = menu.logoUrl.isNotEmpty ? menu.logoUrl : menu.iconoUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sin logo del administrador se usa el icono de la app.
        if (imagen.isNotEmpty)
          ImagenRed(imagen, alto: 32, ancho: 32, radio: 8, respaldo: const LogoLiebre(lado: 32))
        else
          const LogoLiebre(lado: 32),
        const SizedBox(width: 10),
        Flexible(child: Text(menu.titulo, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// "Entrar" para invitados; avatar con el nombre para cuentas activas.
class _BotonCuenta extends StatelessWidget {
  const _BotonCuenta({required this.estado, required this.alAbrirPerfil});

  final EstadoApp estado;
  final VoidCallback alAbrirPerfil;

  @override
  Widget build(BuildContext context) {
    final usuario = estado.usuario;
    if (usuario == null) {
      return TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: () => mostrarDialogoSesion(context, estado),
        icon: const Icon(Icons.login),
        label: const Text('Entrar'),
      );
    }
    return Tooltip(
      message: 'Mi perfil',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: alAbrirPerfil,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: Colors.white,
                child: Text(usuario.inicial, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
              ),
              if (MediaQuery.sizeOf(context).width >= 480) ...[
                const SizedBox(width: 8),
                Text(usuario.nombre, style: const TextStyle(color: Colors.white)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Destino {
  const _Destino(this.icono, this.etiqueta);

  /// Clave de [iconoMenu].
  final String icono;
  final String etiqueta;
}
