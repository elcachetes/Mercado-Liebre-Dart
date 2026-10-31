import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercado_liebre/main.dart';
import 'package:mercado_liebre/modelos/modelos.dart';
import 'package:mercado_liebre/pantallas/detalle_producto.dart';
import 'package:mercado_liebre/pantallas/detalle_vendedor.dart';
import 'package:mercado_liebre/servicios/api.dart';
import 'package:mercado_liebre/servicios/estado.dart';
import 'package:mercado_liebre/tema/tema_liebre.dart';
import 'package:mercado_liebre/widgets/compartir.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> cuentaJson(String rol) =>
    {'id': 'u1', 'nombre': 'Ana', 'apellido': 'López', 'correo': 'ana@itcj.edu.mx', 'rol': rol};

Map<String, dynamic> negocioJson() => {
      'id': 's1',
      'userId': 'u9',
      'nombreNegocio': 'Tacos Liebre',
      'categoria': 'comida',
      'disponible': true,
      'logoUrl': '/medios/logo.jpg',
      'portadaUrl': '/medios/tienda.jpg',
    };

Map<String, dynamic> productoJson() =>
    {'id': 'p1', 'sellerId': 's1', 'nombre': 'Taco de asada', 'precio': 25, 'agotado': false};

/// API falsa: la cuenta empieza con [rol] y `POST /api/yo/modo` la cambia.
MockClient apiFalsa({required String rol, List<Map<String, dynamic>>? peticiones}) {
  var rolActual = rol;
  return MockClient((peticion) async {
    final cuerpoPeticion =
        peticion.body.isEmpty ? <String, dynamic>{} : jsonDecode(peticion.body) as Map<String, dynamic>;
    peticiones?.add({'metodo': peticion.method, 'ruta': peticion.url.path, ...cuerpoPeticion});
    final Object? cuerpo = switch ((peticion.method, peticion.url.path)) {
      (_, '/api/apariencia') => <String, dynamic>{'titulo': 'Mercado Liebre'},
      ('GET', '/api/yo') => cuentaJson(rolActual),
      ('POST', '/api/yo/modo') => cuentaJson(rolActual = cuerpoPeticion['modo'] as String),
      // Una cuenta de usuario que nunca vendió no tiene negocio en pausa.
      (_, '/api/vendedores/mio') => rolActual == 'vendedor' ? negocioJson() : null,
      (_, '/api/vendedores/s1') => negocioJson(),
      (_, '/api/productos/p1') => productoJson(),
      (_, '/api/anuncios' || '/api/favoritos' || '/api/vendedores' || '/api/productos') => <dynamic>[],
      (_, '/api/vendedores/destacados' || '/api/productos/mas-vendidos' || '/api/avisos') => <dynamic>[],
      (_, '/api/calificaciones') => <dynamic>[],
      _ => null,
    };
    if (cuerpo == null) {
      return http.Response(jsonEncode({'error': 'No existe'}), 404);
    }
    return http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

Future<EstadoApp> montar(WidgetTester tester, {required String rol, List<Map<String, dynamic>>? peticiones}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'token_sesion': 'token'});
  final estado = EstadoApp(api: ClienteApi(baseUrl: 'http://api', cliente: apiFalsa(rol: rol, peticiones: peticiones)));
  await tester.pumpWidget(MercadoLiebreApp(estado: estado));
  await tester.pumpAndSettle();
  return estado;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el negocio trae logo y foto de la tienda; la reseña, su aprobación', () {
    final negocio = Vendedor.fromJson(negocioJson());
    expect(negocio.logoUrl, '/medios/logo.jpg');
    expect(negocio.portadaUrl, '/medios/tienda.jpg');

    final pendiente = ResenaAdmin.fromJson({
      'productoId': 'p1',
      'autorId': 'u2',
      'aprobada': false,
      'negocioAutor': 'Tortas Rivales',
    });
    expect(pendiente.aprobada, isFalse);
    expect(pendiente.negocioAutor, 'Tortas Rivales');
    // Respuestas de una API anterior (sin el campo) cuentan como aprobadas.
    expect(ResenaAdmin.fromJson({'productoId': 'p1', 'autorId': 'u2'}).aprobada, isTrue);

    expect(Calificacion.fromJson({'estrellas': 5, 'nombre': 'Ana', 'fotoPerfilUrl': '/medios/a.jpg'}).fotoPerfilUrl,
        '/medios/a.jpg');
  });

  test('solo usuario y vendedor pueden cambiar de modo', () {
    Usuario cuenta(String rol) => Usuario.fromJson(cuentaJson(rol));
    expect(cuenta('comprador').puedeCambiarModo, isTrue);
    expect(cuenta('vendedor').puedeCambiarModo, isTrue);
    expect(cuenta('moderador').puedeCambiarModo, isFalse);
    expect(cuenta('admin').puedeCambiarModo, isFalse);
  });

  test('los enlaces para compartir abren la ficha y se codifican para Facebook y Telegram', () {
    final enlace = enlaceProducto(Producto.fromJson(productoJson()));
    expect(enlace.queryParameters, {'producto': 'p1'});
    expect(enlaceVendedor(Vendedor.fromJson(negocioJson())).queryParameters, {'vendedor': 's1'});

    final facebook = enFacebook(enlace);
    expect(facebook.host, 'www.facebook.com');
    expect(facebook.queryParameters['u'], '$enlace');

    final telegram = enTelegram(enlace, 'Taco de asada & más');
    expect(telegram.host, 't.me');
    expect(telegram.queryParameters, {'url': '$enlace', 'text': 'Taco de asada & más'});
  });

  testWidgets('un usuario pasa a modo vendedor desde el menú de la cuenta', (tester) async {
    final peticiones = <Map<String, dynamic>>[];
    final estado = await montar(tester, rol: 'comprador', peticiones: peticiones);

    await tester.tap(find.byTooltip('Mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Mi negocio'), findsNothing);
    await tester.tap(find.text('Cambiar a modo vendedor'));
    await tester.pumpAndSettle();

    // Sin negocio en pausa pide los datos del nuevo.
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre del negocio'), 'Tacos Ana');
    await tester.tap(find.widgetWithText(FilledButton, 'Cambiar a modo vendedor'));
    await tester.pumpAndSettle();

    final cambio = peticiones.singleWhere((p) => p['ruta'] == '/api/yo/modo');
    expect(cambio['modo'], 'vendedor');
    expect(cambio['nombreNegocio'], 'Tacos Ana');
    expect(cambio['categoria'], 'comida');
    expect(estado.usuario!.esVendedor, isTrue);

    await tester.tap(find.byTooltip('Mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Mi negocio'), findsOneWidget);
    expect(find.text('Cambiar a modo usuario'), findsOneWidget);
  });

  testWidgets('un vendedor vuelve a modo usuario tras confirmar', (tester) async {
    final peticiones = <Map<String, dynamic>>[];
    final estado = await montar(tester, rol: 'vendedor', peticiones: peticiones);

    await tester.tap(find.byTooltip('Mi cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar a modo usuario'));
    await tester.pumpAndSettle();
    expect(find.textContaining('quedará en pausa'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cambiar'));
    await tester.pumpAndSettle();

    expect(peticiones.singleWhere((p) => p['ruta'] == '/api/yo/modo')['modo'], 'comprador');
    expect(estado.usuario!.esVendedor, isFalse);
  });

  testWidgets('un enlace compartido de producto abre su negocio y el producto encima', (tester) async {
    final estado = await montar(tester, rol: 'comprador');
    final contexto = tester.element(find.byType(Scaffold).first);

    expect(await abrirEnlaceCompartido(contexto, estado, Uri.parse('https://mercado/')), isFalse);
    abrirEnlaceCompartido(contexto, estado, Uri.parse('https://mercado/?producto=p1'));
    await tester.pumpAndSettle();

    expect(find.byType(DetalleVendedorPantalla), findsOneWidget);
    expect(find.text('Taco de asada'), findsWidgets);
    expect(find.byTooltip('Compartir producto'), findsOneWidget);
  });

  testWidgets('al calificar, un vendedor ve que su reseña pasa por la administración', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final estado = EstadoApp(api: ClienteApi(baseUrl: 'http://api', cliente: apiFalsa(rol: 'vendedor')))
      ..usuario = Usuario.fromJson(cuentaJson('vendedor'));
    await tester.pumpWidget(MaterialApp(
      theme: temaLiebre(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => abrirProducto(context, estado, Producto.fromJson(productoJson())),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text(textoResenaVendedor), findsOneWidget);
  });
}
