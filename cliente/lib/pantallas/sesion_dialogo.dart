import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/datos_opcionales.dart';

/// Muestra el formulario de entrada o de registro.
Future<void> mostrarDialogoSesion(BuildContext context, EstadoApp estado, {bool registro = false}) {
  return showDialog<void>(
    context: context,
    builder: (contexto) => _FormularioSesion(estado: estado, registroInicial: registro),
  );
}

/// Categorías de negocio que acepta la API: (valor, etiqueta).
const List<(String, String)> categoriasNegocio = [
  ('comida', 'Comida'),
  ('producto', 'Producto'),
  ('servicio', 'Servicio'),
];

/// Validaciones de formulario compartidas con el panel de administración.
class Validar {
  const Validar._();

  /// Campo obligatorio.
  static String? requerido(String? valor) => (valor ?? '').trim().isEmpty ? 'Campo obligatorio' : null;

  /// Correo con @ y punto, igual que la regla del servidor.
  static String? correo(String? valor) {
    final texto = (valor ?? '').trim();
    return texto.contains('@') && texto.contains('.') ? null : 'Escribe un correo válido';
  }

  /// Mínimo 8 caracteres, igual que la regla del servidor.
  static String? password(String? valor) => (valor ?? '').length < 8 ? 'Mínimo 8 caracteres' : null;
}

class _FormularioSesion extends StatefulWidget {
  const _FormularioSesion({required this.estado, required this.registroInicial});

  final EstadoApp estado;
  final bool registroInicial;

  @override
  State<_FormularioSesion> createState() => _FormularioSesionState();
}

class _FormularioSesionState extends State<_FormularioSesion> {
  final _formulario = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _password = TextEditingController();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _negocio = TextEditingController();
  final _telefono = TextEditingController();
  final _numeroControl = TextEditingController();
  final _carrera = TextEditingController();
  late bool _registro = widget.registroInicial;
  bool _vendedor = false;
  bool _verPassword = false;
  String _categoria = 'comida';
  String? _error;
  bool _ocupado = false;

  @override
  void dispose() {
    for (final campo in [_correo, _password, _nombre, _apellido, _negocio, _telefono, _numeroControl, _carrera]) {
      campo.dispose();
    }
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_ocupado || !(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      if (_registro) {
        await widget.estado.registrar({
          'nombre': _nombre.text,
          'apellido': _apellido.text,
          'correo': _correo.text,
          'password': _password.text,
          'rol': _vendedor ? 'vendedor' : 'comprador',
          'telefono': _telefono.text,
          'numeroControl': _numeroControl.text,
          'carrera': _carrera.text,
          if (_vendedor) 'nombreNegocio': _negocio.text,
          if (_vendedor) 'categoria': _categoria,
        });
      } else {
        await widget.estado.entrar(_correo.text, _password.text);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() => _error = error.mensaje);
      }
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    const separacion = SizedBox(height: Espacio.m);
    return AlertDialog(
      title: Text(_registro ? 'Crear cuenta' : 'Iniciar sesión'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formulario,
          child: AutofillGroup(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _registro
                        ? 'Crea tu cuenta para calificar, guardar favoritos o vender en el plantel.'
                        : 'Entra para calificar, comentar y guardar tus vendedores favoritos.',
                    style: TextStyle(color: esquema.onSurfaceVariant),
                  ),
                  separacion,
                  if (_registro) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nombre,
                            decoration: const InputDecoration(labelText: 'Nombre'),
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.givenName],
                            textInputAction: TextInputAction.next,
                            validator: Validar.requerido,
                          ),
                        ),
                        const SizedBox(width: Espacio.s),
                        Expanded(
                          child: TextFormField(
                            controller: _apellido,
                            decoration: const InputDecoration(labelText: 'Apellido'),
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.familyName],
                            textInputAction: TextInputAction.next,
                            validator: Validar.requerido,
                          ),
                        ),
                      ],
                    ),
                    separacion,
                  ],
                  TextFormField(
                    controller: _correo,
                    decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: Validar.correo,
                  ),
                  separacion,
                  TextFormField(
                    controller: _password,
                    obscureText: !_verPassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _verPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                        onPressed: () => setState(() => _verPassword = !_verPassword),
                        icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                    autofillHints: [_registro ? AutofillHints.newPassword : AutofillHints.password],
                    textInputAction: _registro && _vendedor ? TextInputAction.next : TextInputAction.done,
                    onFieldSubmitted: (_) => _enviar(),
                    validator: _registro ? Validar.password : Validar.requerido,
                  ),
                  if (_registro) ...[
                    const SizedBox(height: Espacio.s),
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        maintainState: true,
                        leading: const Icon(Icons.local_offer_outlined),
                        title: const Text('Teléfono, número de control y carrera'),
                        subtitle: const Text('Opcional · para recibir promociones'),
                        childrenPadding: const EdgeInsets.fromLTRB(Espacio.m, 0, Espacio.m, Espacio.m),
                        children: [
                          CamposOpcionales(
                            telefono: _telefono,
                            numeroControl: _numeroControl,
                            carrera: _carrera,
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _vendedor,
                      title: const Text('Quiero vender en el plantel'),
                      onChanged: (valor) => setState(() => _vendedor = valor),
                    ),
                    if (_vendedor) ...[
                      TextFormField(
                        controller: _negocio,
                        decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                        validator: Validar.requerido,
                      ),
                      separacion,
                      DropdownButtonFormField<String>(
                        initialValue: _categoria,
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        items: [
                          for (final (valor, etiqueta) in categoriasNegocio)
                            DropdownMenuItem(value: valor, child: Text(etiqueta)),
                        ],
                        onChanged: (valor) => setState(() => _categoria = valor ?? 'comida'),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    separacion,
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Espacio.m),
                      decoration: BoxDecoration(
                        color: esquema.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!, style: TextStyle(color: esquema.onErrorContainer)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actionsOverflowButtonSpacing: Espacio.s,
      actions: [
        TextButton(
          onPressed: _ocupado
              ? null
              : () => setState(() {
                    _registro = !_registro;
                    _error = null;
                  }),
          child: Text(_registro ? 'Ya tengo cuenta' : 'Crear cuenta'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _ocupado ? null : _enviar,
          child: _ocupado
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_registro ? 'Registrarme' : 'Entrar'),
        ),
      ],
    );
  }
}
