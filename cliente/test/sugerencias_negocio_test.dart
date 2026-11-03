import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercado_liebre/modelos/modelos.dart';
import 'package:mercado_liebre/pantallas/panel_negocio.dart';
import 'package:mercado_liebre/servicios/api.dart';
import 'package:mercado_liebre/servicios/estado.dart';
import 'package:mercado_liebre/widgets/datos_opcionales.dart';
import 'package:mercado_liebre/widgets/sugerencia_encontrar.dart';

Vendedor negocio({String categoria = 'comida', String? edificio, String? whatsapp, String? instagram}) =>
    Vendedor.fromJson({
      'id': 's1',
      'userId': 'u1',
      'nombreNegocio': 'Tacos Liebre',
      'categoria': categoria,
      'disponible': true,
      'edificio': edificio,
      'whatsapp': whatsapp,
      'instagram': instagram,
    });

/// Monta [PanelNegocio] con una API falsa que anota las peticiones.
Future<List<String>> montarPanel(WidgetTester tester, Vendedor vendedor) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final peticiones = <String>[];
  final api = ClienteApi(
    baseUrl: 'http://api',
    cliente: MockClient((peticion) async {
      peticiones.add('${peticion.method} ${peticion.url.path} ${peticion.body}');
      return http.Response(jsonEncode(peticion.method == 'GET' ? <dynamic>[] : <String, dynamic>{}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [PanelNegocio(estado: EstadoApp(api: api), negocio: vendedor, alCambiar: () async {})],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return peticiones;
}

void main() {
  test('comida y producto: piden lugar o, sin lugar fijo, contacto', () {
    for (final categoria in ['comida', 'producto']) {
      expect(faltaParaEncontrar(negocio(categoria: categoria)), FaltaParaEncontrar.lugarOContacto);
      expect(faltaParaEncontrar(negocio(categoria: categoria, whatsapp: '6561234567')), FaltaParaEncontrar.lugar);
      expect(faltaParaEncontrar(negocio(categoria: categoria, edificio: 'A')), isNull);
    }
  });

  test('servicio: pide teléfono o red social, aunque tenga lugar', () {
    expect(faltaParaEncontrar(negocio(categoria: 'servicio')), FaltaParaEncontrar.contacto);
    expect(faltaParaEncontrar(negocio(categoria: 'servicio', edificio: 'A')), FaltaParaEncontrar.contacto);
    expect(faltaParaEncontrar(negocio(categoria: 'servicio', instagram: 'liebre')), isNull);
    expect(consejoCategoria('servicio'), contains('teléfono o red social'));
    expect(consejoCategoria('comida'), contains('dónde vendes'));
  });

  test('la lista de carreras incluye Semiconductores y Ciberseguridad', () {
    expect(carrerasItcj, containsAll(['Ingeniería en Semiconductores', 'Ingeniería en Ciberseguridad']));
    expect(carrerasItcj.toSet().length, carrerasItcj.length);
  });

  testWidgets('Mi negocio de comida sin lugar ni contacto sugiere ambos y guarda el lugar elegido', (tester) async {
    final peticiones = await montarPanel(tester, negocio());
    expect(find.text('Ayuda a que te encuentren'), findsOneWidget);
    expect(find.text('Agregar contacto'), findsOneWidget);

    await tester.tap(find.text('Indicar lugar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Dónde vendes?'), findsOneWidget);
    await tester.tap(find.text('Edificio administrativo'));
    await tester.pumpAndSettle();
    expect(peticiones, contains('POST /api/vendedores/punto {"edificio":"A"}'));
  });

  testWidgets('Mi negocio de servicio sin contacto pide teléfono o red social', (tester) async {
    await montarPanel(tester, negocio(categoria: 'servicio'));
    expect(find.text('Ayuda a que te localicen'), findsOneWidget);
    expect(find.text('Indicar lugar'), findsNothing);

    await tester.tap(find.text('Agregar contacto'));
    await tester.pumpAndSettle();
    final whatsapp = tester.widget<TextField>(find.widgetWithText(TextField, 'WhatsApp'));
    expect(whatsapp.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Mi negocio con lugar y contacto no muestra sugerencias', (tester) async {
    await montarPanel(tester, negocio(edificio: 'A', whatsapp: '6561234567'));
    expect(find.byIcon(Icons.tips_and_updates_outlined), findsNothing);
    expect(find.textContaining('Edificio A'), findsOneWidget);
  });
}
