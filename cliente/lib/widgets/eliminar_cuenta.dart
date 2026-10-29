import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/estado.dart';
import '../tema/tema_liebre.dart';

/// Tarjeta "Eliminar mi cuenta" (en "Mi negocio" y en "Mis datos").
///
/// Pide la contraseña, borra la cuenta en el servidor (`DELETE /api/yo`) con
/// todo lo suyo y regresa a la pantalla principal como invitado, donde se
/// puede crear otra cuenta. Un administrador no la ve: no puede borrarse.
class TarjetaEliminarCuenta extends StatelessWidget {
  /// [vendedor] ajusta el texto para mencionar negocio, fotos, precios y menú.
  const TarjetaEliminarCuenta({super.key, required this.estado, this.vendedor = false});

  /// Sesión que se va a borrar.
  final EstadoApp estado;

  /// La cuenta tiene un negocio.
  final bool vendedor;

  /// Advertencia que se muestra antes de borrar.
  static String advertencia({required bool vendedor}) => vendedor
      ? 'Si eliminas tu cuenta se perderán todos tus datos de usuario, tu negocio, las fotografías, '
          'los precios y el menú de tus productos, y sus reseñas. Esta acción no se puede deshacer. '
          'Después volverás al menú principal, donde podrás crear otra cuenta si lo necesitas.'
      : 'Si eliminas tu cuenta se perderán todos tus datos de usuario, tus favoritos y tus reseñas. '
          'Esta acción no se puede deshacer. Después volverás al menú principal, donde podrás crear '
          'otra cuenta si lo necesitas.';

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Espacio.m),
      child: Card(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: esquema.error.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Eliminar mi cuenta', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: esquema.error)),
              const SizedBox(height: Espacio.s),
              Text(
                vendedor
                    ? 'Borra tu cuenta, tu negocio y todos tus productos con sus fotos y precios.'
                    : 'Borra tu cuenta y todo lo que guardaste en ella.',
                style: TextStyle(color: esquema.onSurfaceVariant),
              ),
              const SizedBox(height: Espacio.m),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: esquema.error,
                    side: BorderSide(color: esquema.error),
                  ),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => DialogoEliminarCuenta(estado: estado, vendedor: vendedor),
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Eliminar mi cuenta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmación con contraseña. Al terminar cierra todas las páginas abiertas.
class DialogoEliminarCuenta extends StatefulWidget {
  /// Ver [TarjetaEliminarCuenta].
  const DialogoEliminarCuenta({super.key, required this.estado, required this.vendedor});

  /// Sesión que se va a borrar.
  final EstadoApp estado;

  /// Cambia el texto de la advertencia.
  final bool vendedor;

  @override
  State<DialogoEliminarCuenta> createState() => _DialogoEliminarCuentaState();
}

class _DialogoEliminarCuentaState extends State<DialogoEliminarCuenta> {
  final _password = TextEditingController();
  bool _entendido = false;
  bool _ocupado = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _eliminar() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    final navegador = Navigator.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await widget.estado.eliminarCuenta(_password.text);
      // Vuelve a la pantalla principal (Inicio) sin páginas encima.
      navegador.popUntil((ruta) => ruta.isFirst);
      mensajero
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Tu cuenta fue eliminada. Puedes crear otra desde "Entrar" cuando quieras.'),
        ));
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
    final listo = _entendido && _password.text.isNotEmpty && !_ocupado;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: esquema.error),
      title: const Text('¿Eliminar tu cuenta?'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(TarjetaEliminarCuenta.advertencia(vendedor: widget.vendedor)),
              const SizedBox(height: Espacio.m),
              TextField(
                controller: _password,
                obscureText: true,
                enabled: !_ocupado,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Tu contraseña',
                  helperText: 'Para confirmar que eres tú.',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _entendido,
                onChanged: _ocupado ? null : (valor) => setState(() => _entendido = valor ?? false),
                title: const Text('Entiendo que se borrará todo y no se puede recuperar.'),
              ),
              if (_error != null) Text(_error!, style: TextStyle(color: esquema.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: esquema.error, foregroundColor: esquema.onError),
          onPressed: listo ? _eliminar : null,
          child: _ocupado
              ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: esquema.onError))
              : const Text('Eliminar definitivamente'),
        ),
      ],
    );
  }
}
