import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/iconos_menu.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/instalar_app.dart';
import '../widgets/publicidad.dart';
import '../widgets/reporte_dialogo.dart';
import 'busqueda_pantalla.dart';
import 'detalle_vendedor.dart';
import 'inicio_pantalla.dart';
import 'mapa_pantalla.dart';
import 'perfil_pantalla.dart';
import 'sesion_dialogo.dart';

/// Marco con la barra superior roja, que lleva toda la navegación.
///
/// Desde [anchoBarraLateral] agrega a la izquierda la barra de publicidad
/// (dos carruseles; tocar un anuncio abre la ficha del negocio). Más angosto,
/// los anuncios van entre los resultados de búsqueda ([AnunciosEnLista]).
/// Con una vista previa activa ([EstadoApp.vista]) muestra [_BandaVista] arriba.
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

  /// Cuenta que había en el último cambio de [EstadoApp]; ver [_alCambiarCuenta].
  String? _cuenta;

  @override
  void initState() {
    super.initState();
    _cuenta = widget.estado.usuario?.id;
    widget.estado.addListener(_alCambiarCuenta);
  }

  @override
  void dispose() {
    widget.estado.removeListener(_alCambiarCuenta);
    super.dispose();
  }

  /// Al cerrar sesión o eliminar la cuenta se vuelve a Inicio, la pantalla
  /// principal, desde donde se puede crear otra cuenta.
  void _alCambiarCuenta() {
    final actual = widget.estado.usuario?.id;
    if (_cuenta != null && actual == null && mounted) {
      _ir(0);
    }
    _cuenta = actual;
  }

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
    final amplio = ancho >= anchoBarraLateral;
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
          // En el celular la invitación a instalar va en Inicio para no saturar la barra.
          if (!compacto) BotonInstalar(conTexto: amplio),
          // "Reportar falla" vive en el menú de la cuenta (y en Inicio para invitados).
          _BotonFavoritos(estado: widget.estado, conTexto: amplio),
          IconButton(
            tooltip: oscuro ? 'Modo claro' : 'Modo oscuro',
            onPressed: () => widget.estado.alternarTema(Theme.of(context).brightness),
            icon: Icon(oscuro ? Icons.light_mode : Icons.dark_mode),
          ),
          _BotonCuenta(estado: widget.estado, compacto: compacto),
          SizedBox(width: compacto ? Espacio.xs : Espacio.s),
        ],
      ),
      body: _conBandaVista(amplio
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BarraPublicidad(
                  anuncios: widget.estado.anuncios,
                  alAbrirVendedor: (vendedor) => abrirVendedor(context, widget.estado, vendedor),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: cuerpo),
              ],
            )
          : cuerpo),
    );
  }

  /// Pone [_BandaVista] sobre [contenido] mientras hay una vista previa activa.
  Widget _conBandaVista(Widget contenido) {
    if (widget.estado.vista == VistaCuenta.propia) {
      return contenido;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_BandaVista(estado: widget.estado), Expanded(child: contenido)],
    );
  }
}

/// Abre "Favoritos". A un invitado primero le pide entrar.
class _BotonFavoritos extends StatelessWidget {
  const _BotonFavoritos({required this.estado, required this.conTexto});

  final EstadoApp estado;

  /// Verdadero en pantallas amplias: icono y etiqueta; si no, solo icono.
  final bool conTexto;

  Future<void> _abrir(BuildContext context) async {
    if (estado.usuario == null) {
      await mostrarDialogoSesion(context, estado);
      if (estado.usuario == null || !context.mounted) {
        return;
      }
    }
    await abrirSeccionCuenta(context, estado, SeccionCuenta.favoritos);
  }

  @override
  Widget build(BuildContext context) {
    final icono = Icon(estado.favoritos.isEmpty ? Icons.favorite_outline : Icons.favorite);
    if (conTexto) {
      return TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: () => _abrir(context),
        icon: icono,
        label: const Text('Favoritos'),
      );
    }
    return IconButton(tooltip: 'Favoritos', onPressed: () => _abrir(context), icon: icono);
  }
}

/// Aviso fijo de la vista previa: qué rol se está simulando y cómo volver.
///
/// En la vista de usuario de un vendedor ofrece además abrir su propia ficha
/// tal como la ven los compradores.
class _BandaVista extends StatelessWidget {
  const _BandaVista({required this.estado});

  final EstadoApp estado;

  Future<void> _verMiTienda(BuildContext context) async {
    try {
      final negocio = await estado.api.miNegocio();
      if (!context.mounted) {
        return;
      }
      if (negocio == null) {
        mostrarAviso(context, 'Tu cuenta todavía no tiene un perfil de negocio.');
        return;
      }
      await abrirVendedor(context, estado, negocio);
    } on ErrorApi catch (error) {
      if (context.mounted) {
        mostrarAviso(context, error.mensaje);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final comoUsuario = estado.vista == VistaCuenta.comprador;
    final estilo = TextButton.styleFrom(foregroundColor: esquema.onTertiaryContainer);
    return Material(
      color: esquema.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.xs, Espacio.s, Espacio.xs),
        child: Row(
          children: [
            Icon(estado.vista.icono, size: 20, color: esquema.onTertiaryContainer),
            const SizedBox(width: Espacio.s),
            Expanded(
              child: Text(
                comoUsuario
                    ? 'Vista de usuario: así ven la app los compradores.'
                    : 'Vista de vendedor: así ven la app los vendedores.',
                style: TextStyle(color: esquema.onTertiaryContainer),
              ),
            ),
            if (comoUsuario && (estado.usuario?.esVendedor ?? false))
              TextButton(style: estilo, onPressed: () => _verMiTienda(context), child: const Text('Mi tienda')),
            TextButton(
              style: estilo,
              onPressed: () => estado.cambiarVista(VistaCuenta.propia),
              child: const Text('Salir'),
            ),
          ],
        ),
      ),
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
  static const String _reportar = 'reportar';

  /// Prefijo de las opciones que cambian la vista previa (`vista:comprador`).
  static const String _prefijoVista = 'vista:';

  final EstadoApp estado;
  final bool compacto;

  Future<void> _elegir(BuildContext context, String opcion) async {
    if (opcion == _salir) {
      if (await confirmar(context, titulo: 'Cerrar sesión', mensaje: '¿Quieres salir de tu cuenta?', accion: 'Salir')) {
        await estado.salir();
      }
      return;
    }
    if (opcion == _reportar) {
      await mostrarReporte(context, estado);
      return;
    }
    if (opcion.startsWith(_prefijoVista)) {
      estado.cambiarVista(VistaCuenta.values.byName(opcion.substring(_prefijoVista.length)));
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
    // Las secciones siguen la vista previa; las opciones de vista, el rol real.
    final visible = estado.usuarioVisible ?? usuario;
    final vistas = [
      if (estado.vista != VistaCuenta.propia) VistaCuenta.propia,
      ...estado.vistasDisponibles.where((vista) => vista != estado.vista),
    ];
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
        for (final seccion in SeccionCuenta.para(visible))
          PopupMenuItem<String>(
            value: seccion.name,
            child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(seccion.icono), title: Text(seccion.titulo)),
          ),
        if (vistas.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final vista in vistas)
            PopupMenuItem<String>(
              value: '$_prefijoVista${vista.name}',
              child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(vista.icono), title: Text(vista.etiqueta)),
            ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: _reportar,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.feedback_outlined),
            title: Text('Reportar falla'),
          ),
        ),
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
