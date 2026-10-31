import 'package:flutter/material.dart';

import '../configuracion.dart';
import '../servicios/api.dart';
import '../tema/tema_liebre.dart';

/// Muestra [mensaje] en un SnackBar, si [context] sigue montado.
void mostrarAviso(BuildContext context, String mensaje) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje)));
}

/// Ejecuta [accion] y muestra en un SnackBar el error de la API, si lo hay.
///
/// Si [exito] no es null, se muestra al terminar bien. Devuelve true si
/// la acción terminó sin error.
Future<bool> intentar(BuildContext context, Future<void> Function() accion, {String? exito}) async {
  try {
    await accion();
    if (exito != null && context.mounted) {
      mostrarAviso(context, exito);
    }
    return true;
  } on ErrorApi catch (error) {
    if (context.mounted) {
      mostrarAviso(context, error.mensaje);
    }
    return false;
  }
}

/// Pide confirmación antes de una acción que no se puede deshacer.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String accion = 'Eliminar',
}) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(contexto).colorScheme.error,
            foregroundColor: Theme.of(contexto).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(contexto, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return respuesta == true;
}

/// Título de sección con acción opcional a la derecha.
class TituloSeccion extends StatelessWidget {
  /// [accion] suele ser un `TextButton`.
  const TituloSeccion(this.texto, {super.key, this.accion, this.icono});

  /// Texto del título.
  final String texto;

  /// Icono a la izquierda del título.
  final IconData? icono;

  /// Widget a la derecha.
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Espacio.xl, bottom: Espacio.s),
      child: Row(
        children: [
          if (icono != null) ...[
            Icon(icono, size: 20, color: esquema.primary),
            const SizedBox(width: Espacio.s),
          ],
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.titleMedium)),
          if (accion != null) accion!,
        ],
      ),
    );
  }
}

/// Mensaje centrado con icono, para listas vacías o errores.
class EstadoVacio extends StatelessWidget {
  /// [alReintentar] agrega un botón "Reintentar".
  const EstadoVacio({super.key, required this.icono, required this.mensaje, this.detalle, this.alReintentar});

  /// Error de carga con botón de reintento.
  const EstadoVacio.error({super.key, required this.mensaje, required this.alReintentar})
      : icono = Icons.cloud_off_outlined,
        detalle = null;

  /// Icono grande superior.
  final IconData icono;

  /// Texto principal.
  final String mensaje;

  /// Texto secundario opcional.
  final String? detalle;

  /// Acción del botón, si se muestra.
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: esquema.primary.withValues(alpha: 0.7)),
            const SizedBox(height: Espacio.m),
            Text(mensaje, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
            if (detalle != null) ...[
              const SizedBox(height: Espacio.xs),
              Text(detalle!, textAlign: TextAlign.center, style: TextStyle(color: esquema.onSurfaceVariant)),
            ],
            if (alReintentar != null) ...[
              const SizedBox(height: Espacio.l),
              FilledButton.tonalIcon(
                onPressed: alReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Imagen de la API o de internet. Si falla, muestra [respaldo] (o nada).
class ImagenRed extends StatelessWidget {
  /// [ruta] puede ser `/medios/...` o una URL completa.
  const ImagenRed(this.ruta, {super.key, this.alto, this.ancho, this.radio = 12, this.respaldo});

  /// Ruta o URL de la imagen.
  final String ruta;

  /// Alto fijo, opcional.
  final double? alto;

  /// Ancho fijo, opcional.
  final double? ancho;

  /// Radio de las esquinas.
  final double radio;

  /// Widget si la imagen no carga.
  final Widget? respaldo;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: Image.network(
        ConfiguracionApp.urlPublica(ruta),
        height: alto,
        width: ancho,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => respaldo ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// Foto de perfil en un círculo. Sin foto (o si no carga), la inicial de [nombre].
class AvatarUsuario extends StatelessWidget {
  /// [fondo] y [colorTexto] solo se usan para la inicial.
  const AvatarUsuario({super.key, required this.nombre, this.fotoUrl, this.radio = 20, this.fondo, this.colorTexto});

  /// Nombre de la persona; su primera letra es el respaldo.
  final String nombre;

  /// `/medios/...` o URL completa; null o vacía muestra la inicial.
  final String? fotoUrl;

  /// Radio del círculo.
  final double radio;

  /// Fondo detrás de la inicial.
  final Color? fondo;

  /// Color de la inicial.
  final Color? colorTexto;

  @override
  Widget build(BuildContext context) {
    final inicial = Text(
      nombre.isEmpty ? '?' : nombre.characters.first.toUpperCase(),
      style: TextStyle(color: colorTexto, fontSize: radio * 0.8, fontWeight: FontWeight.w700),
    );
    final foto = fotoUrl ?? '';
    return CircleAvatar(
      radius: radio,
      backgroundColor: fondo,
      child: foto.isEmpty
          ? inicial
          : ClipOval(
              child: ImagenRed(foto, alto: radio * 2, ancho: radio * 2, radio: 0, respaldo: Center(child: inicial)),
            ),
    );
  }
}

/// Estrellas de 0 a 5, con el promedio y el número de reseñas.
class Estrellas extends StatelessWidget {
  /// [total] se omite si es null.
  const Estrellas({super.key, required this.promedio, this.total, this.tamano = 16});

  /// Promedio de 0 a 5.
  final double promedio;

  /// Número de reseñas.
  final int? total;

  /// Tamaño de cada estrella.
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final redondeado = (promedio * 2).round() / 2;
    return Semantics(
      label: '${promedio.toStringAsFixed(1)} de 5 estrellas',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var n = 1; n <= 5; n++)
            Icon(
              redondeado >= n
                  ? Icons.star_rounded
                  : redondeado >= n - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
              size: tamano,
              color: ColoresLiebre.estrella,
            ),
          if (total != null) ...[
            const SizedBox(width: Espacio.xs),
            Text(
              total == 0 ? 'Sin reseñas' : '${promedio.toStringAsFixed(1)} ($total)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Icono de la app (liebre en su puesto). Fuente: assets/icono/liebre.svg.
class LogoLiebre extends StatelessWidget {
  /// [lado] en píxeles lógicos.
  const LogoLiebre({super.key, this.lado = 28});

  /// Ancho y alto.
  final double lado;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icono/icono.png', width: lado, height: lado, semanticLabel: 'Mercado Liebre');
  }
}

/// Centra y limita el ancho del contenido en pantallas grandes.
class AnchoLimitado extends StatelessWidget {
  /// Envuelve [child] con [Espacio.anchoMaximo].
  const AnchoLimitado({super.key, required this.child});

  /// Contenido.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Espacio.anchoMaximo), child: child),
    );
  }
}
