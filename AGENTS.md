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
  bin/servidor.dart      Arranque: entorno → pool (con reintentos) → esquema → admin inicial → HTTP. Apagado con SIGTERM.
  lib/configuracion.dart Variables de entorno (+ .env local). Nunca imprime secretos.
  lib/base_datos.dart    Pool de PostgreSQL, aplicar schema.sql, cambiar de conexión en caliente.
  lib/rutas.dart         TODAS las rutas HTTP + autorización por rol (_Sesion) + errores → JSON.
  lib/repositorio.dart   TODO el SQL y las reglas de negocio. Devuelve Map con claves camelCase.
  lib/plano.dart         Códigos válidos del mapa (A…ZZ, 1…8).
  lib/apariencia.dart    Claves de apariencia editables y sus valores por defecto. Límites de publicidad (2 secciones × 3).
  lib/contrasena.dart    Hash PBKDF2 (compatible con la app Python anterior; no cambiar iteraciones).
  lib/token_sesion.dart  Token HS256 de 7 días.
  lib/medios.dart        Fotos subidas por el admin en DATOS_PATH/medios.
  lib/correo.dart        SMTP (Zoho): verificación, restablecimiento de contraseña y reportes. Config en ConfiguracionCorreo.
  lib/reportes.dart      Validación de POST /api/reportes (contacto, descripción, foto).
cliente/lib/
  main.dart              Raíz: ListenableBuilder sobre EstadoApp, tema claro/oscuro.
  configuracion.dart     API_BASE_URL (dart-define). "same" = mismo dominio (producción).
  servicios/api.dart     ClienteApi: un método por endpoint. Todo error → ErrorApi.
  servicios/estado.dart  EstadoApp (ChangeNotifier): sesión, tema, apariencia, anuncios, favoritos, eliminarCuenta,
                         cambiarModo (usuario ↔ vendedor, cambio REAL de rol), cambiarFotoPerfil,
                         vista previa (VistaCuenta: admin → vendedor/usuario, vendedor → usuario; solo cambia la interfaz).
  servicios/instalacion.dart  InstalacionApp: botón "Instalar app" (PWA). Web: instalacion_web.dart ↔ window.liebrePwa de web/index.html.
  modelos/modelos.dart   Usuario, Vendedor, Producto, Calificacion, Apariencia, Aviso, Anuncio, Restablecimiento,
                         ResenaAdmin, PaginaTabla… con fromJson.
  pantallas/             Una pantalla por archivo. marco.dart = barra roja con las pestañas,
                         botón Favoritos, menú de la cuenta (secciones, vistas previas, Reportar falla)
                         y barra lateral de publicidad.
  pantallas/perfil_pantalla.dart  SeccionCuenta: cada opción del menú del nombre es una página. "Mis datos" lleva la foto de perfil.
  pantallas/modo_cuenta.dart      cambiarModoCuenta, TarjetaModoCuenta y DialogoNuevoNegocio (POST /api/yo/modo).
  pantallas/panel_negocio.dart    "Mi negocio": logo y foto de la tienda, compartir, catálogo (foto de galería o cámara),
                                  horario, contacto, eliminar cuenta.
  pantallas/detalle_vendedor.dart Ficha del negocio + abrirEnlaceCompartido (?vendedor= / ?producto= al abrir la web).
  pantallas/panel_admin.dart      PanelAdmin: página con pestañas. Lista `pestanas`; cada una vive en pantallas/admin/.
  pantallas/admin/       Una pestaña por archivo (admin_usuarios, admin_vendedores, admin_mapa, admin_publicidad,
                         admin_avisos, admin_resenas, admin_contrasenas, admin_base_datos, admin_apariencia, admin_resumen).
                         comun_admin.dart: CargaAdmin (carga/error/recargar), BuscadorAdmin, Etiqueta, fechaCorta, subirImagenAdmin.
  widgets/comunes.dart   mostrarAviso, intentar, confirmar, EstadoVacio, TituloSeccion, ImagenRed, Estrellas.
  widgets/comunes.dart   (también LogoLiebre: el icono de la app dentro de la interfaz, y AvatarUsuario: foto de perfil o inicial)
  widgets/tarjeta_vendedor.dart  Tarjeta de negocio + LogoNegocio (logo o icono) + iconoCategoria + ubicacionDe.
  widgets/selector_imagen.dart   elegirImagen (hoja galería/cámara/quitar), leerFoto (elige y comprime), hayCamara.
  widgets/compartir.dart         compartirVendedor/compartirProducto: Facebook, Telegram o copiar enlace (enlaceVendedor/enlaceProducto).
  widgets/tarjeta_producto.dart  TarjetaProducto y MiniaturaProducto (foto o icono).
  widgets/datos_opcionales.dart  CamposOpcionales (teléfono, nº de control, carrera), carrerasItcj, ValidarOpcional.
  widgets/selector_dias.dart     SelectorDias + diasDesdeTexto/textoDeDias ("Lun-Vie", "Lun, Mié, Vie").
  widgets/publicidad.dart        BarraPublicidad (dos carruseles, desde anchoBarraLateral), AnunciosEnLista (In-Feed en búsqueda,
                                 pantallas angostas; intercalarAnuncios) y EspacioPublicitario (carrusel: rota cada duracionAnuncio).
  widgets/eliminar_cuenta.dart   TarjetaEliminarCuenta + DialogoEliminarCuenta (pide contraseña, vuelve a Inicio).
  widgets/instalar_app.dart      BotonInstalar (barra roja), InvitacionInstalar (Inicio en celular), instalarApp.
  widgets/reporte_dialogo.dart   mostrarReporte: formulario de fallas, quejas y sugerencias.
  widgets/verificacion.dart      AvisoVerificacion: "verifica tu correo" con reenviar.
  servicios/imagenes.dart        comprimirFoto: reduce fotos a 1280 px JPEG antes de subirlas.
  pantallas/busqueda_pantalla.dart  Incluye OrdenBusqueda y ordenarResultados (orden en el cliente).
  tema/tema_liebre.dart  ColoresLiebre (marca), Espacio (separaciones), temaLiebre().
  mapa/puntos_campus.dart  Geometría de cada edificio sobre assets/mapa_plantel.jpg (1024×549).
  assets/icono/liebre.svg  Fuente del icono (solo el dibujo). Regenerar: python herramientas/generar_iconos.py
cliente/web/
  index.html             Pantalla de carga, window.liebrePwa (beforeinstallprompt) y registro de sw.js.
  flutter_bootstrap.js   Plantilla propia del arranque: sin el service worker obsoleto de Flutter, CanvasKit local.
  sw.js                  Service worker de la PWA ("primero la red"; nunca toca /api ni /medios). Sube CACHE si lo cambias.
  manifest.json          Nombre, colores e iconos de la app instalable.
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
| Una clave de apariencia (`servidor/lib/apariencia.dart`)  | Clase `Apariencia` en `cliente/lib/modelos/modelos.dart` (campo, `fromJson`, `toJson`, `predeterminada`) y `pantallas/admin/admin_apariencia.dart`. |
| Número de carruseles o de imágenes (`seccionesPublicidad`, `anunciosPorSeccion`) | `CHECK` de la tabla `anuncios` en `schema.sql`, `Anuncio.secciones/porSeccion` en el cliente. |
| Dónde va la publicidad (lateral o en la lista)    | Solo `anchoBarraLateral`, `resultadosAntesDeAnuncio` y `resultadosEntreAnuncios` en `widgets/publicidad.dart`. |
| Quién ve un negocio (público vs. en pausa)        | `_selectVendedores` (público: dueño no comprador) y `_selectTodosLosVendedores` (admin y dueño) en `repositorio.dart`; `_soloNegociosPublicos` para productos. Una consulta pública nueva usa la versión pública. |
| Quién necesita aprobación para reseñar            | `Repositorio.calificar` (vendedor o cualquiera con negocio, salvo admin), `textoResenaVendedor` en `detalle_producto.dart` y la pestaña `admin_resenas.dart`. Toda lectura pública de `ratings` filtra `aprobada` (vista `product_ratings_summary`, `_promediosNegocio`, `calificacionesDe`). |
| Una imagen del negocio (logo, portada)            | `Repositorio.columnasImagenNegocio`, columnas en `schema.sql`, `_vendedor`, `eliminarUsuario`/`eliminarNegocio` (devuelven los archivos) y `Vendedor` en el cliente. |
| Los enlaces para compartir (`?vendedor=`, `?producto=`) | `enlaceVendedor`/`enlaceProducto` en `widgets/compartir.dart` y `abrirEnlaceCompartido` en `detalle_vendedor.dart`. |
| Inactividad de un negocio (30 días)               | `diasInactividad` en `admin/admin_vendedores.dart`. El último uso se anota en `_Sesion.anotarAcceso` (`rutas.dart`). |
| Tiempo de cada anuncio                            | Solo `duracionAnuncio` en `widgets/publicidad.dart` (el texto de `admin_publicidad.dart` lo lee de ahí). |
| Algo que pertenece a una cuenta (tabla nueva con `user_id` o `seller_id`) | `ON DELETE CASCADE` en la llave foránea, para que "Eliminar cuenta" lo borre. Si guarda archivos en `/medios`, devuélvelos en `Repositorio.eliminarUsuario`. |
| Una tabla que el admin deba poder consultar       | `Repositorio.tablasVisibles` (columnas fijas, nunca `password_hash`) y `_nombres` en `admin_base_datos.dart`. |
| Una pestaña del panel de administración           | Archivo en `pantallas/admin/` y entrada en `PanelAdmin.pestanas`. |
| Vigencia del enlace de contraseña (1 h)           | `vigenciaRestablecimiento` en `rutas.dart` y los textos "vence en una hora" del cliente. |
| Un icono de menú (`iconosDeMenu` en el servidor)  | `nombresDeIcono` e `iconoMenu()` en `cliente/lib/tema/iconos_menu.dart`. |
| Un campo que devuelve la API                      | `Repositorio._vendedor/_producto/_usuario` y el `fromJson` del modelo.  |
| Una columna o tabla                               | `db/schema.sql` con `ADD COLUMN IF NOT EXISTS` (el script corre en cada arranque sobre bases existentes). |
| Una ruta                                          | `rutas.dart`, método en `ClienteApi` y [docs/API.md](docs/API.md).      |
| Roles o categorías                                | Enums `user_role` / `seller_category` en `schema.sql`, validación en `Repositorio._crearCuenta` y `actualizarUsuarioAdmin`/`actualizarVendedorAdmin`, listas `categoriasNegocio` (`sesion_dialogo.dart`) y `rolesCuenta` (`admin/admin_usuarios.dart`). |
| Validación de teléfono / nº de control            | `Repositorio._datosOpcionales` (servidor) y `ValidarOpcional` (cliente). |
| Límite de tamaño de imagen (1.5 MB)               | `Medios.maximoBytes` (también lo usa `Reporte`), `subirImagenAdmin` en `admin/comun_admin.dart` y `comprimirFoto` (1280 px). |
| Regla del contacto de un reporte                  | `Reporte._contactoValido` (servidor) y `validarContactoReporte` (cliente). |
| Largo de la descripción de un reporte (1000)      | `Reporte.maximoDescripcion` y `maximoDescripcionReporte`.               |
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

### Agregar una pestaña al panel de administración

1. Crea `cliente/lib/pantallas/admin/admin_algo.dart` con un widget que reciba
   `EstadoApp estado` y use `CargaAdmin<T>(cargar: …, construir: (context, datos, recargar) => [...])`.
2. Agrégalo a `PanelAdmin.pestanas` (título, icono, constructor).
3. Las rutas nuevas van bajo `/api/admin/...` y empiezan con `await sesion.admin(request)`.
4. Acciones destructivas con `confirmar(...)`; guardar con `intentar(..., exito: '…')` y luego `recargar()`.

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
- `SMTP_PASSWORD` solo vive en el entorno (Coolify). Nunca en el repositorio ni en logs.
- El enlace de verificación se firma con una llave derivada (`APP_SECRET_KEY|verificar-correo`):
  un token de sesión no sirve para verificar ni viceversa.
- Las rutas que envían correo tienen límite en memoria (`_Limite` en `rutas.dart`).
- El enlace de restablecimiento usa otra llave derivada (`APP_SECRET_KEY|restablecer-contrasena`),
  apunta a una fila de `restablecimientos` y solo sirve una vez. `/api/contrasena/olvido` responde
  igual exista o no la cuenta (y envía en segundo plano) para no revelar qué correos están registrados.
- `DELETE /api/yo` pide la contraseña; un administrador no puede borrarse a sí mismo ni quitarse su rol.
- `POST /api/yo/modo` solo cambia entre `comprador` y `vendedor`: nunca sube a moderador ni admin.
- Las reseñas pendientes (`aprobada = FALSE`) nunca salen en rutas públicas ni cuentan en promedios.
- El explorador de registros es de **solo lectura** y arma el SQL con nombres de `tablasVisibles`,
  nunca con texto del cliente.
- El service worker (`web/sw.js`) nunca guarda en caché `/api/` ni `/medios/`.
