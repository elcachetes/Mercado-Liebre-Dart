import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:mercado_liebre/modelos/modelos.dart';
import 'package:mercado_liebre/pantallas/busqueda_pantalla.dart';
import 'package:mercado_liebre/servicios/api.dart';
import 'package:mercado_liebre/servicios/estado.dart';
import 'package:mercado_liebre/servicios/imagenes.dart';
import 'package:mercado_liebre/tema/tema_liebre.dart';
import 'package:mercado_liebre/widgets/datos_opcionales.dart';
import 'package:mercado_liebre/widgets/selector_dias.dart';

ResultadoBusqueda resultado(String nombre, {double estrellas = 0, int resenas = 0}) {
  return ResultadoBusqueda(
    vendedor: Vendedor.fromJson({
      'id': nombre,
      'userId': 'u',
      'nombreNegocio': nombre,
      'categoria': 'comida',
      'disponible': true,
      'promedioEstrellas': estrellas,
      'totalResenas': resenas,
    }),
    productos: const [],
    coincidenciaExacta: false,
  );
}

List<String> nombres(List<ResultadoBusqueda> lista) => [for (final r in lista) r.vendedor.nombreNegocio];

void main() {
  group('días de atención', () {
    test('rango de lunes a viernes', () {
      expect(diasDesdeTexto('Lun-Vie'), {0, 1, 2, 3, 4});
      expect(textoDeDias({0, 1, 2, 3, 4}), 'Lun-Vie');
    });

    test('días sueltos y rangos mezclados', () {
      expect(textoDeDias({0, 2, 4}), 'Lun, Mié, Vie');
      expect(textoDeDias({0, 1, 2, 5, 6}), 'Lun-Mié, Sáb, Dom');
      expect(diasDesdeTexto('Lun-Mié, Sáb, Dom'), {0, 1, 2, 5, 6});
    });

    test('todos los días y texto escrito a mano', () {
      expect(textoDeDias({0, 1, 2, 3, 4, 5, 6}), 'Todos los días');
      expect(diasDesdeTexto('Todos los días'), hasLength(7));
      expect(diasDesdeTexto('lunes y miercoles'), {0, 2});
      expect(diasDesdeTexto('algo raro'), isEmpty);
    });

    test('ida y vuelta conserva la selección', () {
      for (final dias in [{1, 3}, {0, 1, 2, 3, 4, 5}, {6}, {4, 5, 6}]) {
        expect(diasDesdeTexto(textoDeDias(dias)), dias);
      }
    });
  });

  group('orden de la búsqueda', () {
    final lista = [
      resultado('Tacos', estrellas: 4.5, resenas: 2),
      resultado('Ángel Café'),
      resultado('Burritos', estrellas: 3, resenas: 10),
      resultado('Zumos', estrellas: 5, resenas: 1),
    ];

    test('relevancia respeta el orden del servidor', () {
      expect(nombres(ordenarResultados(lista, OrdenBusqueda.relevancia)), ['Tacos', 'Ángel Café', 'Burritos', 'Zumos']);
    });

    test('alfabético ignora acentos', () {
      expect(nombres(ordenarResultados(lista, OrdenBusqueda.nombre)), ['Ángel Café', 'Burritos', 'Tacos', 'Zumos']);
    });

    test('por estrellas: sin reseñas siempre al final', () {
      expect(nombres(ordenarResultados(lista, OrdenBusqueda.masEstrellas)), ['Zumos', 'Tacos', 'Burritos', 'Ángel Café']);
      expect(nombres(ordenarResultados(lista, OrdenBusqueda.menosEstrellas)), ['Burritos', 'Tacos', 'Zumos', 'Ángel Café']);
    });

    test('por número de reseñas', () {
      expect(nombres(ordenarResultados(lista, OrdenBusqueda.masResenas)), ['Burritos', 'Tacos', 'Zumos', 'Ángel Café']);
      expect(nombres(ordenarResultados(lista, OrdenBusqueda.menosResenas)), ['Ángel Café', 'Zumos', 'Tacos', 'Burritos']);
    });
  });

  group('datos opcionales', () {
    test('teléfono', () {
      expect(ValidarOpcional.telefono(''), isNull);
      expect(ValidarOpcional.telefono('656 123 4567'), isNull);
      expect(ValidarOpcional.telefono('+52 (656) 123-4567'), isNull);
      expect(ValidarOpcional.telefono('123'), isNotNull);
      expect(ValidarOpcional.telefono('abc1234567'), isNotNull);
    });

    test('número de control', () {
      expect(ValidarOpcional.numeroControl(''), isNull);
      expect(ValidarOpcional.numeroControl('20111234'), isNull);
      expect(ValidarOpcional.numeroControl('c20111234'), isNull);
      expect(ValidarOpcional.numeroControl('12'), isNotNull);
      expect(ValidarOpcional.numeroControl('20-111234'), isNotNull);
    });
  });

  testWidgets('comprimirFoto reduce una imagen grande a JPEG de 1280 px', (tester) async {
    final grande = Uint8List.fromList(img.encodePng(img.Image(width: 3000, height: 2000)));
    final comprimida = await tester.runAsync(() => comprimirFoto(grande));
    final leida = img.decodeJpg(comprimida!)!;
    expect(leida.width, 1280);
    expect(leida.height, 853);
  });

  testWidgets('la búsqueda abre mostrando lo disponible y filtra por categoría', (tester) async {
    final pedidas = <Uri>[];
    final api = ClienteApi(
      baseUrl: 'http://api',
      cliente: MockClient((peticion) async {
        pedidas.add(peticion.url);
        final categoria = peticion.url.queryParameters['categoria'];
        final lista = [
          if (categoria == null || categoria == 'comida')
            {
              'vendedor': {'id': '1', 'userId': 'u', 'nombreNegocio': 'Tacos Liebre', 'categoria': 'comida', 'disponible': true},
              'productos': [],
              'coincidenciaExacta': false,
            },
        ];
        return http.Response(jsonEncode(lista), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    await tester.pumpWidget(MaterialApp(
      theme: temaLiebre(Brightness.light),
      home: Scaffold(body: BusquedaPantalla(estado: EstadoApp(api: api))),
    ));
    await tester.pumpAndSettle();

    expect(pedidas.first.queryParameters['soloDisponibles'], 'true');
    expect(find.text('Tacos Liebre'), findsOneWidget);

    await tester.tap(find.text('Servicios'));
    await tester.pumpAndSettle();
    expect(pedidas.last.queryParameters['categoria'], 'servicio');
    expect(find.text('No hay vendedores de servicios abiertos en este momento'), findsOneWidget);
  });
}
