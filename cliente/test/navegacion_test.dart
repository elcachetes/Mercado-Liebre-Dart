import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercado_liebre/main.dart';
import 'package:mercado_liebre/modelos/modelos.dart';
import 'package:mercado_liebre/pantallas/detalle_producto.dart';
import 'package:mercado_liebre/servicios/api.dart';
import 'package:mercado_liebre/servicios/estado.dart';
import 'package:mercado_liebre/widgets/publicidad.dart';
import 'package:mercado_liebre/widgets/reporte_dialogo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cuenta de ejemplo como la devuelve `GET /api/yo`.
Map<String, dynamic> usuarioJson({bool verificado = true, String rol = 'comprador'}) => {
      'id': 'u1',
      'nombre': 'Ana',
      'apellido': 'López',
      'correo': 'ana@itcj.edu.mx',
      'rol': rol,
      'correoVerificado': verificado,
    };

/// API falsa: responde según la ruta y guarda los cuerpos de los POST.
MockClient apiFalsa({Map<String, dynamic>? usuario, List<Map<String, dynamic>>? enviados}) {
  return MockClient((peticion) async {
    if (peticion.method == 'POST') {
      enviados?.add({'ruta': peticion.url.path, ...jsonDecode(peticion.body) as Map<String, dynamic>});
    }
    final Object? cuerpo = switch (peticion.url.path) {
      '/api/apariencia' => <String, dynamic>{'titulo': 'Mercado Liebre'},
      '/api/yo' => usuario,
      '/api/favoritos' || '/api/vendedores' || '/api/calificaciones' => <dynamic>[],
      '/api/vendedores/destacados' || '/api/productos/mas-vendidos' || '/api/avisos' => <dynamic>[],
      '/api/reportes' => <String, dynamic>{'ok': true},
      _ => null,
    };
    if (cuerpo == null) {
      return http.Response(jsonEncode({'error': 'No existe'}), 404);
    }
    return http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

/// Monta la app con un tamaño de pantalla dado. Con [usuario] arranca con sesión.
Future<EstadoApp> montar(
  WidgetTester tester, {
  Size tamano = const Size(1280, 800),
  Map<String, dynamic>? usuario,
  List<Map<String, dynamic>>? enviados,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({if (usuario != null) 'token_sesion': 'token'});
  final estado = EstadoApp(api: ClienteApi(baseUrl: 'http://api', cliente: apiFalsa(usuario: usuario, enviados: enviados)));
  await tester.pumpWidget(MercadoLiebreApp(estado: estado));
  await tester.pumpAndSettle();
  return estado;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('barra superior', () {
    testWidgets('en pantalla amplia lleva las pestañas con texto y la publicidad a un lado', (tester) async {
      await montar(tester);

      final barra = find.byType(AppBar);
      expect(find.descendant(of: barra, matching: find.text('Inicio')), findsOneWidget);
      expect(find.descendant(of: barra, matching: find.text('Búsqueda')), findsOneWidget);
      expect(find.descendant(of: barra, matching: find.text('Mapa')), findsOneWidget);
      expect(find.descendant(of: barra, matching: find.text('Reportar')), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(EspacioPublicitario), findsNWidgets(2));
      expect(tester.getSize(find.byType(BarraPublicidad)).width, anchoBarraPublicidad);
    });

    testWidgets('en el celular no hay barra inferior ni publicidad y nada se desborda', (tester) async {
      await montar(tester, tamano: const Size(360, 740), usuario: usuarioJson());

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BarraPublicidad), findsNothing);
      expect(find.byTooltip('Mapa'), findsOneWidget);
      expect(find.byTooltip('Reportar falla, queja o sugerencia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la liebre regresa a Inicio desde otra pestaña', (tester) async {
      await montar(tester);

      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Mapa')));
      await tester.pumpAndSettle();
      expect(find.text('Edificios y lugares'), findsOneWidget);

      await tester.tap(find.byTooltip('Ir a Inicio'));
      await tester.pumpAndSettle();
      expect(find.text('Abiertos ahora'), findsWidgets);
      expect(find.text('Edificios y lugares'), findsNothing);
    });
  });

  group('cuenta', () {
    testWidgets('ya no hay pestaña Perfil: el nombre abre el menú con las secciones', (tester) async {
      await montar(tester, usuario: usuarioJson(rol: 'admin'));

      expect(find.text('Perfil'), findsNothing);
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();

      for (final opcion in ['Mis datos', 'Favoritos', 'Administración', 'Moderación', 'Cerrar sesión']) {
        expect(find.text(opcion), findsOneWidget, reason: opcion);
      }
      expect(find.text('Mi negocio'), findsNothing);

      await tester.tap(find.text('Mis datos'));
      await tester.pumpAndSettle();
      expect(find.text('ana@itcj.edu.mx'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('una cuenta sin verificar ve el aviso en lugar del formulario de calificación', (tester) async {
      final estado = await montar(tester, usuario: usuarioJson(verificado: false));
      final producto = Producto(
        id: 'p1',
        sellerId: 's1',
        nombre: 'Burrito',
        precio: 30,
        agotado: false,
        vecesVendido: 0,
        promedioEstrellas: 0,
        totalResenas: 0,
      );
      abrirProducto(tester.element(find.byType(Scaffold).first), estado, producto);
      await tester.pumpAndSettle();

      expect(find.text('Verifica tu correo para calificar y comentar productos.'), findsOneWidget);
      expect(find.text('Reenviar correo'), findsOneWidget);
      expect(find.text('Publicar'), findsNothing);
    });
  });

  group('mapa', () {
    testWidgets('plano y leyenda en dos marcos; la leyenda es texto de la app', (tester) async {
      await montar(tester);
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Mapa')));
      await tester.pumpAndSettle();

      // La lista se construye al desplazarse: basta con el primer lugar.
      expect(find.text('Edificio administrativo'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final plano = tester.getSize(find.byType(InteractiveViewer));
      final leyenda = tester.getSize(find.byType(GridView));
      // Lado a lado, con el mismo ancho (salvo el encabezado propio de la leyenda).
      expect((plano.width - leyenda.width).abs(), lessThan(1));
    });
  });

  group('reporte', () {
    test('el contacto acepta correo o número de control', () {
      expect(validarContactoReporte('ana@itcj.edu.mx'), isNull);
      expect(validarContactoReporte('c20111234'), isNull);
      expect(validarContactoReporte(''), isNotNull);
      expect(validarContactoReporte('ana'), isNotNull);
    });

    testWidgets('exige descripción, se puede cancelar y envía lo escrito', (tester) async {
      final enviados = <Map<String, dynamic>>[];
      await montar(tester, enviados: enviados);

      await tester.tap(find.text('Reportar'));
      await tester.pumpAndSettle();
      expect(find.text('Adjuntar foto (opcional)'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(FormularioReporte), findsNothing);

      await tester.tap(find.text('Reportar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Correo electrónico o número de control'), '20111234');
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();
      expect(find.text('Cuéntanos qué pasó (mínimo 10 caracteres)'), findsOneWidget);
      expect(enviados, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Describe brevemente el problema'),
        'El mapa no carga en mi celular.',
      );
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      expect(enviados.single, {
        'ruta': '/api/reportes',
        'contacto': '20111234',
        'descripcion': 'El mapa no carga en mi celular.',
      });
      expect(find.byType(FormularioReporte), findsNothing);
      expect(find.text('Gracias. Recibimos tu reporte y lo revisaremos pronto.'), findsOneWidget);
    });
  });
}
