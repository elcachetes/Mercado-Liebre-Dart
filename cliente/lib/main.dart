import 'package:flutter/material.dart';

import 'pantallas/marco.dart';
import 'servicios/estado.dart';
import 'tema/tema_liebre.dart';
import 'widgets/comunes.dart';

/// Punto de entrada. Restaura la sesión y monta el tema rojo y blanco.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MercadoLiebreApp());
}

/// Raíz de la aplicación.
///
/// Reconstruye el árbol cada vez que [EstadoApp] avisa un cambio
/// (sesión, tema, apariencia o favoritos).
class MercadoLiebreApp extends StatefulWidget {
  /// [estado] permite inyectar uno falso en pruebas.
  MercadoLiebreApp({super.key, EstadoApp? estado}) : estado = estado ?? EstadoApp();

  /// Estado global de la app.
  final EstadoApp estado;

  @override
  State<MercadoLiebreApp> createState() => _MercadoLiebreAppState();
}

class _MercadoLiebreAppState extends State<MercadoLiebreApp> {
  @override
  void initState() {
    super.initState();
    widget.estado.restaurar();
  }

  @override
  void dispose() {
    widget.estado.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    return ListenableBuilder(
      listenable: estado,
      builder: (context, _) => MaterialApp(
        title: estado.apariencia.titulo,
        debugShowCheckedModeBanner: false,
        theme: temaLiebre(Brightness.light),
        darkTheme: temaLiebre(Brightness.dark),
        themeMode: estado.modo,
        home: estado.cargando ? const _Arranque() : MarcoPrincipal(estado: estado),
      ),
    );
  }
}

/// Pantalla roja con el nombre mientras se restaura la sesión.
class _Arranque extends StatelessWidget {
  const _Arranque();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ColoresLiebre.primario,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoLiebre(lado: 112),
            SizedBox(height: Espacio.l),
            Text('Mercado Liebre', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            SizedBox(height: Espacio.xl),
            SizedBox.square(dimension: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
          ],
        ),
      ),
    );
  }
}
