import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/tarjeta_producto.dart';
import '../widgets/tarjeta_vendedor.dart';
import 'detalle_producto.dart';
import 'sesion_dialogo.dart';

/// Abre la ficha completa de un negocio en una pantalla nueva.
Future<void> abrirVendedor(BuildContext context, EstadoApp estado, Vendedor vendedor) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DetalleVendedorPantalla(estado: estado, vendedor: vendedor)),
  );
}

/// Ficha de un negocio: estado, ubicación, contacto y catálogo.
class DetalleVendedorPantalla extends StatefulWidget {
  /// [vendedor] ya viene de una lista; los productos se piden aquí.
  const DetalleVendedorPantalla({super.key, required this.estado, required this.vendedor});

  /// Sesión, para favoritos y calificaciones.
  final EstadoApp estado;

  /// Negocio a mostrar.
  final Vendedor vendedor;

  @override
  State<DetalleVendedorPantalla> createState() => _DetalleVendedorPantallaState();
}

class _DetalleVendedorPantallaState extends State<DetalleVendedorPantalla> {
  late Future<List<Producto>> _productos;

  @override
  void initState() {
    super.initState();
    _productos = widget.estado.api.productosDe(widget.vendedor.id);
  }

  Future<void> _alternarFavorito() async {
    if (widget.estado.usuario == null) {
      await mostrarDialogoSesion(context, widget.estado);
      return;
    }
    await intentar(context, () async {
      final marcado = await widget.estado.alternarFavorito(widget.vendedor.id);
      if (mounted) {
        mostrarAviso(context, marcado ? 'Guardado en favoritos.' : 'Quitado de favoritos.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vendedor = widget.vendedor;
    final tema = Theme.of(context);
    final ubicacion = ubicacionDe(vendedor);

    return Scaffold(
      appBar: AppBar(
        title: Text(vendedor.nombreNegocio),
        actions: [
          ListenableBuilder(
            listenable: widget.estado,
            builder: (context, _) {
              final favorito = widget.estado.esFavorito(vendedor.id);
              return IconButton(
                tooltip: favorito ? 'Quitar de favoritos' : 'Guardar en favoritos',
                onPressed: _alternarFavorito,
                icon: Icon(favorito ? Icons.favorite : Icons.favorite_border),
              );
            },
          ),
        ],
      ),
      body: AnchoLimitado(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _productos = widget.estado.api.productosDe(vendedor.id));
            await _productos;
          },
          child: ListView(
            padding: const EdgeInsets.all(Espacio.l),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: ColoresLiebre.primario,
                    child: Icon(iconoCategoria(vendedor.categoria), color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: Espacio.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vendedor.nombreNegocio, style: tema.textTheme.headlineSmall),
                        Text(
                          [vendedor.categoriaEtiqueta, if (vendedor.subtipo != null) vendedor.subtipo!].join(' · '),
                          style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: Espacio.s),
                        EstadoAbierto(abierto: vendedor.disponible),
                      ],
                    ),
                  ),
                ],
              ),
              if ((vendedor.descripcion ?? '').isNotEmpty) ...[
                const SizedBox(height: Espacio.l),
                Text(vendedor.descripcion!, style: tema.textTheme.bodyLarge),
              ],
              const SizedBox(height: Espacio.l),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(ubicacion ?? 'Sin punto en el mapa'),
                      subtitle: const Text('Ubicación en el plantel'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(vendedor.horarioTexto),
                      subtitle: const Text('Horario de atención'),
                    ),
                    for (final (canal, valor) in vendedor.contactos)
                      ListTile(
                        leading: Icon(_iconoCanal(canal)),
                        title: SelectableText(valor),
                        subtitle: Text(canal),
                        trailing: IconButton(
                          tooltip: 'Copiar',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: valor));
                            if (context.mounted) {
                              mostrarAviso(context, '$canal copiado.');
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const TituloSeccion('Catálogo', icono: Icons.storefront_outlined),
              FutureBuilder<List<Producto>>(
                future: _productos,
                builder: (context, captura) {
                  if (captura.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.all(Espacio.l), child: LinearProgressIndicator());
                  }
                  if (captura.hasError) {
                    final error = captura.error;
                    return EstadoVacio.error(
                      mensaje: error is ErrorApi ? error.mensaje : 'No se pudo cargar el catálogo.',
                      alReintentar: () => setState(() => _productos = widget.estado.api.productosDe(vendedor.id)),
                    );
                  }
                  final productos = captura.data!;
                  if (productos.isEmpty) {
                    return const EstadoVacio(
                      icono: Icons.inventory_2_outlined,
                      mensaje: 'Este negocio aún no publica productos.',
                    );
                  }
                  return Column(
                    children: [
                      for (final producto in productos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Espacio.s),
                          child: TarjetaProducto(
                            producto: producto,
                            alTocar: () => abrirProducto(context, widget.estado, producto),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconoCanal(String canal) {
    switch (canal) {
      case 'WhatsApp':
        return Icons.chat_outlined;
      case 'Telegram':
        return Icons.send_outlined;
      case 'Instagram':
        return Icons.camera_alt_outlined;
      default:
        return Icons.phone_outlined;
    }
  }
}
