import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/compartir.dart';
import '../widgets/verificacion.dart';
import 'sesion_dialogo.dart';

/// Abre la hoja inferior de un producto: precio, reseñas y formulario para calificar.
Future<void> abrirProducto(BuildContext context, EstadoApp estado, Producto producto) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _HojaProducto(estado: estado, producto: producto),
  );
}

class _HojaProducto extends StatefulWidget {
  const _HojaProducto({required this.estado, required this.producto});

  final EstadoApp estado;
  final Producto producto;

  @override
  State<_HojaProducto> createState() => _HojaProductoState();
}

class _HojaProductoState extends State<_HojaProducto> {
  final TextEditingController _comentario = TextEditingController();
  late Future<List<Calificacion>> _resenas;
  int _estrellas = 0;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _resenas = widget.estado.api.calificaciones(widget.producto.id);
    // La hoja no está bajo el ListenableBuilder de la app: entrar o verificar
    // el correo desde aquí debe mostrar el formulario sin cerrarla.
    widget.estado.addListener(_alCambiarEstado);
  }

  @override
  void dispose() {
    widget.estado.removeListener(_alCambiarEstado);
    _comentario.dispose();
    super.dispose();
  }

  void _alCambiarEstado() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _publicar() async {
    if (_estrellas < 1) {
      mostrarAviso(context, 'Elige de 1 a 5 estrellas.');
      return;
    }
    setState(() => _enviando = true);
    var pendiente = false;
    final ok = await intentar(context, () async {
      pendiente = await widget.estado.api.calificar(widget.producto.id, _estrellas, _comentario.text);
    });
    if (ok && mounted) {
      mostrarAviso(
        context,
        pendiente
            ? 'Gracias. Tu reseña se publicará cuando la apruebe la administración.'
            : 'Gracias por tu calificación.',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _enviando = false;
      if (ok) {
        _estrellas = 0;
        _comentario.clear();
        _resenas = widget.estado.api.calificaciones(widget.producto.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final producto = widget.producto;
    final tema = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AnchoLimitado(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Espacio.xl, 0, Espacio.xl, Espacio.xl),
          children: [
            if ((producto.fotoUrl ?? '').isNotEmpty) ...[
              ImagenRed(producto.fotoUrl!, alto: 240, ancho: double.infinity, radio: 16),
              const SizedBox(height: Espacio.l),
            ],
            Row(
              children: [
                Expanded(child: Text(producto.nombre, style: tema.textTheme.headlineSmall)),
                IconButton(
                  tooltip: 'Compartir producto',
                  onPressed: () => compartirProducto(context, producto),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            const SizedBox(height: Espacio.xs),
            Row(
              children: [
                Text(
                  producto.precioFormateado,
                  style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.primary),
                ),
                const SizedBox(width: Espacio.m),
                if (producto.agotado)
                  Chip(
                    label: const Text('Agotado'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: tema.colorScheme.errorContainer,
                  ),
              ],
            ),
            const SizedBox(height: Espacio.s),
            Estrellas(promedio: producto.promedioEstrellas, total: producto.totalResenas),
            if ((producto.descripcion ?? '').isNotEmpty) ...[
              const SizedBox(height: Espacio.m),
              Text(producto.descripcion!),
            ],
            const TituloSeccion('Califica este producto', icono: Icons.rate_review_outlined),
            if (widget.estado.usuario == null)
              OutlinedButton.icon(
                onPressed: () async {
                  await mostrarDialogoSesion(context, widget.estado);
                  if (mounted) {
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.login),
                label: const Text('Entra para calificar'),
              )
            else if (!widget.estado.usuario!.correoVerificado)
              AvisoVerificacion(estado: widget.estado)
            else ...[
              // Los vendedores pueden opinar, pero su reseña pasa antes por la administración.
              if (widget.estado.usuario!.esVendedor)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espacio.s),
                  child: Text(
                    textoResenaVendedor,
                    style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
                  ),
                ),
              Row(
                children: [
                  for (var n = 1; n <= 5; n++)
                    IconButton(
                      tooltip: '$n estrella${n == 1 ? '' : 's'}',
                      onPressed: _enviando ? null : () => setState(() => _estrellas = n),
                      icon: Icon(
                        n <= _estrellas ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: ColoresLiebre.estrella,
                        size: 32,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: _comentario,
                enabled: !_enviando,
                decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _enviando ? null : _publicar,
                  icon: _enviando
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('Publicar'),
                ),
              ),
            ],
            const TituloSeccion('Reseñas recientes', icono: Icons.forum_outlined),
            FutureBuilder<List<Calificacion>>(
              future: _resenas,
              builder: (context, captura) {
                if (captura.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(Espacio.l), child: LinearProgressIndicator());
                }
                if (captura.hasError) {
                  final error = captura.error;
                  return Text(error is ErrorApi ? error.mensaje : 'No se pudieron cargar las reseñas.');
                }
                final resenas = captura.data!;
                if (resenas.isEmpty) {
                  return Text('Aún no hay reseñas. ¡Sé la primera persona en opinar!',
                      style: TextStyle(color: tema.colorScheme.onSurfaceVariant));
                }
                return Column(children: [for (final resena in resenas) _FilaResena(resena)]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso sobre el formulario de reseña cuando quien califica es vendedor.
const String textoResenaVendedor = 'Como vendedor, tu reseña se publicará cuando la apruebe la administración. '
    'Así evitamos opiniones falsas entre negocios.';

class _FilaResena extends StatelessWidget {
  const _FilaResena(this.resena);

  final Calificacion resena;

  @override
  Widget build(BuildContext context) {
    final fecha = resena.creadoEn;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AvatarUsuario(nombre: resena.nombre, fotoUrl: resena.fotoPerfilUrl),
      title: Row(
        children: [
          Flexible(child: Text(resena.nombre, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: Espacio.s),
          Estrellas(promedio: resena.estrellas.toDouble(), tamano: 14),
        ],
      ),
      subtitle: Text([
        if ((resena.comentario ?? '').isNotEmpty) resena.comentario!,
        if (fecha != null) '${fecha.day}/${fecha.month}/${fecha.year}',
      ].join('\n')),
    );
  }
}
