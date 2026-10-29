/// Piezas que comparten las pestañas del panel de administración.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../servicios/api.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';

/// Carga datos con [cargar] y los dibuja con [construir].
///
/// Resuelve lo que se repite en cada pestaña: indicador de carga, error con
/// "Reintentar", deslizar hacia abajo para recargar y lista con el padding de
/// la app. [construir] recibe `recargar` para usarlo después de guardar.
class CargaAdmin<T> extends StatefulWidget {
  /// [limitarAncho] falso deja el contenido a todo lo ancho (tablas).
  const CargaAdmin({super.key, required this.cargar, required this.construir, this.limitarAncho = true});

  /// Petición a la API. Debe lanzar [ErrorApi] si falla.
  final Future<T> Function() cargar;

  /// Hijos de la lista con los datos ya cargados.
  final List<Widget> Function(BuildContext context, T datos, Future<void> Function() recargar) construir;

  /// Centra y limita el ancho como el resto de la app.
  final bool limitarAncho;

  @override
  State<CargaAdmin<T>> createState() => _CargaAdminState<T>();
}

class _CargaAdminState<T> extends State<CargaAdmin<T>> {
  T? _datos;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await widget.cargar();
      if (mounted) {
        setState(() => _datos = datos);
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() => _error = error.mensaje);
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    if (datos == null) {
      if (_error != null) {
        return EstadoVacio.error(mensaje: _error!, alReintentar: _recargar);
      }
      return const Center(child: CircularProgressIndicator());
    }
    final lista = RefreshIndicator(
      onRefresh: _recargar,
      child: ListView(
        padding: const EdgeInsets.all(Espacio.l),
        children: [
          if (_cargando) const LinearProgressIndicator(),
          ...widget.construir(context, datos, _recargar),
        ],
      ),
    );
    return widget.limitarAncho ? AnchoLimitado(child: lista) : lista;
  }
}

/// Campo de búsqueda para filtrar listas del panel.
class BuscadorAdmin extends StatelessWidget {
  /// [alCambiar] recibe el texto en minúsculas y sin espacios sobrantes.
  const BuscadorAdmin({super.key, required this.pista, required this.alCambiar});

  /// Texto de ayuda dentro del campo.
  final String pista;

  /// Se llama con cada letra.
  final ValueChanged<String> alCambiar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.m),
      child: TextField(
        decoration: InputDecoration(hintText: pista, prefixIcon: const Icon(Icons.search)),
        onChanged: (texto) => alCambiar(texto.trim().toLowerCase()),
      ),
    );
  }
}

/// Fecha local `dd/mm/aaaa hh:mm`, o "—" si no hay.
String fechaCorta(DateTime? fecha) {
  if (fecha == null) {
    return '—';
  }
  final local = fecha.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(local.day)}/${dos(local.month)}/${local.year} ${dos(local.hour)}:${dos(local.minute)}';
}

/// Elige una imagen del equipo y la sube a `/medios`. Devuelve su ruta, o null.
///
/// Mismo límite de 1.5 MB que `Medios.maximoBytes` en el servidor.
Future<String?> subirImagenAdmin(BuildContext context, EstadoApp estado) async {
  final elegido = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  final archivo = elegido?.files.single;
  final bytes = archivo?.bytes;
  if (archivo == null || bytes == null || !context.mounted) {
    return null;
  }
  if (bytes.length > 1500000) {
    mostrarAviso(context, 'La imagen pesa más de 1.5 MB. Redúcela e inténtalo de nuevo.');
    return null;
  }
  try {
    return await estado.api.subirMedio(archivo.name, base64Encode(bytes));
  } on ErrorApi catch (error) {
    if (context.mounted) {
      mostrarAviso(context, error.mensaje);
    }
    return null;
  }
}

/// Etiqueta pequeña de color (estado, rol…).
class Etiqueta extends StatelessWidget {
  /// [color] tiñe el fondo; el texto usa el mismo color más oscuro.
  const Etiqueta(this.texto, {super.key, this.color});

  /// Texto corto.
  final String texto;

  /// Color de acento; por defecto el secundario del tema.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final base = color ?? esquema.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: 2),
      decoration: BoxDecoration(color: base.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: base)),
    );
  }
}
