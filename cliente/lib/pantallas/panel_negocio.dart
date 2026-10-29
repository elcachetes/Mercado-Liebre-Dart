import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../modelos/modelos.dart';
import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../servicios/imagenes.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
import '../widgets/eliminar_cuenta.dart';
import '../widgets/tarjeta_producto.dart';
import '../widgets/selector_dias.dart';
import 'sesion_dialogo.dart';

/// Disponibilidad, catálogo, horario y contacto del vendedor autenticado.
///
/// El edificio del puesto no se edita aquí: se elige tocando el plano.
class PanelNegocio extends StatefulWidget {
  /// [negocio] es el perfil ya cargado. [alCambiar] pide recargar el perfil.
  const PanelNegocio({super.key, required this.estado, required this.negocio, required this.alCambiar});

  /// Sesión con el cliente HTTP.
  final EstadoApp estado;

  /// Negocio dueño de los productos.
  final Vendedor negocio;

  /// Se llama después de guardar horario, contacto o disponibilidad.
  final Future<void> Function() alCambiar;

  @override
  State<PanelNegocio> createState() => _PanelNegocioState();
}

class _PanelNegocioState extends State<PanelNegocio> {
  final TextEditingController _whatsapp = TextEditingController();
  final TextEditingController _telegram = TextEditingController();
  final TextEditingController _instagram = TextEditingController();
  final TextEditingController _telefono = TextEditingController();
  TimeOfDay? _apertura;
  TimeOfDay? _cierre;
  Set<int> _dias = {};

  List<Producto> _productos = [];
  bool _cargando = true;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _copiarNegocio();
    _cargarProductos();
  }

  @override
  void didUpdateWidget(PanelNegocio anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.negocio.id != widget.negocio.id) {
      _copiarNegocio();
      _cargarProductos();
    }
  }

  @override
  void dispose() {
    for (final campo in [_whatsapp, _telegram, _instagram, _telefono]) {
      campo.dispose();
    }
    super.dispose();
  }

  /// Rellena los campos con lo que ya está guardado.
  void _copiarNegocio() {
    final negocio = widget.negocio;
    _apertura = _leerHora(negocio.horarioApertura);
    _cierre = _leerHora(negocio.horarioCierre);
    _dias = diasDesdeTexto(negocio.diasAtencion ?? 'Lun-Vie');
    _whatsapp.text = negocio.whatsapp ?? '';
    _telegram.text = negocio.telegram ?? '';
    _instagram.text = negocio.instagram ?? '';
    _telefono.text = negocio.telefonoFijo ?? '';
  }

  Future<void> _cargarProductos() async {
    try {
      final lista = await widget.estado.api.productosDe(widget.negocio.id);
      if (mounted) {
        setState(() {
          _productos = lista;
          _cargando = false;
        });
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() => _cargando = false);
        mostrarAviso(context, error.mensaje);
      }
    }
  }

  /// Bloquea los botones mientras corre [accion] y avisa el resultado.
  Future<bool> _guardar(Future<void> Function() accion, {String? exito}) async {
    setState(() => _ocupado = true);
    final ok = await intentar(context, accion, exito: exito);
    if (mounted) {
      setState(() => _ocupado = false);
    }
    return ok;
  }

  Future<void> _editarProducto([Producto? producto]) async {
    final edicion = await showDialog<_Edicion>(
      context: context,
      builder: (_) => _DialogoProducto(producto: producto),
    );
    if (edicion == null) {
      return;
    }
    if (edicion.eliminar && producto != null) {
      await _borrar(producto);
      return;
    }
    final api = widget.estado.api;
    final datos = edicion.producto;
    final ok = await _guardar(() async {
      final String id;
      if (producto == null) {
        id = (await api.publicarProducto(nombre: datos.nombre, precio: datos.precio, descripcion: datos.descripcion)).id;
      } else {
        await api.actualizarProducto(datos);
        id = datos.id;
      }
      final foto = edicion.fotoNueva;
      if (foto != null) {
        await api.subirFotoProducto(id, 'foto.jpg', base64Encode(foto));
      } else if (edicion.quitarFoto) {
        await api.quitarFotoProducto(id);
      }
    }, exito: producto == null ? 'Producto publicado.' : 'Producto actualizado.');
    if (ok) {
      await _cargarProductos();
    }
  }

  Future<void> _alternarAgotado(Producto producto) async {
    if (await _guardar(() => widget.estado.api.actualizarProducto(producto.copyWith(agotado: !producto.agotado)))) {
      await _cargarProductos();
    }
  }

  /// Borra el producto en la base (`DELETE /api/productos/<id>`) con su foto,
  /// su precio y sus reseñas. Pide confirmación antes.
  Future<void> _borrar(Producto producto) async {
    final seguro = await confirmar(
      context,
      titulo: 'Eliminar producto',
      mensaje: '"${producto.nombre}" se eliminará junto con su fotografía, su precio y sus reseñas. '
          'Esta acción no se puede deshacer.',
    );
    if (seguro && await _guardar(() => widget.estado.api.eliminarProducto(producto.id), exito: 'Producto eliminado.')) {
      await _cargarProductos();
    }
  }

  Future<void> _elegirHora({required bool apertura}) async {
    final elegida = await showTimePicker(
      context: context,
      initialTime: (apertura ? _apertura : _cierre) ?? TimeOfDay(hour: apertura ? 8 : 15, minute: 0),
      helpText: apertura ? 'Hora de apertura' : 'Hora de cierre',
    );
    if (elegida != null) {
      setState(() => apertura ? _apertura = elegida : _cierre = elegida);
    }
  }

  Future<void> _guardarHorario() async {
    if (_apertura == null || _cierre == null) {
      mostrarAviso(context, 'Elige la hora de apertura y de cierre.');
      return;
    }
    if (_dias.isEmpty) {
      mostrarAviso(context, 'Marca al menos un día de atención.');
      return;
    }
    final ok = await _guardar(
      () => widget.estado.api.guardarHorario(
        apertura: _formatoHora(_apertura!),
        cierre: _formatoHora(_cierre!),
        dias: textoDeDias(_dias),
      ),
      exito: 'Horario guardado.',
    );
    if (ok) {
      await widget.alCambiar();
    }
  }

  Future<void> _guardarContacto() async {
    final ok = await _guardar(
      () => widget.estado.api.guardarContacto(
        whatsapp: _whatsapp.text,
        telegram: _telegram.text,
        instagram: _instagram.text,
        telefonoFijo: _telefono.text,
      ),
      exito: 'Contacto guardado.',
    );
    if (ok) {
      await widget.alCambiar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final negocio = widget.negocio;
    final tema = Theme.of(context);
    const separacion = SizedBox(height: Espacio.m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: negocio.disponible,
                secondary: Icon(negocio.disponible ? Icons.storefront : Icons.store_mall_directory_outlined),
                title: Text(negocio.nombreNegocio, style: tema.textTheme.titleMedium),
                subtitle: Text(negocio.disponible ? 'Abierto: apareces en "Abiertos ahora"' : 'Cerrado: no apareces como disponible'),
                onChanged: _ocupado
                    ? null
                    : (valor) async {
                        if (await _guardar(() => widget.estado.api.disponibilidad(valor))) {
                          await widget.alCambiar();
                        }
                      },
              ),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(negocio.edificio == null ? 'Sin punto en el mapa' : 'Punto ${negocio.edificio}'),
                subtitle: const Text('Para cambiarlo, abre Mapa y toca el edificio donde vendes.'),
              ),
            ],
          ),
        ),
        _Seccion(
          titulo: 'Catálogo',
          accion: FilledButton.tonalIcon(
            onPressed: _ocupado ? null : () => _editarProducto(),
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
          children: [
            if (_cargando)
              const Padding(padding: EdgeInsets.all(Espacio.m), child: LinearProgressIndicator())
            else if (_productos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Espacio.m),
                child: Text('Todavía no publicas productos. Toca "Agregar" para crear el primero.'),
              )
            else
              for (final producto in _productos) _filaProducto(producto),
          ],
        ),
        _Seccion(
          titulo: 'Horario',
          children: [
            Row(
              children: [
                Expanded(child: _campoHora('Abre', _apertura, () => _elegirHora(apertura: true))),
                const SizedBox(width: Espacio.s),
                Expanded(child: _campoHora('Cierra', _cierre, () => _elegirHora(apertura: false))),
              ],
            ),
            separacion,
            Text(
              _dias.isEmpty ? 'Días de atención' : 'Días de atención: ${textoDeDias(_dias)}',
              style: tema.textTheme.labelLarge,
            ),
            const SizedBox(height: Espacio.s),
            SelectorDias(
              seleccion: _dias,
              habilitado: !_ocupado,
              alCambiar: (dias) => setState(() => _dias = dias),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _ocupado ? null : _guardarHorario,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar horario'),
              ),
            ),
          ],
        ),
        _Seccion(
          titulo: 'Contacto',
          children: [
            Text('Deja vacío un canal para ocultarlo.', style: TextStyle(color: tema.colorScheme.onSurfaceVariant)),
            separacion,
            TextField(
              controller: _whatsapp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp', prefixIcon: Icon(Icons.chat_outlined)),
            ),
            separacion,
            TextField(
              controller: _telegram,
              decoration: const InputDecoration(labelText: 'Telegram', prefixIcon: Icon(Icons.send_outlined)),
            ),
            separacion,
            TextField(
              controller: _instagram,
              decoration: const InputDecoration(labelText: 'Instagram', prefixIcon: Icon(Icons.camera_alt_outlined)),
            ),
            separacion,
            TextField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _ocupado ? null : _guardarContacto,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar contacto'),
              ),
            ),
          ],
        ),
        TarjetaEliminarCuenta(estado: widget.estado, vendedor: true),
      ],
    );
  }

  Widget _campoHora(String etiqueta, TimeOfDay? hora, VoidCallback alTocar) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: alTocar,
      child: InputDecorator(
        decoration: InputDecoration(labelText: etiqueta, prefixIcon: const Icon(Icons.schedule)),
        child: Text(hora == null ? 'Elegir' : _formatoHora(hora)),
      ),
    );
  }

  /// Fila con precio, agotado, edición y borrado.
  Widget _filaProducto(Producto producto) {
    final esquema = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: MiniaturaProducto(producto: producto),
      onTap: _ocupado ? null : () => _editarProducto(producto),
      title: Text(
        producto.nombre,
        style: producto.agotado ? TextStyle(color: esquema.onSurfaceVariant, decoration: TextDecoration.lineThrough) : null,
      ),
      subtitle: Text(producto.agotado ? '${producto.precioFormateado} · Agotado' : producto.precioFormateado),
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: producto.agotado ? 'Marcar disponible' : 'Marcar agotado',
            onPressed: _ocupado ? null : () => _alternarAgotado(producto),
            icon: Icon(producto.agotado ? Icons.inventory_2_outlined : Icons.remove_shopping_cart_outlined),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _ocupado ? null : () => _borrar(producto),
            icon: Icon(Icons.delete_outline, color: esquema.error),
          ),
        ],
      ),
    );
  }

  static TimeOfDay? _leerHora(String? texto) {
    final partes = (texto ?? '').split(':');
    if (partes.length < 2) {
      return null;
    }
    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);
    return hora == null || minuto == null ? null : TimeOfDay(hour: hora, minute: minuto);
  }

  /// `HH:mm` en 24 horas, el formato que exige la API.
  static String _formatoHora(TimeOfDay hora) =>
      '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
}

/// Tarjeta con título y acción opcional, para agrupar campos del panel.
class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.children, this.accion});

  final String titulo;
  final List<Widget> children;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Espacio.m),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
                  if (accion != null) accion!,
                ],
              ),
              const SizedBox(height: Espacio.s),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que devuelve [_DialogoProducto]: datos escritos y cambios de foto,
/// o la orden de eliminar el producto.
class _Edicion {
  const _Edicion(this.producto, {this.fotoNueva, this.quitarFoto = false, this.eliminar = false});

  final Producto producto;

  /// La persona tocó "Eliminar producto" dentro del formulario.
  final bool eliminar;

  /// JPEG ya comprimido para subir, o null si no se eligió otra foto.
  final Uint8List? fotoNueva;

  /// La persona quitó la foto que tenía.
  final bool quitarFoto;
}

/// Formulario de alta o edición de un producto, con fotografía.
class _DialogoProducto extends StatefulWidget {
  const _DialogoProducto({this.producto});

  /// Null para un producto nuevo.
  final Producto? producto;

  @override
  State<_DialogoProducto> createState() => _DialogoProductoState();
}

class _DialogoProductoState extends State<_DialogoProducto> {
  final _formulario = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.producto?.nombre);
  late final _precio = TextEditingController(text: widget.producto?.precio.toStringAsFixed(2));
  late final _descripcion = TextEditingController(text: widget.producto?.descripcion);
  Uint8List? _fotoNueva;
  bool _quitarFoto = false;
  bool _procesando = false;

  /// Abre la cámara ([ImageSource.camera]) o la galería / los archivos del
  /// dispositivo ([ImageSource.gallery]) y comprime la foto elegida.
  Future<void> _elegirFoto(ImageSource origen) async {
    final Uint8List? bytes;
    try {
      bytes = await (await ImagePicker().pickImage(source: origen))?.readAsBytes();
    } catch (_) {
      // Sin permiso de cámara o sin cámara disponible.
      if (mounted) {
        mostrarAviso(
          context,
          origen == ImageSource.camera
              ? 'No se pudo abrir la cámara. Revisa el permiso de cámara o elige una foto de la galería.'
              : 'No se pudo abrir la galería.',
        );
      }
      return;
    }
    if (bytes == null || !mounted) {
      return;
    }
    setState(() => _procesando = true);
    try {
      final comprimida = await comprimirFoto(bytes);
      if (mounted) {
        setState(() {
          _fotoNueva = comprimida;
          _quitarFoto = false;
        });
      }
    } catch (_) {
      if (mounted) {
        mostrarAviso(context, 'No se pudo leer esa imagen. Prueba con una foto JPG o PNG.');
      }
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  double? get _monto => double.tryParse(_precio.text.trim().replaceAll(',', '.').replaceAll(r'$', ''));

  void _aceptar() {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    final base = widget.producto ??
        Producto(
          id: '',
          sellerId: '',
          nombre: '',
          precio: 0,
          agotado: false,
          vecesVendido: 0,
          promedioEstrellas: 0,
          totalResenas: 0,
        );
    Navigator.pop(
      context,
      _Edicion(
        base.copyWith(nombre: _nombre.text.trim(), precio: _monto, descripcion: _descripcion.text.trim()),
        fotoNueva: _fotoNueva,
        quitarFoto: _quitarFoto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.producto == null ? 'Nuevo producto' : 'Editar producto'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formulario,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _foto(),
              const SizedBox(height: Espacio.m),
              TextFormField(
                controller: _nombre,
                autofocus: widget.producto == null,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: Validar.requerido,
              ),
              const SizedBox(height: Espacio.s),
              TextFormField(
                controller: _precio,
                decoration: const InputDecoration(labelText: 'Precio', prefixText: r'$ ', suffixText: 'MXN'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (_) {
                  final monto = _monto;
                  return monto == null || monto < 0 || monto > 999999 ? 'Escribe un precio válido' : null;
                },
              ),
              const SizedBox(height: Espacio.m),
              TextFormField(
                controller: _descripcion,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.producto != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: _procesando
                ? null
                : () => Navigator.pop(context, _Edicion(widget.producto!, eliminar: true)),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar producto'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _procesando ? null : _aceptar,
          child: Text(widget.producto == null ? 'Publicar' : 'Guardar'),
        ),
      ],
    );
  }

  /// Hay cámara que abrir: celulares y tabletas, en la app nativa o en el navegador.
  /// En escritorio la "cámara" del selector solo abriría otra vez los archivos.
  static bool get _hayCamara =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  /// Vista previa con botones para elegir (galería o cámara), cambiar o quitar la foto.
  Widget _foto() {
    final esquema = Theme.of(context).colorScheme;
    final actual = _quitarFoto ? null : widget.producto?.fotoUrl;
    final Widget vista;
    if (_procesando) {
      vista = const Center(child: CircularProgressIndicator());
    } else if (_fotoNueva != null) {
      vista = Image.memory(_fotoNueva!, fit: BoxFit.cover);
    } else if (actual != null) {
      vista = ImagenRed(actual, radio: 0);
    } else {
      vista = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 36, color: esquema.onSurfaceVariant),
          const SizedBox(height: Espacio.xs),
          Text('Agregar foto', style: TextStyle(color: esquema.onSurfaceVariant)),
        ],
      );
    }
    final tieneFoto = _fotoNueva != null || actual != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: esquema.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _procesando ? null : () => _elegirFoto(ImageSource.gallery),
            child: AspectRatio(aspectRatio: 16 / 10, child: vista),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _procesando ? null : () => _elegirFoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_hayCamara ? 'Galería' : 'Elegir archivo'),
            ),
            if (_hayCamara)
              TextButton.icon(
                onPressed: _procesando ? null : () => _elegirFoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Tomar foto'),
              ),
            if (tieneFoto)
              TextButton.icon(
                onPressed: _procesando
                    ? null
                    : () => setState(() {
                          _fotoNueva = null;
                          _quitarFoto = widget.producto?.fotoUrl != null;
                        }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar'),
              ),
          ],
        ),
      ],
    );
  }
}
