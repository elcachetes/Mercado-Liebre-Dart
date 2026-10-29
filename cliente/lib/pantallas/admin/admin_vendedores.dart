import 'package:flutter/material.dart';

import '../../mapa/puntos_campus.dart';
import '../../modelos/modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import '../../widgets/tarjeta_producto.dart';
import '../detalle_vendedor.dart';
import '../sesion_dialogo.dart';
import 'comun_admin.dart';

/// Días sin usar la app a partir de los cuales un negocio se marca como inactivo ("fantasma").
const int diasInactividad = 30;

/// Verdadero si el dueño de [negocio] lleva [diasInactividad] días o más sin usar la app.
bool negocioInactivo(Vendedor negocio, {DateTime? ahora}) {
  final ultimo = negocio.ultimoAcceso;
  return ultimo == null || (ahora ?? DateTime.now()).difference(ultimo).inDays >= diasInactividad;
}

/// "Último uso: hoy", "ayer", "hace 12 días (3 oct 2026)" o "sin registro".
String textoUltimoUso(DateTime? fecha, {DateTime? ahora}) {
  if (fecha == null) {
    return 'Último uso: sin registro';
  }
  final referencia = ahora ?? DateTime.now();
  final dias = DateTime(referencia.year, referencia.month, referencia.day)
      .difference(DateTime(fecha.year, fecha.month, fecha.day))
      .inDays;
  return switch (dias) {
    <= 0 => 'Último uso: hoy',
    1 => 'Último uso: ayer',
    _ => 'Último uso: hace $dias días (${fechaCorta(fecha)})',
  };
}

/// Negocios: editar datos, punto del mapa y promoción; ver y borrar productos; eliminar el negocio.
///
/// Muestra el último uso de la app de cada dueño y filtra los inactivos
/// para encontrar tiendas fantasma y cerrarlas o eliminarlas.
class AdminVendedores extends StatefulWidget {
  /// Sesión de administrador.
  const AdminVendedores({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  @override
  State<AdminVendedores> createState() => _AdminVendedoresState();
}

class _AdminVendedoresState extends State<AdminVendedores> {
  String _filtro = '';
  bool _soloInactivos = false;

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    return CargaAdmin<List<Vendedor>>(
      cargar: estado.api.vendedoresAdmin,
      construir: (context, negocios, recargar) {
        final inactivos = negocios.where((v) => negocioInactivo(v)).length;
        final visibles = negocios
            .where((v) =>
                (!_soloInactivos || negocioInactivo(v)) &&
                (_filtro.isEmpty ||
                    v.nombreNegocio.toLowerCase().contains(_filtro) ||
                    (v.subtipo ?? '').toLowerCase().contains(_filtro)))
            .toList();
        return [
          Text('${negocios.length} negocios', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espacio.s),
          Text(
            'Para crear un negocio nuevo, crea una cuenta con rol Vendedor en la pestaña Usuarios.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Espacio.m),
          BuscadorAdmin(pista: 'Nombre o especialidad', alCambiar: (texto) => setState(() => _filtro = texto)),
          Padding(
            padding: const EdgeInsets.only(bottom: Espacio.s),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: Text('Sin usar la app en $diasInactividad+ días ($inactivos)'),
                avatar: const Icon(Icons.hourglass_bottom, size: 18),
                selected: _soloInactivos,
                onSelected: (valor) => setState(() => _soloInactivos = valor),
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final negocio in visibles) _FilaNegocio(negocio: negocio, estado: estado, alCambiar: recargar),
                if (visibles.isEmpty) const ListTile(title: Text('Ningún negocio coincide.')),
              ],
            ),
          ),
        ];
      },
    );
  }
}

class _FilaNegocio extends StatelessWidget {
  const _FilaNegocio({required this.negocio, required this.estado, required this.alCambiar});

  final Vendedor negocio;
  final EstadoApp estado;
  final Future<void> Function() alCambiar;

  Future<void> _elegir(BuildContext context, String opcion) async {
    switch (opcion) {
      case 'editar':
        if (await editarNegocio(context, estado, negocio)) {
          await alCambiar();
        }
      case 'productos':
        await showDialog<void>(context: context, builder: (_) => _ProductosNegocio(estado: estado, negocio: negocio));
      case 'ficha':
        await abrirVendedor(context, estado, negocio);
      case 'cerrar':
        if (!await confirmar(
          context,
          titulo: 'Marcar como cerrado',
          mensaje: '"${negocio.nombreNegocio}" dejará de aparecer en "Abiertos ahora" y en el filtro "Solo abiertos". '
              'Su dueño puede volver a abrirlo desde "Mi negocio".',
          accion: 'Cerrar',
        )) {
          return;
        }
        if (context.mounted &&
            await intentar(
              context,
              () => estado.api.actualizarVendedorAdmin(negocio.id, {'disponible': false}),
              exito: 'Negocio marcado como cerrado.',
            )) {
          await alCambiar();
        }
      case 'eliminar':
        if (!await confirmar(
          context,
          titulo: 'Eliminar negocio',
          mensaje: 'Se borrará "${negocio.nombreNegocio}" con todos sus productos, fotos, precios, reseñas y anuncios. '
              'La cuenta de su dueño seguirá existiendo como comprador.',
        )) {
          return;
        }
        if (context.mounted &&
            await intentar(context, () => estado.api.eliminarNegocio(negocio.id), exito: 'Negocio eliminado.')) {
          await alCambiar();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final punto = puntoPorCodigo(negocio.edificio);
    return ListTile(
      title: Text(negocio.nombreNegocio),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Espacio.xs),
        child: Wrap(
          spacing: Espacio.xs,
          runSpacing: Espacio.xs,
          children: [
            Etiqueta(negocio.categoriaEtiqueta),
            Etiqueta(
              negocio.disponible ? 'Abierto' : 'Cerrado',
              color: negocio.disponible ? ColoresLiebre.abierto(Theme.of(context).brightness) : esquema.outline,
            ),
            Etiqueta(punto == null ? 'Sin punto' : 'Punto ${punto.codigo}', color: punto == null ? esquema.error : null),
            if (negocio.destacado) Etiqueta('Destacado', color: ColoresLiebre.estrella),
            Etiqueta(textoUltimoUso(negocio.ultimoAcceso), color: negocioInactivo(negocio) ? esquema.error : null),
          ],
        ),
      ),
      onTap: () => _elegir(context, 'editar'),
      trailing: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (opcion) => _elegir(context, opcion),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'editar', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
          const PopupMenuItem(
            value: 'productos',
            child: ListTile(leading: Icon(Icons.inventory_2_outlined), title: Text('Productos')),
          ),
          const PopupMenuItem(value: 'ficha', child: ListTile(leading: Icon(Icons.visibility_outlined), title: Text('Ver ficha'))),
          if (negocio.disponible)
            const PopupMenuItem(
              value: 'cerrar',
              child: ListTile(leading: Icon(Icons.storefront_outlined), title: Text('Marcar como cerrado')),
            ),
          PopupMenuItem(
            value: 'eliminar',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: esquema.error),
              title: Text('Eliminar negocio', style: TextStyle(color: esquema.error)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre el formulario de edición de [negocio]. Devuelve true si se guardó.
///
/// También lo usa la pestaña Mapa para cambiar el punto.
Future<bool> editarNegocio(BuildContext context, EstadoApp estado, Vendedor negocio) async {
  return await showDialog<bool>(context: context, builder: (_) => _EditarNegocio(estado: estado, negocio: negocio)) ==
      true;
}

class _EditarNegocio extends StatefulWidget {
  const _EditarNegocio({required this.estado, required this.negocio});

  final EstadoApp estado;
  final Vendedor negocio;

  @override
  State<_EditarNegocio> createState() => _EditarNegocioState();
}

class _EditarNegocioState extends State<_EditarNegocio> {
  final _formulario = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.negocio.nombreNegocio);
  late final _subtipo = TextEditingController(text: widget.negocio.subtipo);
  late final _descripcion = TextEditingController(text: widget.negocio.descripcion);
  late String _categoria = widget.negocio.categoria;
  late String _edificio = widget.negocio.edificio ?? '';
  late bool _disponible = widget.negocio.disponible;
  late bool _destacado = widget.negocio.destacado;
  late DateTime? _hasta = widget.negocio.destacadoHasta;
  bool _ocupado = false;

  @override
  void dispose() {
    _nombre.dispose();
    _subtipo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _elegirFin() async {
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _hasta ?? hoy.add(const Duration(days: 30)),
      firstDate: hoy,
      lastDate: hoy.add(const Duration(days: 730)),
      helpText: 'Fin de la promoción',
    );
    if (fecha != null) {
      // Termina al final de ese día.
      setState(() => _hasta = DateTime(fecha.year, fecha.month, fecha.day, 23, 59));
    }
  }

  Future<void> _guardar() async {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _ocupado = true);
    final ok = await intentar(
      context,
      () => widget.estado.api.actualizarVendedorAdmin(widget.negocio.id, {
        'nombreNegocio': _nombre.text,
        'categoria': _categoria,
        'subtipo': _subtipo.text,
        'descripcion': _descripcion.text,
        'edificio': _edificio,
        'disponible': _disponible,
        'destacado': _destacado,
        'destacadoHasta': _destacado ? (_hasta?.toUtc().toIso8601String() ?? '') : '',
      }),
      exito: 'Negocio actualizado.',
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: Espacio.m);
    return AlertDialog(
      title: const Text('Editar negocio'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombre,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                  validator: Validar.requerido,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final (valor, etiqueta) in categoriasNegocio) DropdownMenuItem(value: valor, child: Text(etiqueta)),
                  ],
                  onChanged: (valor) => setState(() => _categoria = valor ?? _categoria),
                ),
                separacion,
                TextFormField(
                  controller: _subtipo,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Especialidad (opcional)', hintText: 'Comida mexicana'),
                ),
                TextFormField(
                  controller: _descripcion,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _edificio,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Punto del mapa'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Sin punto')),
                    for (final punto in puntosCampus)
                      DropdownMenuItem(
                        value: punto.codigo,
                        child: Text('${punto.codigo} · ${punto.nombre}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (valor) => setState(() => _edificio = valor ?? ''),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _disponible,
                  title: const Text('Abierto ahora'),
                  onChanged: (valor) => setState(() => _disponible = valor),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _destacado,
                  title: const Text('Destacado'),
                  subtitle: const Text('Aparece primero y en "Destacados" de Inicio.'),
                  onChanged: (valor) => setState(() => _destacado = valor),
                ),
                if (_destacado)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: Text(_hasta == null ? 'Sin fecha de fin' : 'Hasta el ${fechaCorta(_hasta)}'),
                    trailing: Wrap(
                      children: [
                        if (_hasta != null)
                          IconButton(
                            tooltip: 'Quitar fecha de fin',
                            onPressed: () => setState(() => _hasta = null),
                            icon: const Icon(Icons.close),
                          ),
                        IconButton(tooltip: 'Elegir fecha', onPressed: _elegirFin, icon: const Icon(Icons.edit_calendar)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Productos de un negocio, cada uno con botón para borrarlo (con su foto).
class _ProductosNegocio extends StatefulWidget {
  const _ProductosNegocio({required this.estado, required this.negocio});

  final EstadoApp estado;
  final Vendedor negocio;

  @override
  State<_ProductosNegocio> createState() => _ProductosNegocioState();
}

class _ProductosNegocioState extends State<_ProductosNegocio> {
  List<Producto>? _productos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await widget.estado.api.productosDe(widget.negocio.id);
      if (mounted) {
        setState(() => _productos = lista);
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() => _error = error.mensaje);
      }
    }
  }

  Future<void> _borrar(Producto producto) async {
    if (!await confirmar(
      context,
      titulo: 'Eliminar producto',
      mensaje: '"${producto.nombre}" se eliminará con su foto, su precio y sus reseñas.',
    )) {
      return;
    }
    if (mounted &&
        await intentar(context, () => widget.estado.api.eliminarProductoAdmin(producto.id), exito: 'Producto eliminado.')) {
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final productos = _productos;
    final esquema = Theme.of(context).colorScheme;
    final Widget contenido;
    if (_error != null) {
      contenido = Text(_error!, style: TextStyle(color: esquema.error));
    } else if (productos == null) {
      contenido = const Center(child: CircularProgressIndicator());
    } else if (productos.isEmpty) {
      contenido = const Text('Este negocio no tiene productos.');
    } else {
      contenido = ListView(
        shrinkWrap: true,
        children: [
          for (final producto in productos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MiniaturaProducto(producto: producto),
              title: Text(producto.nombre),
              subtitle: Text(producto.agotado ? '${producto.precioFormateado} · Agotado' : producto.precioFormateado),
              trailing: IconButton(
                tooltip: 'Eliminar',
                onPressed: () => _borrar(producto),
                icon: Icon(Icons.delete_outline, color: esquema.error),
              ),
            ),
        ],
      );
    }
    return AlertDialog(
      title: Text('Productos de ${widget.negocio.nombreNegocio}'),
      content: SizedBox(width: 460, child: contenido),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
