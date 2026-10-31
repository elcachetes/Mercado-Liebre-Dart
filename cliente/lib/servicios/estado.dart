import 'dart:convert';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos/modelos.dart';
import 'api.dart';

/// Cómo se muestra la app a la cuenta activa: con su rol real o como otro rol.
///
/// Sirve para revisar ajustes sin cerrar sesión. Solo cambia la interfaz
/// (menús y botones); la API sigue autorizando con el rol real.
enum VistaCuenta {
  /// El rol real de la cuenta.
  propia('Volver a mi vista', Icons.undo),

  /// Como un vendedor: menú "Mi negocio" y registro de puesto en el mapa.
  vendedor('Ver como vendedor', Icons.storefront_outlined),

  /// Como un comprador: sin menús de negocio, moderación ni administración.
  comprador('Ver como usuario', Icons.person_search_outlined);

  const VistaCuenta(this.etiqueta, this.icono);

  /// Texto del menú de la cuenta.
  final String etiqueta;

  /// Icono del menú de la cuenta.
  final IconData icono;

  /// Rol que simula; null en [propia].
  String? get rol => switch (this) {
        propia => null,
        vendedor => 'vendedor',
        comprador => 'comprador',
      };
}

/// Sesión de la app y acceso a la API.
///
/// Guarda el token en el dispositivo. Al abrir, intenta recuperar la
/// cuenta; si el token ya no sirve, deja a la persona como invitada.
///
/// Las pantallas lo reciben por constructor y escuchan sus cambios con
/// `ListenableBuilder` o `addListener`.
class EstadoApp extends ChangeNotifier {
  /// Crea el estado con un cliente HTTP nuevo, o con [api] en pruebas.
  EstadoApp({ClienteApi? api}) : api = api ?? ClienteApi();

  /// Cliente que usa el token actual.
  final ClienteApi api;

  /// Cuenta activa, o null si se explora sin entrar.
  Usuario? usuario;

  /// Menús, iconos y fotografías publicados por el administrador.
  Apariencia apariencia = Apariencia.predeterminada();

  /// Anuncios de los carruseles de publicidad. Vacía si la API no respondió.
  List<Anuncio> anuncios = const [];

  /// Claro, oscuro o el del sistema (si la persona nunca eligió).
  ThemeMode modo = ThemeMode.system;

  /// Verdadero mientras se restaura la sesión al abrir.
  bool cargando = true;

  /// Vista previa elegida en el menú de la cuenta. Vuelve a [VistaCuenta.propia] al entrar o salir.
  VistaCuenta vista = VistaCuenta.propia;

  /// [usuario] con el rol de [vista]. Menús y botones que dependen del rol lo usan.
  Usuario? get usuarioVisible {
    final cuenta = usuario;
    final rol = vista.rol;
    return cuenta == null || rol == null ? cuenta : cuenta.conRol(rol);
  }

  /// Vistas previas que puede elegir la cuenta activa (sin contar [VistaCuenta.propia]).
  ///
  /// Admin → vendedor y usuario; vendedor → usuario; los demás, ninguna.
  List<VistaCuenta> get vistasDisponibles {
    final cuenta = usuario;
    if (cuenta == null) {
      return const [];
    }
    if (cuenta.esAdmin) {
      return const [VistaCuenta.vendedor, VistaCuenta.comprador];
    }
    return cuenta.esVendedor ? const [VistaCuenta.comprador] : const [];
  }

  /// Cambia la vista previa. Ignora vistas que la cuenta no puede usar.
  void cambiarVista(VistaCuenta nueva) {
    if (nueva != VistaCuenta.propia && !vistasDisponibles.contains(nueva)) {
      return;
    }
    vista = nueva;
    notifyListeners();
  }

  /// Ids de los vendedores favoritos de la cuenta activa.
  Set<String> get favoritos => Set.unmodifiable(_favoritos);
  Set<String> _favoritos = {};

  static const String _claveToken = 'token_sesion';
  static const String _claveTema = 'tema_liebre';

  /// Lee el token y el tema, y pide la apariencia pública.
  ///
  /// Pase lo que pase termina con [cargando] en falso: un fallo aquí deja
  /// a la persona como invitada, nunca en la pantalla de arranque.
  Future<void> restaurar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      modo = switch (prefs.getString(_claveTema)) {
        'oscuro' => ThemeMode.dark,
        'claro' => ThemeMode.light,
        _ => ThemeMode.system,
      };
      try {
        apariencia = await api.apariencia();
      } catch (_) {
        apariencia = Apariencia.predeterminada();
      }
      try {
        anuncios = await api.anuncios();
      } catch (_) {
        anuncios = const []; // Sin anuncios se muestra "Anúnciate aquí".
      }
      final token = prefs.getString(_claveToken);
      if (token != null && token.isNotEmpty) {
        api.token = token;
        try {
          usuario = await api.yo();
          await _cargarFavoritos();
        } on ErrorApi catch (error) {
          // Sin red se conserva el token para reintentar en la próxima apertura.
          api.token = null;
          if (!error.sinConexion) {
            await prefs.remove(_claveToken);
          }
        }
      }
    } catch (error) {
      debugPrint('No se pudo restaurar la sesión: $error');
      usuario = null;
      api.token = null;
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Entra y persiste el token.
  Future<void> entrar(String correo, String password) async {
    final sesion = await api.iniciarSesion(correo, password);
    await _guardar(sesion.token, sesion.usuario);
  }

  /// Crea la cuenta y entra. Devuelve si se envió el correo de verificación.
  Future<bool> registrar(Map<String, dynamic> datos) async {
    final sesion = await api.registrar(datos);
    await _guardar(sesion.token, sesion.usuario);
    return sesion.correoEnviado;
  }

  /// Vuelve a leer la cuenta, por ejemplo después de abrir el enlace de verificación.
  Future<void> refrescarUsuario() async {
    if (usuario == null) {
      return;
    }
    usuario = await api.yo();
    notifyListeners();
  }

  /// Cambia a oscuro si ahora se ve claro, y viceversa. [actual] es el brillo en pantalla.
  Future<void> alternarTema(Brightness actual) async {
    modo = actual == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveTema, modo == ThemeMode.dark ? 'oscuro' : 'claro');
  }

  /// Publica en la interfaz la apariencia que acaba de guardar el administrador.
  void aplicarApariencia(Apariencia nueva) {
    apariencia = nueva;
    notifyListeners();
  }

  /// Publica en los carruseles los anuncios que acaba de guardar el administrador.
  void aplicarAnuncios(List<Anuncio> nuevos) {
    anuncios = nuevos;
    notifyListeners();
  }

  /// Borra la cuenta en el servidor y deja la app como invitada.
  ///
  /// Si la contraseña es incorrecta lanza [ErrorApi] y la sesión sigue abierta.
  Future<void> eliminarCuenta(String password) async {
    await api.eliminarMiCuenta(password);
    await salir();
  }

  /// Guarda teléfono, número de control y carrera, y refresca [usuario].
  Future<void> actualizarPerfil({String? telefono, String? numeroControl, String? carrera}) async {
    usuario = await api.actualizarPerfil(telefono: telefono, numeroControl: numeroControl, carrera: carrera);
    notifyListeners();
  }

  /// Cambia la cuenta a modo `comprador` o `vendedor` (ver [ClienteApi.cambiarModo]).
  ///
  /// Quita cualquier vista previa: el rol real acaba de cambiar.
  Future<void> cambiarModo(String modo, {Map<String, dynamic> negocio = const {}}) async {
    usuario = await api.cambiarModo(modo, negocio: negocio);
    vista = VistaCuenta.propia;
    notifyListeners();
  }

  /// Sube [jpeg] como foto de perfil, o la quita si es null, y refresca [usuario].
  Future<void> cambiarFotoPerfil(Uint8List? jpeg) async {
    usuario = jpeg == null ? await api.quitarFotoPerfil() : await api.subirFotoPerfil('perfil.jpg', base64Encode(jpeg));
    notifyListeners();
  }

  /// Verdadero si [sellerId] está en favoritos.
  bool esFavorito(String sellerId) => _favoritos.contains(sellerId);

  /// Marca o desmarca un favorito. Devuelve el estado final.
  ///
  /// Actualiza la interfaz de inmediato y revierte si la API falla.
  Future<bool> alternarFavorito(String sellerId) async {
    final antes = _favoritos.contains(sellerId);
    _cambiarFavorito(sellerId, !antes);
    try {
      final marcado = await api.alternarFavorito(sellerId);
      _cambiarFavorito(sellerId, marcado);
      return marcado;
    } on ErrorApi {
      _cambiarFavorito(sellerId, antes);
      rethrow;
    }
  }

  /// Borra el token local.
  Future<void> salir() async {
    usuario = null;
    api.token = null;
    _favoritos = {};
    vista = VistaCuenta.propia;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveToken);
  }

  void _cambiarFavorito(String sellerId, bool marcado) {
    _favoritos = {..._favoritos};
    marcado ? _favoritos.add(sellerId) : _favoritos.remove(sellerId);
    notifyListeners();
  }

  Future<void> _cargarFavoritos() async {
    try {
      _favoritos = await api.favoritos();
    } on ErrorApi {
      _favoritos = {};
    }
  }

  Future<void> _guardar(String token, Usuario cuenta) async {
    api.token = token;
    usuario = cuenta;
    vista = VistaCuenta.propia;
    await _cargarFavoritos();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveToken, token);
  }
}
