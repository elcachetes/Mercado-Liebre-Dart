import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import '../../widgets/publicidad.dart';
import 'comun_admin.dart';

/// Publicidad: [Anuncio.secciones] carruseles con [Anuncio.porSeccion] imágenes cada uno.
///
/// Cada imagen se enlaza a un negocio: al tocarla en la app se abre su ficha.
/// Todas duran lo mismo en pantalla ([duracionAnuncio]).
class AdminPublicidad extends StatelessWidget {
  /// Sesión de administrador.
  const AdminPublicidad({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  static const List<String> _nombresSeccion = ['Carrusel de arriba', 'Carrusel de abajo'];

  @override
  Widget build(BuildContext context) {
    final api = estado.api;
    return CargaAdmin<(List<Anuncio>, List<Vendedor>)>(
      // Una tras otra: así un fallo llega como ErrorApi y CargaAdmin muestra "Reintentar".
      cargar: () async => (await api.anuncios(), await api.vendedores()),
      construir: (context, datos, recargar) {
        final (anuncios, negocios) = datos;
        final tenue = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
        return [
          Text(
            'Se ven en la barra lateral en pantallas amplias. Cada carrusel rota sus imágenes cada '
            '${duracionAnuncio.inSeconds} segundos, todas el mismo tiempo. Usa imágenes verticales '
            '(por ejemplo 320 × 600 px, máx. 1.5 MB). Un carrusel vacío muestra "Anúnciate aquí".',
            style: tenue,
          ),
          for (var seccion = 1; seccion <= Anuncio.secciones; seccion++) ...[
            TituloSeccion(_nombresSeccion[seccion - 1], icono: Icons.view_carousel_outlined),
            LayoutBuilder(
              builder: (context, limites) {
                final vista = SizedBox(
                  width: anchoBarraPublicidad - 2 * Espacio.s,
                  height: 300,
                  child: EspacioPublicitario(
                    anuncios: anunciosDeSeccion(anuncios, seccion),
                    // En la vista previa no se navega: solo se muestra a dónde lleva.
                    alAbrirVendedor: (vendedor) => mostrarAviso(context, 'Este anuncio abre "${vendedor.nombreNegocio}".'),
                  ),
                );
                final ranuras = Column(
                  children: [
                    for (var posicion = 1; posicion <= Anuncio.porSeccion; posicion++)
                      _Ranura(
                        key: ValueKey('$seccion-$posicion'),
                        estado: estado,
                        seccion: seccion,
                        posicion: posicion,
                        actual: anuncios.where((a) => a.seccion == seccion && a.posicion == posicion).firstOrNull,
                        negocios: negocios,
                        alGuardar: recargar,
                      ),
                  ],
                );
                // Vista previa a un lado en pantallas anchas; arriba en el celular.
                if (limites.maxWidth >= 620) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [vista, const SizedBox(width: Espacio.l), Expanded(child: ranuras)],
                  );
                }
                return Column(children: [Center(child: vista), const SizedBox(height: Espacio.m), ranuras]);
              },
            ),
          ],
        ];
      },
    );
  }
}

/// Una posición del carrusel: imagen, negocio enlazado, guardar y quitar.
class _Ranura extends StatefulWidget {
  const _Ranura({
    super.key,
    required this.estado,
    required this.seccion,
    required this.posicion,
    required this.actual,
    required this.negocios,
    required this.alGuardar,
  });

  final EstadoApp estado;
  final int seccion;
  final int posicion;

  /// Lo publicado ahora en esta posición, o null si está vacía.
  final Anuncio? actual;

  final List<Vendedor> negocios;

  /// Recarga la pestaña después de guardar o quitar.
  final Future<void> Function() alGuardar;

  @override
  State<_Ranura> createState() => _RanuraState();
}

class _RanuraState extends State<_Ranura> {
  late String _imagen = widget.actual?.imagenUrl ?? '';
  late String? _vendedorId = widget.actual?.vendedor?.id;
  bool _ocupado = false;

  @override
  void didUpdateWidget(_Ranura anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.actual != widget.actual) {
      _imagen = widget.actual?.imagenUrl ?? '';
      _vendedorId = widget.actual?.vendedor?.id;
    }
  }

  bool get _cambiado => _imagen != (widget.actual?.imagenUrl ?? '') || _vendedorId != widget.actual?.vendedor?.id;

  Future<void> _ejecutar(Future<List<Anuncio>> Function() accion, String exito) async {
    setState(() => _ocupado = true);
    final ok = await intentar(context, () async {
      // Los carruseles de la app se actualizan sin recargarla.
      widget.estado.aplicarAnuncios(await accion());
    }, exito: exito);
    if (mounted) {
      setState(() => _ocupado = false);
    }
    if (ok) {
      await widget.alGuardar();
    }
  }

  Future<void> _subir() async {
    setState(() => _ocupado = true);
    final ruta = await subirImagenAdmin(context, widget.estado);
    if (mounted) {
      setState(() {
        _ocupado = false;
        if (ruta != null) {
          _imagen = ruta;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final api = widget.estado.api;
    // Si el negocio enlazado ya no está en la lista, el valor no debe romper el menú.
    final vendedor = widget.negocios.any((v) => v.id == _vendedorId) ? _vendedorId : null;
    return Card(
      margin: const EdgeInsets.only(bottom: Espacio.m),
      child: Padding(
        padding: const EdgeInsets.all(Espacio.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              height: 112,
              child: Material(
                color: esquema.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: _imagen.isEmpty
                    ? Icon(Icons.image_outlined, color: esquema.onSurfaceVariant)
                    : ImagenRed(_imagen, radio: 0, respaldo: const Icon(Icons.broken_image_outlined)),
              ),
            ),
            const SizedBox(width: Espacio.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Imagen ${widget.posicion}', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: Espacio.s),
                  DropdownButtonFormField<String?>(
                    initialValue: vendedor,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Al tocarla abre', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Nada (solo imagen)')),
                      for (final negocio in widget.negocios)
                        DropdownMenuItem<String?>(
                          value: negocio.id,
                          child: Text(negocio.nombreNegocio, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _ocupado ? null : (valor) => setState(() => _vendedorId = valor),
                  ),
                  const SizedBox(height: Espacio.s),
                  Wrap(
                    spacing: Espacio.s,
                    runSpacing: Espacio.xs,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _ocupado ? null : _subir,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_imagen.isEmpty ? 'Subir imagen' : 'Cambiar imagen'),
                      ),
                      FilledButton(
                        onPressed: _ocupado || _imagen.isEmpty || !_cambiado
                            ? null
                            : () => _ejecutar(
                                  () => api.guardarAnuncio(widget.seccion, widget.posicion,
                                      imagenUrl: _imagen, vendedorId: _vendedorId),
                                  'Anuncio publicado.',
                                ),
                        child: const Text('Publicar'),
                      ),
                      if (widget.actual != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: esquema.error),
                          onPressed: _ocupado
                              ? null
                              : () => _ejecutar(() => api.quitarAnuncio(widget.seccion, widget.posicion), 'Anuncio quitado.'),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Quitar'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
