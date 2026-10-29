import 'package:flutter_test/flutter_test.dart';
import 'package:mercado_liebre/modelos/modelos.dart';
import 'package:mercado_liebre/pantallas/admin/admin_vendedores.dart';
import 'package:mercado_liebre/widgets/publicidad.dart';

void main() {
  group('intercalarAnuncios', () {
    test('sin resultados no hay anuncios', () {
      expect(intercalarAnuncios(0), isEmpty);
    });

    test('con pocos resultados el bloque va al final', () {
      expect(intercalarAnuncios(2), [0, 1, null]);
    });

    test('el primero va tras el tercero y luego uno cada seis', () {
      final orden = intercalarAnuncios(10);
      expect(orden, [0, 1, 2, null, 3, 4, 5, 6, 7, 8, null, 9]);
      // Todos los resultados aparecen una sola vez y en orden.
      expect(orden.whereType<int>(), List.generate(10, (i) => i));
    });
  });

  group('último uso de un negocio', () {
    final ahora = DateTime(2026, 10, 29, 12);

    Vendedor negocio(DateTime? ultimoAcceso) => Vendedor(
          id: 's1',
          userId: 'u1',
          nombreNegocio: 'Tacos',
          categoria: 'comida',
          horarioTexto: '',
          disponible: true,
          destacado: false,
          ultimoAcceso: ultimoAcceso,
        );

    test('texto por días de calendario', () {
      expect(textoUltimoUso(DateTime(2026, 10, 29, 8), ahora: ahora), 'Último uso: hoy');
      expect(textoUltimoUso(DateTime(2026, 10, 28, 23), ahora: ahora), 'Último uso: ayer');
      expect(textoUltimoUso(DateTime(2026, 10, 17), ahora: ahora), startsWith('Último uso: hace 12 días'));
      expect(textoUltimoUso(null, ahora: ahora), 'Último uso: sin registro');
    });

    test('inactivo desde $diasInactividad días o sin registro', () {
      expect(negocioInactivo(negocio(ahora.subtract(const Duration(days: 29))), ahora: ahora), isFalse);
      expect(negocioInactivo(negocio(ahora.subtract(const Duration(days: diasInactividad))), ahora: ahora), isTrue);
      expect(negocioInactivo(negocio(null), ahora: ahora), isTrue);
    });

    test('fromJson lee ultimoAcceso', () {
      final vendedor = Vendedor.fromJson({
        'id': 's1',
        'userId': 'u1',
        'nombreNegocio': 'Tacos',
        'categoria': 'comida',
        'ultimoAcceso': '2026-10-01T10:00:00.000Z',
      });
      expect(vendedor.ultimoAcceso, DateTime.utc(2026, 10, 1, 10).toLocal());
    });
  });
}
