import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/iconos_menu.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import 'comun_admin.dart';

/// Apariencia: nombre de la app, textos e iconos de las pestañas, logo, icono y portada.
///
/// Las claves son las de `servidor/lib/apariencia.dart`; si agregas una,
/// agrégala también a [Apariencia] y aquí. La publicidad tiene su propia pestaña.
class AdminApariencia extends StatefulWidget {
  /// Sesión de administrador.
  const AdminApariencia({super.key, required this.estado});

  /// Sesión de administrador; al publicar se aplica la apariencia nueva en vivo.
  final EstadoApp estado;

  @override
  State<AdminApariencia> createState() => _AdminAparienciaState();
}

class _AdminAparienciaState extends State<AdminApariencia> {
  final _titulo = TextEditingController();
  final _menuInicio = TextEditingController();
  final _menuBusqueda = TextEditingController();
  final _menuMapa = TextEditingController();
  final _logo = TextEditingController();
  final _iconoImagen = TextEditingController();
  final _portada = TextEditingController();
  late String _menuPerfil;
  late String _iconoInicio;
  late String _iconoBusqueda;
  late String _iconoMapa;
  late String _iconoPerfil;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    final menu = widget.estado.apariencia;
    _titulo.text = menu.titulo;
    _menuInicio.text = menu.menuInicio;
    _menuBusqueda.text = menu.menuBusqueda;
    _menuMapa.text = menu.menuMapa;
    _logo.text = menu.logoUrl;
    _iconoImagen.text = menu.iconoUrl;
    _portada.text = menu.fotoPortadaUrl;
    // Ya no hay pestaña Perfil (la cuenta va en el menú del nombre), pero la clave existe: se conserva.
    _menuPerfil = menu.menuPerfil;
    _iconoInicio = menu.iconoInicio;
    _iconoBusqueda = menu.iconoBusqueda;
    _iconoMapa = menu.iconoMapa;
    _iconoPerfil = menu.iconoPerfil;
  }

  @override
  void dispose() {
    for (final campo in [_titulo, _menuInicio, _menuBusqueda, _menuMapa, _logo, _iconoImagen, _portada]) {
      campo.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _ocupado = true);
    await intentar(context, () async {
      final guardada = await widget.estado.api.guardarApariencia(Apariencia(
        titulo: _titulo.text.trim(),
        menuInicio: _menuInicio.text.trim(),
        menuBusqueda: _menuBusqueda.text.trim(),
        menuMapa: _menuMapa.text.trim(),
        menuPerfil: _menuPerfil,
        iconoInicio: _iconoInicio,
        iconoBusqueda: _iconoBusqueda,
        iconoMapa: _iconoMapa,
        iconoPerfil: _iconoPerfil,
        logoUrl: _logo.text.trim(),
        iconoUrl: _iconoImagen.text.trim(),
        fotoPortadaUrl: _portada.text.trim(),
      ));
      widget.estado.aplicarApariencia(guardada);
    }, exito: 'Apariencia publicada.');
    if (mounted) {
      setState(() => _ocupado = false);
    }
  }

  Future<void> _subir(TextEditingController destino) async {
    setState(() => _ocupado = true);
    final ruta = await subirImagenAdmin(context, widget.estado);
    if (!mounted) {
      return;
    }
    setState(() {
      _ocupado = false;
      if (ruta != null) {
        destino.text = ruta;
      }
    });
    if (ruta != null) {
      mostrarAviso(context, 'Imagen subida. Toca "Publicar apariencia" para mostrarla.');
    }
  }

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: Espacio.m);
    return AnchoLimitado(
      child: ListView(
        padding: const EdgeInsets.all(Espacio.l),
        children: [
          if (_ocupado) const LinearProgressIndicator(),
          TextField(controller: _titulo, decoration: const InputDecoration(labelText: 'Nombre de la aplicación')),
          separacion,
          _filaMenu(_menuInicio, 'Pestaña inicio', _iconoInicio, (valor) => _iconoInicio = valor),
          _filaMenu(_menuBusqueda, 'Pestaña búsqueda', _iconoBusqueda, (valor) => _iconoBusqueda = valor),
          _filaMenu(_menuMapa, 'Pestaña mapa', _iconoMapa, (valor) => _iconoMapa = valor),
          _foto('Logo', _logo),
          _foto('Icono', _iconoImagen),
          _foto('Fotografía de portada', _portada),
          separacion,
          FilledButton.icon(
            onPressed: _ocupado ? null : _guardar,
            icon: const Icon(Icons.publish),
            label: const Text('Publicar apariencia'),
          ),
        ],
      ),
    );
  }

  /// Texto de la pestaña y su icono en la misma fila.
  Widget _filaMenu(TextEditingController campo, String etiqueta, String icono, ValueChanged<String> alElegir) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.m),
      child: Row(
        children: [
          Expanded(child: TextField(controller: campo, decoration: InputDecoration(labelText: etiqueta))),
          const SizedBox(width: Espacio.s),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: nombresDeIcono.containsKey(icono) ? icono : 'home',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Icono'),
              items: [
                for (final entrada in nombresDeIcono.entries)
                  DropdownMenuItem(
                    value: entrada.key,
                    child: Row(children: [
                      Icon(iconoMenu(entrada.key, activo: true), size: 20),
                      const SizedBox(width: Espacio.s),
                      Flexible(child: Text(entrada.value, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
              ],
              onChanged: _ocupado ? null : (valor) => setState(() => alElegir(valor ?? icono)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _foto(String etiqueta, TextEditingController campo) {
    final ruta = campo.text.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: campo,
            decoration: InputDecoration(
              labelText: 'URL de $etiqueta',
              suffixIcon: IconButton(
                tooltip: 'Subir $etiqueta',
                onPressed: _ocupado ? null : () => _subir(campo),
                icon: const Icon(Icons.upload_file),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (ruta.isNotEmpty) ...[
            const SizedBox(height: Espacio.s),
            ImagenRed(ruta, alto: 88, ancho: double.infinity, respaldo: const Text('No se pudo mostrar la imagen.')),
          ],
        ],
      ),
    );
  }
}
