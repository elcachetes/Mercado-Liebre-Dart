import 'package:flutter/material.dart';

import '../servicios/estado.dart';
import '../tema/iconos_menu.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/publicidad.dart';
import '../widgets/reporte_dialogo.dart';
import 'busqueda_pantalla.dart';
import 'inicio_pantalla.dart';
import 'mapa_pantalla.dart';
import 'perfil_pantalla.dart';
import 'sesion_dialogo.dart';

/// Marco con la barra superior roja, que lleva toda la navegación.
///
/// Desde 840 px de ancho agrega a la izquierda la barra de publicidad.
/// Cada pestaña se construye la primera vez que se visita y después se
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
  static const int _pestanaMapa = 2;

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
    ];
  }

  Widget _pestana(int indice) {
    final estado = widget.estado;
    switch (indice) {
      case 1:
        return AnchoLimitado(child: BusquedaPantalla(estado: estado));
      case _pestanaMapa:
        // El mapa usa todo el ancho: plano y leyenda ocupan la mitad cada uno.
        return MapaPantalla(estado: estado);
      default:
        return AnchoLimitado(child: InicioPantalla(estado: estado, alBuscar: () => _ir(1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final amplio = ancho >= 840;
    final compacto = ancho < 600;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final destinos = _destinos;
    final cuerpo = IndexedStack(
      index: _indice,
      children: [
        for (var i = 0; i < destinos.length; i++)
          _visitadas.contains(i) ? _pestana(i) : const SizedBox.shrink(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: compacto ? Espacio.s : null,
        title: Row(
          children: [
            Flexible(child: _Marca(estado: widget.estado, conTitulo: !compacto, alTocar: () => _ir(0))),
            SizedBox(width: compacto ? Espacio.xs : Espacio.l),
            for (var i = 0; i < destinos.length; i++)
              _BotonDestino(
                destino: destinos[i],
                activo: i == _indice,
                conTexto: amplio,
                alTocar: () => _ir(i),
              ),
          ],
        ),
        actions: [
          if (amplio)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => mostrarReporte(context, widget.estado),
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('Reportar'),
            )
          else
            IconButton(
              tooltip: 'Reportar falla, queja o sugerencia',
              onPressed: () => mostrarReporte(context, widget.estado),
              icon: const Icon(Icons.feedback_outlined),
            ),
          IconButton(
            tooltip: oscuro ? 'Modo claro' : 'Modo oscuro',
            onPressed: () => widget.estado.alternarTema(Theme.of(context).brightness),
            icon: Icon(oscuro ? Icons.light_mode : Icons.dark_mode),
          ),
          _BotonCuenta(estado: widget.estado, compacto: compacto),
          SizedBox(width: compacto ? Espacio.xs : Espacio.s),
        ],
      ),
      body: amplio
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BarraPublicidad(apariencia: widget.estado.apariencia),
                const VerticalDivider(width: 1),
                Expanded(child: cuerpo),
              ],
            )
          : cuerpo,
    );
  }
}

/// Logo (si el admin subió uno) y título de la app. Al tocarlo vuelve a Inicio.
class _Marca extends StatelessWidget {
  const _Marca({required this.estado, required this.conTitulo, required this.alTocar});

  final EstadoApp estado;

  /// Falso en pantallas angostas: solo el icono, para dejar sitio a los botones.
  final bool conTitulo;

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final menu = estado.apariencia;
    final imagen = menu.logoUrl.isNotEmpty ? menu.logoUrl : menu.iconoUrl;
    return Tooltip(
      message: 'Ir a ${menu.menuInicio}',
      child: Semantics(
        button: true,
        label: 'Ir a ${menu.menuInicio}',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sin logo del administrador se usa el icono de la app.
                if (imagen.isNotEmpty)
                  ImagenRed(imagen, alto: 32, ancho: 32, radio: 8, respaldo: const LogoLiebre(lado: 32))
                else
                  const LogoLiebre(lado: 32),
                if (conTitulo) ...[
                  const SizedBox(width: 10),
                  Flexible(child: Text(menu.titulo, overflow: TextOverflow.ellipsis)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón de una pestaña en la barra roja. La pestaña activa lleva fondo claro.
class _BotonDestino extends StatelessWidget {
  const _BotonDestino({required this.destino, required this.activo, required this.conTexto, required this.alTocar});

  final _Destino destino;
  final bool activo;

  /// Verdadero en pantallas amplias: icono y etiqueta; si no, solo icono.
  final bool conTexto;

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final icono = Icon(iconoMenu(destino.icono, activo: activo));
    final estilo = TextButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: activo ? Colors.white.withValues(alpha: 0.2) : null,
      shape: const StadiumBorder(),
    );
    final boton = conTexto
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: TextButton.icon(style: estilo, onPressed: alTocar, icon: icono, label: Text(destino.etiqueta)),
          )
        : IconButton(
            tooltip: destino.etiqueta,
            isSelected: activo,
            // 40 px en lugar de 48: en un celular de 360 px caben logo, tres pestañas y acciones.
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: activo ? Colors.white.withValues(alpha: 0.2) : null,
            ),
            onPressed: alTocar,
            icon: icono,
          );
    return Semantics(selected: activo, child: boton);
  }
}

/// "Entrar" para invitados; para cuentas activas, el nombre abre el menú de la cuenta.
class _BotonCuenta extends StatelessWidget {
  const _BotonCuenta({required this.estado, required this.compacto});

  static const String _salir = 'salir';

  final EstadoApp estado;
  final bool compacto;

  Future<void> _elegir(BuildContext context, String opcion) async {
    if (opcion == _salir) {
      if (await confirmar(context, titulo: 'Cerrar sesión', mensaje: '¿Quieres salir de tu cuenta?', accion: 'Salir')) {
        await estado.salir();
      }
      return;
    }
    final seccion = SeccionCuenta.values.byName(opcion);
    if (context.mounted) {
      await abrirSeccionCuenta(context, estado, seccion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = estado.usuario;
    if (usuario == null) {
      if (compacto) {
        return IconButton(
          tooltip: 'Entrar',
          onPressed: () => mostrarDialogoSesion(context, estado),
          icon: const Icon(Icons.login),
        );
      }
      return TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: () => mostrarDialogoSesion(context, estado),
        icon: const Icon(Icons.login),
        label: const Text('Entrar'),
      );
    }
    final esquema = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Mi cuenta',
      position: PopupMenuPosition.under,
      onSelected: (opcion) => _elegir(context, opcion),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(usuario.nombreCompleto, style: TextStyle(color: esquema.onSurface)),
            subtitle: Text(
              usuario.correoVerificado ? usuario.correo : '${usuario.correo}\nCorreo sin verificar',
              style: TextStyle(color: usuario.correoVerificado ? esquema.onSurfaceVariant : esquema.error),
            ),
          ),
        ),
        const PopupMenuDivider(),
        for (final seccion in SeccionCuenta.para(usuario))
          PopupMenuItem<String>(
            value: seccion.name,
            child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(seccion.icono), title: Text(seccion.titulo)),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: _salir,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout), title: Text('Cerrar sesión')),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: !usuario.correoVerificado,
              smallSize: 10,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: Colors.white,
                child: Text(usuario.inicial, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 480) ...[
              const SizedBox(width: 8),
              Text(usuario.nombre, style: const TextStyle(color: Colors.white)),
            ],
            if (!compacto) const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
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
