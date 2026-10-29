import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercado_liebre/main.dart';
import 'package:mercado_liebre/modelos/modelos.dart';
import 'package:mercado_liebre/pantallas/sesion_dialogo.dart';
import 'package:mercado_liebre/servicios/api.dart';
import 'package:mercado_liebre/servicios/estado.dart';
import 'package:mercado_liebre/tema/tema_liebre.dart';
import 'package:mercado_liebre/widgets/eliminar_cuenta.dart';
import 'package:mercado_liebre/widgets/publicidad.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Negocio mínimo como lo manda la API.
Map<String, dynamic> negocioJson(String id, String nombre) =>
    {'id': id, 'userId': 'u$id', 'nombreNegocio': nombre, 'categoria': 'comida', 'disponible': true};

/// API falsa que anota cada petición (método, ruta y cuerpo).
MockClient apiFalsa({String rol = 'vendedor', List<Map<String, dynamic>>? peticiones}) {
  return MockClient((peticion) async {
    peticiones?.add({
      'metodo': peticion.method,
      'ruta': peticion.url.path,
      if (peticion.body.isNotEmpty) ...jsonDecode(peticion.body) as Map<String, dynamic>,
    });
    final Object? cuerpo = switch ((peticion.method, peticion.url.path)) {
      (_, '/api/apariencia') => <String, dynamic>{'titulo': 'Mercado Liebre'},
      (_, '/api/anuncios') => [
          {'seccion': 1, 'posicion': 1, 'imagenUrl': '/medios/a.jpg', 'vendedor': negocioJson('1', 'Tacos Liebre')},
        ],
      ('GET', '/api/yo') => {'id': 'u1', 'nombre': 'Ana', 'apellido': 'López', 'correo': 'ana@itcj.edu.mx', 'rol': rol},
      ('DELETE', '/api/yo') => <String, dynamic>{'ok': true},
      (_, '/api/vendedores/mio') => negocioJson('1', 'Tacos Liebre'),
      (_, '/api/favoritos' || '/api/vendedores' || '/api/productos') => <dynamic>[],
      (_, '/api/vendedores/destacados' || '/api/productos/mas-vendidos' || '/api/avisos') => <dynamic>[],
      _ => null,
    };
    if (cuerpo == null) {
      return http.Response(jsonEncode({'error': 'No existe'}), 404);
    }
    return http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

Future<EstadoApp> montar(WidgetTester tester, {bool conSesion = true, String rol = 'vendedor', List<Map<String, dynamic>>? peticiones}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({if (conSesion) 'token_sesion': 'token'});
  final estado = EstadoApp(api: ClienteApi(baseUrl: 'http://api', cliente: apiFalsa(rol: rol, peticiones: peticiones)));
  await tester.pumpWidget(MercadoLiebreApp(estado: estado));
  await tester.pumpAndSettle();
  return estado;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('un anuncio trae el negocio que abre', () {
    final anuncio = Anuncio.fromJson({
      'seccion': 2,
      'posicion': 3,
      'imagenUrl': '/medios/x.png',
      'vendedor': negocioJson('7', 'Copias Express'),
    });
    expect(anuncio.seccion, 2);
    expect(anuncio.posicion, 3);
    expect(anuncio.vendedor?.nombreNegocio, 'Copias Express');
    expect(Anuncio.fromJson({'seccion': 1, 'posicion': 1, 'imagenUrl': '/medios/y.png'}).vendedor, isNull);
  });

  testWidgets('el carrusel rota sus tres imágenes con la misma duración y abre el negocio visible', (tester) async {
    final abiertos = <String>[];
    final anuncios = [
      for (var i = 1; i <= 3; i++)
        Anuncio(
          seccion: 1,
          posicion: i,
          imagenUrl: '/medios/$i.jpg',
          vendedor: Vendedor.fromJson(negocioJson('$i', 'Negocio $i')),
        ),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: temaLiebre(Brightness.light),
      home: Center(
        child: SizedBox(
          width: 160,
          height: 300,
          child: EspacioPublicitario(
            anuncios: anuncios,
            duracion: const Duration(seconds: 2),
            alAbrirVendedor: (vendedor) => abiertos.add(vendedor.nombreNegocio),
          ),
        ),
      ),
    ));

    Future<void> tocar() async {
      await tester.tap(find.byType(EspacioPublicitario));
      await tester.pump();
    }

    await tocar();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tocar();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tocar();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tocar();
    expect(abiertos, ['Negocio 1', 'Negocio 2', 'Negocio 3', 'Negocio 1']);
    expect(find.bySemanticsLabel('Anuncio 2 de 3'), findsOneWidget);

    // Quita el carrusel para que su temporizador no quede pendiente.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la barra lateral toma los anuncios de la API', (tester) async {
    await montar(tester, conSesion: false);
    expect(find.byType(BarraPublicidad), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Anuncio de Tacos Liebre')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Espacio publicitario disponible')), findsOneWidget);
  });

  testWidgets('el registro avisa que el correo debe ser real y el login ofrece recuperar la contraseña', (tester) async {
    await montar(tester, conSesion: false);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(find.text(AvisoCorreoReal.texto), findsNothing);

    await tester.tap(find.text('Crear cuenta').last);
    await tester.pumpAndSettle();
    expect(find.text(AvisoCorreoReal.texto), findsOneWidget);
    expect(find.text('Correo real al que tengas acceso'), findsOneWidget);
  });

  testWidgets('el vendedor elimina su cuenta con contraseña y vuelve a Inicio como invitado', (tester) async {
    final peticiones = <Map<String, dynamic>>[];
    final estado = await montar(tester, peticiones: peticiones);

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi negocio'));
    await tester.pumpAndSettle();
    final eliminar = find.widgetWithText(OutlinedButton, 'Eliminar mi cuenta');
    await tester.ensureVisible(eliminar);
    await tester.pumpAndSettle();
    await tester.tap(eliminar);
    await tester.pumpAndSettle();

    expect(find.text(TarjetaEliminarCuenta.advertencia(vendedor: true)), findsOneWidget);
    final boton = find.widgetWithText(FilledButton, 'Eliminar definitivamente');
    expect(tester.widget<FilledButton>(boton).onPressed, isNull, reason: 'sin contraseña ni casilla no se puede');

    await tester.enterText(find.widgetWithText(TextField, 'Tu contraseña'), 'secreta123');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(peticiones.where((p) => p['metodo'] == 'DELETE').single, {'metodo': 'DELETE', 'ruta': '/api/yo', 'password': 'secreta123'});
    expect(estado.usuario, isNull);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('¿Qué se te antoja hoy?'), findsOneWidget);
  });

  testWidgets('el administrador abre su panel con todas las pestañas', (tester) async {
    await montar(tester, rol: 'admin');
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Administración'));
    await tester.pumpAndSettle();

    for (final pestana in ['Resumen', 'Usuarios', 'Negocios', 'Mapa', 'Publicidad', 'Contraseñas', 'Base de datos']) {
      expect(find.widgetWithText(Tab, pestana), findsOneWidget, reason: pestana);
    }
    // La API falsa no tiene /api/admin/resumen: la pestaña ofrece reintentar en vez de romperse.
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
