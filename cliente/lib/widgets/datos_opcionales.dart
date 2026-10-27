import 'package:flutter/material.dart';

import '../tema/tema_liebre.dart';

/// Carreras sugeridas en el campo "Carrera". La persona puede escribir
/// otra; la lista solo agiliza la captura. Ajústala a la oferta vigente.
const List<String> carrerasItcj = [
  'Contador Público',
  'Ingeniería Eléctrica',
  'Ingeniería Electrónica',
  'Ingeniería en Gestión Empresarial',
  'Ingeniería en Logística',
  'Ingeniería en Materiales',
  'Ingeniería en Sistemas Computacionales',
  'Ingeniería en Tecnologías de la Información y Comunicaciones',
  'Ingeniería Industrial',
  'Ingeniería Mecánica',
  'Ingeniería Mecatrónica',
  'Licenciatura en Administración',
];

/// Mensaje que explica para qué sirven los datos opcionales.
const String avisoDatosOpcionales =
    'Opcional. Los vendedores del plantel podrían usar estos datos para ofrecerte promociones y descuentos.';

/// Validaciones iguales a las del servidor (`Repositorio._datosOpcionales`).
class ValidarOpcional {
  const ValidarOpcional._();

  /// Vacío o 7–15 dígitos (admite espacios, guiones, paréntesis y +).
  static String? telefono(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) {
      return null;
    }
    final digitos = texto.replaceAll(RegExp(r'\D'), '').length;
    final caracteres = RegExp(r'^[0-9+\-() ]+$').hasMatch(texto);
    return caracteres && digitos >= 7 && digitos <= 15 ? null : 'Escribe entre 7 y 15 dígitos';
  }

  /// Vacío o 6–10 dígitos, con una letra inicial opcional (p. ej. C20111234).
  static String? numeroControl(String? valor) {
    final texto = (valor ?? '').trim().toUpperCase();
    if (texto.isEmpty) {
      return null;
    }
    return RegExp(r'^[A-Z]?\d{6,10}$').hasMatch(texto) ? null : 'De 6 a 10 dígitos; puede empezar con una letra';
  }
}

/// Teléfono, número de control y carrera, con el aviso de promociones.
///
/// Usar dentro de un `Form` para que se apliquen las validaciones.
class CamposOpcionales extends StatelessWidget {
  /// Los controladores los crea y libera quien usa el widget.
  const CamposOpcionales({
    super.key,
    required this.telefono,
    required this.numeroControl,
    required this.carrera,
    this.mostrarAviso = true,
  });

  /// Teléfono de contacto.
  final TextEditingController telefono;

  /// Número de control del ITCJ.
  final TextEditingController numeroControl;

  /// Carrera (texto libre con sugerencias).
  final TextEditingController carrera;

  /// Muestra el texto de promociones arriba de los campos.
  final bool mostrarAviso;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    const separacion = SizedBox(height: Espacio.m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mostrarAviso) ...[
          Container(
            padding: const EdgeInsets.all(Espacio.m),
            decoration: BoxDecoration(
              color: esquema.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.local_offer_outlined, color: esquema.onSecondaryContainer),
                const SizedBox(width: Espacio.m),
                Expanded(
                  child: Text(avisoDatosOpcionales, style: TextStyle(color: esquema.onSecondaryContainer)),
                ),
              ],
            ),
          ),
          separacion,
        ],
        TextFormField(
          controller: telefono,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.phone_outlined)),
          validator: ValidarOpcional.telefono,
        ),
        separacion,
        TextFormField(
          controller: numeroControl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Número de control (opcional)',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          validator: ValidarOpcional.numeroControl,
        ),
        separacion,
        LayoutBuilder(
          builder: (context, limites) => DropdownMenu<String>(
            controller: carrera,
            width: limites.maxWidth,
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 280,
            leadingIcon: const Icon(Icons.school_outlined),
            label: const Text('Carrera (opcional)'),
            dropdownMenuEntries: [
              for (final nombre in carrerasItcj) DropdownMenuEntry(value: nombre, label: nombre),
            ],
          ),
        ),
      ],
    );
  }
}
