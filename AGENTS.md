# Guía para editar Mercado Liebre

Para personas nuevas en el código y para agentes de IA (Claude Code, Codex,
Cursor…). Lee primero [README.md](README.md) para saber qué hace la app.

## Comandos

| Qué                         | Dónde        | Comando                                                                   |
|-----------------------------|--------------|---------------------------------------------------------------------------|
| Analizar API                | `servidor/`  | `dart analyze`                                                            |
| Pruebas API (sin base)      | `servidor/`  | `dart test`                                                               |
| Correr API                  | `servidor/`  | `dart run bin/servidor.dart` (necesita `../.env` con `DATABASE_URL`)      |
| Analizar app                | `cliente/`   | `flutter analyze`                                                         |
| Pruebas app                 | `cliente/`   | `flutter test`                                                            |
| Correr app web              | `cliente/`   | `flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080`  |
| Build web de producción     | `cliente/`   | `flutter build web --release --dart-define=API_BASE_URL=same`             |
| Todo en Docker              | raíz         | `docker compose -f docker-compose.yml -f docker-compose.local.yml up --build` |

Antes de dar un cambio por terminado: `analyze` sin avisos y `test` en verde
en los dos paquetes que hayas tocado.

## Mapa del código

```
servidor/
  bin/servidor.dart      Arranque: entorno → pool → esquema → admin inicial → HTTP. Apagado con SIGTERM.
  lib/configuracion.dart Variables de entorno (+ .env local). Nunca imprime secretos.
  lib/base_datos.dart    Pool de PostgreSQL, aplicar schema.sql, cambiar de conexión en caliente.
  lib/rutas.dart         TODAS las rutas HTTP + autorización por rol (_Sesion) + errores → JSON.
  lib/repositorio.dart   TODO el SQL y las reglas de negocio. Devuelve Map con claves camelCase.
  lib/plano.dart         Códigos válidos del mapa (A…ZZ, 1…8).
  lib/apariencia.dart    Claves de apariencia editables y sus valores por defecto.
  lib/contrasena.dart    Hash PBKDF2 (compatible con la app Python anterior; no cambiar iteraciones).
  lib/token_sesion.dart  Token HS256 de 7 días.
  lib/medios.dart        Fotos subidas por el admin en DATOS_PATH/medios.
cliente/lib/
  main.dart              Raíz: ListenableBuilder sobre EstadoApp, tema claro/oscuro.
  configuracion.dart     API_BASE_URL (dart-define). "same" = mismo dominio (producción).
  servicios/api.dart     ClienteApi: un método por endpoint. Todo error → ErrorApi.
  servicios/estado.dart  EstadoApp (ChangeNotifier): sesión, tema, apariencia, favoritos.
  modelos/modelos.dart   Usuario, Vendedor, Producto, Calificacion, Apariencia, Aviso… con fromJson.
  pantallas/             Una pantalla por archivo. marco.dart = navegación y pestañas.
  widgets/comunes.dart   mostrarAviso, intentar, confirmar, EstadoVacio, TituloSeccion, ImagenRed, Estrellas.
  widgets/comunes.dart   (también LogoLiebre: el icono de la app dentro de la interfaz)
  widgets/tarjeta_vendedor.dart  Tarjeta de negocio + iconoCategoria + ubicacionDe.
  widgets/tarjeta_producto.dart  TarjetaProducto y MiniaturaProducto (foto o icono).
  widgets/datos_opcionales.dart  CamposOpcionales (teléfono, nº de control, carrera), carrerasItcj, ValidarOpcional.
  widgets/selector_dias.dart     SelectorDias + diasDesdeTexto/textoDeDias ("Lun-Vie", "Lun, Mié, Vie").
  servicios/imagenes.dart        comprimirFoto: reduce fotos a 1280 px JPEG antes de subirlas.
  pantallas/busqueda_pantalla.dart  Incluye OrdenBusqueda y ordenarResultados (orden en el cliente).
  tema/tema_liebre.dart  ColoresLiebre (marca), Espacio (separaciones), temaLiebre().
  mapa/puntos_campus.dart  Geometría de cada edificio sobre assets/mapa_plantel.jpg (1024×549).
  assets/icono/liebre.svg  Fuente del icono (solo el dibujo). Regenerar: python herramientas/generar_iconos.py
db/schema.sql            Idempotente (IF NOT EXISTS). Se ejecuta en cada arranque de la API.
herramientas/            Scripts de mantenimiento (generar_iconos.py).
```

## Convenciones

- **Idioma:** identificadores, comentarios, mensajes y commits en **español**.
  Excepción: nombres de tablas/columnas SQL heredados en inglés (`users`, `sellers`…).
- **Comentarios:** cada clase y miembro público lleva `///` explicando *para qué*.
  Mantén esa densidad al agregar código.
- **JSON:** la API responde camelCase (`nombreNegocio`), la base usa snake_case
  (`nombre_negocio`). La traducción vive solo en `Repositorio._usuario/_vendedor/_producto`.
- **Errores en la API:** lanza `ErrorApi(estado, 'Mensaje para la persona.')`
  desde rutas o repositorio. Nunca devuelvas texto de excepción de PostgreSQL.
- **Errores en la app:** `ClienteApi` convierte todo (HTTP, red, timeout) en
  `ErrorApi`. En pantallas usa `intentar(context, () => …, exito: '…')` o
  atrapa solo `on ErrorApi`.
- **SQL:** siempre `Sql.named` con `@parametros`. Nunca concatenes texto del cliente.
- **Colores:** usa `Theme.of(context).colorScheme` para texto y fondos (funciona
  en modo oscuro). `ColoresLiebre` solo para la marca (barra roja, avatar).
  Separaciones con `Espacio.s/m/l/xl`.
- **Acciones destructivas** (borrar, bloquear): siempre `confirmar(...)` antes.
- **Sintaxis Dart:** el SDK mínimo declarado es 3.5; evita `?elemento` en listas
  y comodines `_` repetidos en parámetros.

## Invariantes: si cambias X, cambia también Y

| Si cambias…                                       | …también cambia                                                        |
|---------------------------------------------------|------------------------------------------------------------------------|
| Un punto del mapa (`cliente/lib/mapa/puntos_campus.dart`) | `servidor/lib/plano.dart`. El test `plano_sincronizado_test` lo exige. |
| Una clave de apariencia (`servidor/lib/apariencia.dart`)  | Clase `Apariencia` en `cliente/lib/modelos/modelos.dart` (campo, `fromJson`, `toJson`, `predeterminada`) y `panel_admin.dart`. |
| Un icono de menú (`iconosDeMenu` en el servidor)  | `nombresDeIcono` e `iconoMenu()` en `cliente/lib/tema/iconos_menu.dart`. |
| Un campo que devuelve la API                      | `Repositorio._vendedor/_producto/_usuario` y el `fromJson` del modelo.  |
| Una columna o tabla                               | `db/schema.sql` con `ADD COLUMN IF NOT EXISTS` (el script corre en cada arranque sobre bases existentes). |
| Una ruta                                          | `rutas.dart`, método en `ClienteApi` y [docs/API.md](docs/API.md).      |
| Roles o categorías                                | Enums `user_role` / `seller_category` en `schema.sql`, validación en `Repositorio._crearCuenta`, listas en `sesion_dialogo.dart` (`categoriasNegocio`) y `panel_admin.dart`. |
| Validación de teléfono / nº de control            | `Repositorio._datosOpcionales` (servidor) y `ValidarOpcional` (cliente). |
| Límite de tamaño de imagen (1.5 MB)               | `Medios._maximoBytes`, `panel_admin.dart` y `comprimirFoto` (1280 px). |
| El dibujo del icono                               | Edita `cliente/assets/icono/liebre.svg` y corre `python herramientas/generar_iconos.py` (necesita Edge y Pillow). Regenera web, Android, iOS, Windows y el logo interno. |
| `iteracionesContrasena`                           | **No lo cambies**: invalidaría todas las contraseñas guardadas.         |

## Recetas

### Agregar un endpoint

1. SQL y regla en `Repositorio` (método público con `///`).
2. Ruta en `construirRutas` dentro de la sección que corresponda. Para exigir
   sesión: `await sesion.usuario(request)`, `sesion.vendedor`, `sesion.admin` o
   `sesion.conRol(request, {...}, 'mensaje')`.
3. Método en `ClienteApi` usando `_objeto` (respuesta objeto) o `_lista` (GET lista).
4. Documenta en `docs/API.md`.
5. Si no toca la base, agrega un caso en `servidor/test/rutas_test.dart`.

### Agregar una columna

```sql
-- al final de db/schema.sql
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS facebook TEXT;
```

Luego expónla en `Repositorio._vendedor` y en `Vendedor` (modelo + `fromJson`).

### Agregar una pantalla o sección

Usa `ListView` con `padding: EdgeInsets.all(Espacio.l)`, títulos con
`TituloSeccion`, estados vacíos con `EstadoVacio` y carga con
`CircularProgressIndicator`/`LinearProgressIndicator`. Para abrir fichas usa
`abrirVendedor(context, estado, v)` y `abrirProducto(context, estado, p)`.

## Seguridad: no romper

- Ninguna ruta devuelve `password_hash` (`_usuario` lo omite a propósito).
- El vendedor solo modifica *su* negocio: las consultas filtran por
  `user_id` del token, nunca por un id que mande el cliente.
- `/medios/<archivo>` valida el nombre con una expresión regular (sin `/` ni `..`).
- La API nunca imprime `DATABASE_URL` ni contraseñas en logs.
- `.env` y `datos/` están en `.gitignore` y `.dockerignore`.
