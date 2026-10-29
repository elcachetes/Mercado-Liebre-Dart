import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';
import '../widgets/comunes.dart';
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

/// Recuadro del registro que pide un correo real: sin verificarlo la cuenta
/// no califica ni comenta, y sin acceso a él no se recupera la contraseña.
class AvisoCorreoReal extends StatelessWidget {
  /// Sin parámetros.
  const AvisoCorreoReal({super.key});

  /// Texto del aviso; también lo buscan las pruebas.
  static const String texto = 'Usa un correo real, que exista y al que tengas acceso. Te enviaremos un enlace '
      'para verificarlo: sin verificarlo no podrás calificar ni comentar, y si olvidas tu contraseña solo '
      'podrás recuperarla desde ese correo.';

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Espacio.m),
      decoration: BoxDecoration(color: esquema.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mark_email_read_outlined, color: esquema.onTertiaryContainer),
          const SizedBox(width: Espacio.s),
          Expanded(child: Text(texto, style: TextStyle(color: esquema.onTertiaryContainer))),
        ],
      ),
    );
  }
}

/// Pide el correo y solicita el enlace para elegir una contraseña nueva.
class _OlvidoContrasena extends StatefulWidget {
  const _OlvidoContrasena({required this.estado, required this.correo});

  final EstadoApp estado;

  /// Lo que ya se escribió en el formulario de entrada.
  final String correo;

  @override
  State<_OlvidoContrasena> createState() => _OlvidoContrasenaState();
}

class _OlvidoContrasenaState extends State<_OlvidoContrasena> {
  final _formulario = GlobalKey<FormState>();
  late final _correo = TextEditingController(text: widget.correo.trim());
  bool _ocupado = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
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
      await widget.estado.api.olvideContrasena(_correo.text);
      if (mounted) {
        Navigator.pop(context);
        // El servidor no dice si la cuenta existe: el mensaje tampoco.
        mostrarAviso(
          context,
          'Si hay una cuenta con ese correo, te enviamos un enlace para elegir una contraseña nueva. '
          'Revisa también la carpeta de spam.',
        );
      }
    } on ErrorApi catch (error) {
      if (mounted) {
        setState(() {
          _error = error.mensaje;
          _ocupado = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Recuperar contraseña'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formulario,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Escribe el correo de tu cuenta. Te mandaremos un enlace que vence en una hora.',
                style: TextStyle(color: esquema.onSurfaceVariant),
              ),
              const SizedBox(height: Espacio.m),
              TextFormField(
                controller: _correo,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                validator: Validar.correo,
                onFieldSubmitted: (_) => _enviar(),
              ),
              if (_error != null) ...[
                const SizedBox(height: Espacio.m),
                Text(_error!, style: TextStyle(color: esquema.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _ocupado ? null : _enviar,
          child: _ocupado
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enviar enlace'),
        ),
      ],
    );
  }
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
      String? aviso;
      if (_registro) {
        final enviado = await widget.estado.registrar({
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
        // Sin verificar el correo la cuenta no califica ni comenta.
        aviso = enviado
            ? 'Cuenta creada. Te enviamos un enlace a ${_correo.text.trim()} para verificar tu correo.'
            : 'Cuenta creada, pero no pudimos enviar el correo de verificación. Pídelo de nuevo en "Mis datos".';
      } else {
        await widget.estado.entrar(_correo.text, _password.text);
      }
      if (mounted) {
        Navigator.pop(context);
        if (aviso != null) {
          mostrarAviso(context, aviso);
        }
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
                  if (_registro) ...[
                    const AvisoCorreoReal(),
                    const SizedBox(height: Espacio.s),
                  ],
                  TextFormField(
                    controller: _correo,
                    decoration: InputDecoration(
                      labelText: _registro ? 'Correo real al que tengas acceso' : 'Correo',
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
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
                  if (!_registro)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _ocupado
                            ? null
                            : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _OlvidoContrasena(estado: widget.estado, correo: _correo.text),
                                ),
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
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
