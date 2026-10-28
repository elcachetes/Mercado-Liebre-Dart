import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos/modelos.dart';
import 'api.dart';

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

  /// Claro, oscuro o el del sistema (si la persona nunca eligió).
  ThemeMode modo = ThemeMode.system;

  /// Verdadero mientras se restaura la sesión al abrir.
  bool cargando = true;

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

  /// Guarda teléfono, número de control y carrera, y refresca [usuario].
  Future<void> actualizarPerfil({String? telefono, String? numeroControl, String? carrera}) async {
    usuario = await api.actualizarPerfil(telefono: telefono, numeroControl: numeroControl, carrera: carrera);
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
    await _cargarFavoritos();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveToken, token);
  }
}
