import 'package:flutter/material.dart';

import '../tema/tema_liebre.dart';

/// Abreviaturas de los días, de lunes (0) a domingo (6).
const List<String> nombresDias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// Convierte el texto guardado ("Lun-Vie", "Lun, Mié, Vie", "Todos los días")
/// en los índices de [nombresDias]. Entiende texto escrito a mano antes de
/// que existiera este selector; lo que no reconoce lo ignora.
Set<int> diasDesdeTexto(String texto) {
  final limpio = _sinAcentos(texto.toLowerCase());
  if (limpio.contains('todos')) {
    return {for (var i = 0; i < 7; i++) i};
  }
  int? indice(String parte) {
    final clave = _sinAcentos(parte.trim().toLowerCase());
    for (var i = 0; i < 7; i++) {
      if (clave.startsWith(_sinAcentos(nombresDias[i].toLowerCase()))) {
        return i;
      }
    }
    return null;
  }

  final dias = <int>{};
  for (final tramo in limpio.split(RegExp(r',| y '))) {
    final extremos = tramo.split('-');
    final inicio = indice(extremos.first);
    final fin = extremos.length > 1 ? indice(extremos.last) : inicio;
    if (inicio == null || fin == null) {
      continue;
    }
    for (var i = inicio; ; i = (i + 1) % 7) {
      dias.add(i);
      if (i == fin) {
        break;
      }
    }
  }
  return dias;
}

/// Texto corto para guardar: rangos de 3 o más días seguidos con guion
/// ("Lun-Vie"), los demás separados por coma ("Lun-Mié, Sáb").
String textoDeDias(Set<int> dias) {
  if (dias.length == 7) {
    return 'Todos los días';
  }
  final orden = dias.toList()..sort();
  final partes = <String>[];
  var i = 0;
  while (i < orden.length) {
    var j = i;
    while (j + 1 < orden.length && orden[j + 1] == orden[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      partes.add('${nombresDias[orden[i]]}-${nombresDias[orden[j]]}');
    } else {
      partes.addAll([for (var k = i; k <= j; k++) nombresDias[orden[k]]]);
    }
    i = j + 1;
  }
  return partes.join(', ');
}

String _sinAcentos(String texto) =>
    texto.replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u');

/// Un chip por día, más atajos "Lun-Vie", "Lun-Sáb" y "Todos".
class SelectorDias extends StatelessWidget {
  /// [seleccion] usa los índices de [nombresDias].
  const SelectorDias({super.key, required this.seleccion, required this.alCambiar, this.habilitado = true});

  /// Días marcados.
  final Set<int> seleccion;

  /// Recibe el conjunto nuevo.
  final ValueChanged<Set<int>> alCambiar;

  /// Falso mientras se guarda.
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    Set<int> rango(int fin) => {for (var i = 0; i <= fin; i++) i};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Espacio.xs,
          runSpacing: Espacio.xs,
          children: [
            for (var i = 0; i < 7; i++)
              FilterChip(
                label: Text(nombresDias[i]),
                selected: seleccion.contains(i),
                showCheckmark: false,
                onSelected: habilitado
                    ? (marcado) => alCambiar(marcado ? {...seleccion, i} : ({...seleccion}..remove(i)))
                    : null,
              ),
          ],
        ),
        const SizedBox(height: Espacio.xs),
        Wrap(
          spacing: Espacio.s,
          children: [
            for (final (etiqueta, dias) in [('Lun-Vie', rango(4)), ('Lun-Sáb', rango(5)), ('Todos', rango(6))])
              ActionChip(
                avatar: const Icon(Icons.bolt, size: 16),
                label: Text(etiqueta),
                visualDensity: VisualDensity.compact,
                onPressed: habilitado ? () => alCambiar(dias) : null,
              ),
          ],
        ),
      ],
    );
  }
}
