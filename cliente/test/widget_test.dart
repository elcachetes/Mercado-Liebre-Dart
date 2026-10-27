import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercado_liebre/main.dart';
import 'package:mercado_liebre/mapa/puntos_campus.dart';
import 'package:mercado_liebre/modelos/modelos.dart';
import 'package:mercado_liebre/servicios/api.dart';
import 'package:mercado_liebre/servicios/estado.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vendedor de ejemplo con los campos que devuelve la API.
Map<String, dynamic> vendedorJson({String id = '1', bool disponible = true}) => {
      'id': id,
      'userId': '9',
      'nombreNegocio': 'Taller del Nodo',
      'categoria': 'servicio',
      'disponible': disponible,
      'edificio': 'Z',
      'horarioTexto': 'Lun-Vie · 08:00 - 14:00',
      'whatsapp': '6561234567',
    };

/// API falsa: responde según la ruta, sin red.
MockClient apiFalsa({List<Map<String, dynamic>>? vendedores}) {
  return MockClient((peticion) async {
    final cuerpo = switch (peticion.url.path) {
      '/api/apariencia' => <String, dynamic>{'titulo': 'Mercado Liebre'},
      '/api/vendedores' => vendedores ?? [vendedorJson()],
      '/api/vendedores/destacados' || '/api/productos/mas-vendidos' || '/api/avisos' => <dynamic>[],
      _ => null,
    };
    if (cuerpo == null) {
      return http.Response(jsonEncode({'error': 'No existe'}), 404);
    }
    return http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('modelos', () {
    test('el plano del plantel incluye el edificio Z', () {
      final punto = puntoPorCodigo('z');
      expect(punto, isNotNull);
      expect(punto!.nombre, 'Nodo de Creatividad y Emprendimiento');
    });

    test('un vendedor se reconstruye desde el JSON de la API', () {
      final vendedor = Vendedor.fromJson(vendedorJson());
      expect(vendedor.nombreNegocio, 'Taller del Nodo');
      expect(vendedor.edificio, 'Z');
      expect(vendedor.contactos, [('WhatsApp', '6561234567')]);
    });

    test('copyWith conserva lo que no cambia', () {
      final producto = Producto(
        id: 'p',
        sellerId: 's',
        nombre: 'Café',
        precio: 20,
        agotado: false,
        vecesVendido: 3,
        promedioEstrellas: 4.5,
        totalResenas: 2,
      );
      final agotado = producto.copyWith(agotado: true);
      expect(agotado.agotado, isTrue);
      expect(agotado.nombre, 'Café');
      expect(agotado.vecesVendido, 3);
    });
  });

  group('ClienteApi', () {
    test('convierte el campo "error" de la API en ErrorApi con su código', () async {
      final api = ClienteApi(
        baseUrl: 'http://api',
        cliente: MockClient((_) async => http.Response('{"error":"Correo o contraseña incorrectos."}', 401)),
      );
      expect(
        () => api.iniciarSesion('a@b.c', 'x'),
        throwsA(isA<ErrorApi>()
            .having((e) => e.estado, 'estado', 401)
            .having((e) => e.mensaje, 'mensaje', 'Correo o contraseña incorrectos.')),
      );
    });

    test('un 502 sin JSON da un mensaje genérico, no una excepción de formato', () async {
      final api = ClienteApi(baseUrl: 'http://api', cliente: MockClient((_) async => http.Response('<html>', 502)));
      expect(() => api.avisos(), throwsA(isA<ErrorApi>().having((e) => e.estado, 'estado', 502)));
    });

    test('sin red lanza ErrorApi con estado 0', () async {
      final api = ClienteApi(
        baseUrl: 'http://api',
        cliente: MockClient((_) async => throw http.ClientException('sin red')),
      );
      expect(() => api.avisos(), throwsA(isA<ErrorApi>().having((e) => e.sinConexion, 'sinConexion', isTrue)));
    });

    test('miNegocio devuelve null con 404', () async {
      final api = ClienteApi(
        baseUrl: 'http://api',
        token: 't',
        cliente: MockClient((_) async => http.Response('{"error":"No tienes un perfil de negocio."}', 404)),
      );
      expect(await api.miNegocio(), isNull);
    });

    test('codifica los parámetros de búsqueda', () async {
      Uri? pedida;
      final api = ClienteApi(
        baseUrl: 'http://api',
        cliente: MockClient((peticion) async {
          pedida = peticion.url;
          return http.Response('[]', 200);
        }),
      );
      await api.buscar('café & pan', categoria: 'comida');
      expect(pedida!.queryParameters, {'q': 'café & pan', 'categoria': 'comida'});
    });
  });

  group('app', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('muestra el título y los vendedores abiertos', (tester) async {
      final estado = EstadoApp(api: ClienteApi(baseUrl: 'http://api', cliente: apiFalsa()));
      await tester.pumpWidget(MercadoLiebreApp(estado: estado));
      await tester.pumpAndSettle();

      expect(find.text('Mercado Liebre'), findsWidgets);
      expect(find.text('Abiertos ahora'), findsWidgets);
      expect(find.text('Taller del Nodo'), findsOneWidget);
    });

    testWidgets('sin vendedores abiertos muestra un estado vacío', (tester) async {
      final estado = EstadoApp(api: ClienteApi(baseUrl: 'http://api', cliente: apiFalsa(vendedores: [])));
      await tester.pumpWidget(MercadoLiebreApp(estado: estado));
      await tester.pumpAndSettle();

      expect(find.text('No hay vendedores abiertos en este momento.'), findsOneWidget);
    });

    testWidgets('al tocar un vendedor abre su ficha con el contacto', (tester) async {
      final estado = EstadoApp(api: ClienteApi(baseUrl: 'http://api', cliente: apiFalsa()));
      await tester.pumpWidget(MercadoLiebreApp(estado: estado));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Taller del Nodo'));
      await tester.pumpAndSettle();

      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('6561234567'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });
  });
}
