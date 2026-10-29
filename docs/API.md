# API de Mercado Liebre

Base: el mismo dominio de la app (`https://mercado.tudominio.com`) o
`http://127.0.0.1:8080` en desarrollo. Todo es JSON UTF-8.

**Autenticación:** `Authorization: Bearer <token>`. El token se obtiene en
`POST /api/sesion` o `POST /api/usuarios` y dura 7 días.

**Errores:** cualquier fallo responde `{ "error": "Mensaje para la persona." }`
con el código HTTP correspondiente:

| Código | Cuándo |
|--------|--------|
| 400 | Datos inválidos o JSON mal formado |
| 401 | Falta el token, expiró o la cuenta ya no existe |
| 403 | La cuenta está bloqueada o su rol no alcanza |
| 404 | No existe (producto, negocio, imagen) |
| 429 | Demasiados intentos seguidos (reportes, reenvío de verificación) |
| 500 | Error inesperado (el detalle queda en los logs del servidor) |
| 502 | El servidor de correo rechazó el envío o no respondió |
| 503 | El correo no está configurado (faltan `SMTP_USUARIO`/`SMTP_PASSWORD`) |

**Roles:** `comprador`, `vendedor`, `moderador`, `admin`. En la tabla, "vendedor"
significa vendedor **o** admin; "moderador" significa moderador **o** admin.

## Público

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/salud` | `{ "estado": "ok" }`. Healthcheck. |
| GET | `/api/apariencia` | Título, menús, iconos y URLs de imágenes. |
| GET | `/api/vendedores?soloDisponibles=true` | Negocios; destacados primero. |
| GET | `/api/vendedores/destacados` | Negocios con promoción vigente. |
| GET | `/api/productos?vendedor=<sellerId>` | Catálogo de un negocio. |
| GET | `/api/productos/mas-vendidos` | 8 productos con más `vecesVendido`. |
| GET | `/api/buscar?q=<texto>&categoria=<comida\|producto\|servicio>&soloDisponibles=true` | Ver abajo. |
| GET | `/api/avisos` | Avisos institucionales activos. |
| GET | `/api/anuncios` | Anuncios de los carruseles: `[{ seccion: 1-2, posicion: 1-3, imagenUrl, vendedor: {…} \| null }]`, por sección y posición. `vendedor` es el negocio que abre al tocarlo. |
| GET | `/api/calificaciones?producto=<id>` | Últimas 20 reseñas. |
| GET | `/medios/<archivo>` | Imagen subida por el admin (caché de un año). |
| GET | `/api/verificar-correo?token=<token>` | Enlace del correo de verificación. Responde **HTML** (no JSON): 200 verificado, 400 enlace vencido o falso, 404 cuenta borrada. |
| POST | `/api/reportes` | Reporte de falla, queja o sugerencia. Ver abajo. |
| POST | `/api/contrasena/olvido` | `{ correo }` → `{ ok }`. Manda un enlace para elegir contraseña nueva. Responde igual exista o no la cuenta. 400 correo inválido, 429 más de 5 por hora por IP, 503 sin SMTP. |
| GET | `/api/restablecer?token=<token>` | Enlace del correo. Responde **HTML** con el formulario (o 400 si venció, se usó o se anuló). |
| POST | `/api/restablecer` | Formulario `application/x-www-form-urlencoded`: `token, password, confirmacion`. Responde **HTML**. |

### Restablecer contraseña

Cada solicitud es una fila de `restablecimientos`; el token del enlace la
identifica, se firma con una llave derivada (`APP_SECRET_KEY|restablecer-contrasena`),
vence en **1 hora** y sirve **una sola vez**. Pedir otro enlace anula los
anteriores. El administrador ve el historial y puede anular enlaces o fijar
una contraseña directamente (ver Administración).

### `POST /api/reportes`

No exige sesión; si viene un token válido, el correo de la cuenta se anota en el reporte.

```json
{ "contacto": "ana@itcj.edu.mx", "descripcion": "El mapa no carga.", "foto": { "nombre": "captura.jpg", "datos": "<base64>" } }
```

`contacto` es un correo o un número de control (misma regla que el perfil).
`descripcion` lleva de 10 a 1000 caracteres. `foto` es opcional: JPG/PNG/WEBP/GIF,
máx. 1.5 MB. Se envía por correo a `CORREO_REPORTES` (texto plano, la foto como
adjunto y `Reply-To` al contacto si es un correo). Máximo 5 reportes por hora por IP (429).

### `GET /api/buscar`

Busca `q` (mínimo 2 letras, sin distinguir mayúsculas) en nombre del negocio,
especialidad y nombre de producto. **Sin `q`** lista todos los vendedores (útil
para explorar una `categoria`). Con `soloDisponibles=true` deja solo los
abiertos. Una sola letra devuelve `[]`. Responde:

```json
[
  {
    "vendedor": { "id": "…", "nombreNegocio": "Tacos Liebre", "...": "…" },
    "productos": [ { "id": "…", "nombre": "Taco de asada", "precio": 25.0, "...": "…" } ],
    "coincidenciaExacta": true
  }
]
```

Las coincidencias exactas van primero. Si coincide el negocio, `productos`
trae todo su catálogo; si coincidió un producto, solo los productos que contienen `q`.

## Sesión

| Método | Ruta | Cuerpo | Respuesta |
|--------|------|--------|-----------|
| POST | `/api/sesion` | `{ correo, password }` | `{ token, usuario }` |
| POST | `/api/usuarios` | `{ nombre, apellido, correo, password, rol?, telefono?, numeroControl?, carrera?, nombreNegocio?, categoria?, subtipo?, descripcion? }` | 201 `{ token, usuario, correoEnviado }` |
| GET | `/api/yo` | — | `usuario` |
| POST | `/api/yo/verificacion` | — | `{ ok, correo }`. Reenvía el enlace de verificación. 400 si ya está verificado; 429 si pidió otro hace menos de un minuto. |
| PATCH | `/api/yo` | `{ telefono?, numeroControl?, carrera? }` | `usuario`. Clave ausente = sin cambio; `""` = borrar. |
| DELETE | `/api/yo` | `{ password }` | `{ ok }`. Borra la cuenta y **todo lo suyo**: negocio, productos (y sus fotos del disco), reseñas que escribió y que recibieron sus productos, favoritos, anuncios de su negocio y restablecimientos. 400 sin contraseña o si es admin; 403 contraseña incorrecta. |

Datos opcionales (registro y `PATCH /api/yo`): `telefono` con 7–15 dígitos
(admite espacios, `+`, `-`, paréntesis); `numeroControl` de 6–10 dígitos con
una letra inicial opcional (se guarda en mayúsculas); `carrera` hasta 80
caracteres.

En el registro público `rol` solo puede ser `comprador` (por defecto) o
`vendedor`; un vendedor necesita `nombreNegocio` y `categoria`.

**Verificación de correo:** la cuenta pública nace con `correoVerificado: false`
y se le envía un enlace (`/api/verificar-correo?token=…`, vence en 48 h). La
cuenta entra y navega normalmente, pero no califica ni comenta hasta abrirlo.
`correoEnviado: false` significa que el correo no salió (la cuenta sí se creó;
puede pedir otro con `POST /api/yo/verificacion`). Las cuentas creadas por el
admin y las que ya existían antes de esta función quedan verificadas.

## Cuenta con sesión

| Método | Ruta | Cuerpo | Respuesta |
|--------|------|--------|-----------|
| GET | `/api/favoritos` | — | `["sellerId", …]` |
| POST | `/api/favoritos/<sellerId>` | — | `{ marcado: bool }` (alterna) |
| POST | `/api/calificaciones` | `{ productoId, estrellas: 1-5, comentario? }` | `{ ok }`. Solo comprador o admin con el correo verificado (403 si no); no sobre productos propios. Una reseña por persona y producto (se sobrescribe). |

## Vendedor

| Método | Ruta | Cuerpo |
|--------|------|--------|
| GET | `/api/vendedores/mio` | — (404 si la cuenta no tiene negocio) |
| PATCH | `/api/vendedores/disponibilidad` | `{ disponible: bool }` |
| POST | `/api/vendedores/punto` | `{ edificio: "Z" }` (código de `servidor/lib/plano.dart`) |
| PATCH | `/api/vendedores/horario` | `{ apertura: "08:00", cierre: "15:30", dias: "Lun, Mié, Vie" }` (texto libre, máx. 40; la app lo arma con `textoDeDias`) |
| PATCH | `/api/vendedores/contacto` | `{ whatsapp?, telegram?, instagram?, telefonoFijo? }` — vacío borra |
| POST | `/api/productos` | `{ nombre, precio, descripcion? }` → 201 producto |
| PATCH | `/api/productos/<id>` | `{ nombre, precio, descripcion?, agotado }` |
| DELETE | `/api/productos/<id>` | — (borra también su foto) |
| POST | `/api/productos/<id>/foto` | `{ nombre: "foto.jpg", datos: "<base64>" }` → `{ fotoUrl }`. JPG/PNG/WEBP/GIF, máx. 1.5 MB. Reemplaza y borra la anterior. |
| DELETE | `/api/productos/<id>/foto` | — |

Todas actúan sobre el negocio de la cuenta del token; no se puede tocar el de otra persona.

## Moderación

| Método | Ruta | Rol | Cuerpo |
|--------|------|-----|--------|
| GET | `/api/moderacion/usuarios` | moderador | — |
| POST | `/api/moderacion/usuarios/<id>/bloqueo` | moderador | `{ bloqueado: bool }` |
| DELETE | `/api/moderacion/usuarios/<id>` | admin | — (igual que `DELETE /api/yo`: borra todo lo de la cuenta, fotos incluidas) |

Nadie puede bloquear ni borrar su propia cuenta (400). Un moderador no puede
bloquear a otro moderador ni a un administrador (403). Un `id` que no es UUID
responde 404.

## Administración (solo `admin`)

| Método | Ruta | Cuerpo |
|--------|------|--------|
| POST | `/api/admin/usuarios` | Igual que el registro, con `rol` cualquiera de los cuatro. |
| PATCH | `/api/admin/apariencia` | Cualquier subconjunto de `titulo, menuInicio, menuBusqueda, menuMapa, menuPerfil, iconoInicio, iconoBusqueda, iconoMapa, iconoPerfil, logoUrl, iconoUrl, fotoPortadaUrl`. Los `…Url` son imagen (`http(s)://` o `/medios/…`). La publicidad ya no va aquí (ver Anuncios). |
| POST | `/api/admin/medios` | `{ nombre: "foto.png", datos: "<base64>" }` → 201 `{ url: "/medios/…" }`. JPG/PNG/WEBP/GIF, máx. 1.5 MB. |
| GET | `/api/admin/conexion` | — → `{ host, puerto, base, usuario, ssl, tieneContrasena, conectada, usaEntorno }` |
| POST | `/api/admin/conexion/probar` | `{ host, puerto, base, usuario, contrasena?, ssl }` |
| PATCH | `/api/admin/conexion` | Igual que probar, o `{ restaurarEntorno: true }`. Reconecta en caliente y guarda en `DATOS_PATH/conexion.json`. |
| GET | `/api/admin/resumen` | — → conteos: `usuarios, bloqueados, sinVerificar, compradores, cuentasVendedor, moderadores, administradores, vendedores, abiertos, sinPunto, productos, calificaciones, favoritos, avisosActivos, anuncios, restablecimientosPendientes` |

### Cuentas

| Método | Ruta | Cuerpo |
|--------|------|--------|
| PATCH | `/api/admin/usuarios/<id>` | Cualquier subconjunto de `nombre, apellido, correo, rol, correoVerificado, telefono, numeroControl, carrera` → `usuario`. 400 si el admin se quita su propio rol o el correo ya existe. |
| POST | `/api/admin/usuarios/<id>/contrasena` | `{ password }` (≥ 8). Fija la contraseña y anula enlaces pendientes. |
| POST | `/api/admin/usuarios/<id>/restablecimiento` | — → `{ ok, correo }`. Manda a la cuenta el enlace de restablecimiento. 503 sin SMTP. |
| GET | `/api/admin/restablecimientos` | — → últimas 100: `{ id, userId, nombre, correo, origen: correo\|admin, estado: pendiente\|usado\|vencido\|anulado, creadoEn, venceEn, usadoEn }` |
| POST | `/api/admin/restablecimientos/<id>/anular` | — (404 si ya no está pendiente) |

### Negocios, productos y mapa

| Método | Ruta | Cuerpo |
|--------|------|--------|
| PATCH | `/api/admin/vendedores/<id>` | Cualquier subconjunto de `nombreNegocio, categoria, subtipo, descripcion, edificio, disponible, destacado, destacadoHasta` → `vendedor`. `edificio` es un código del plano o `""` (sin punto). `destacadoHasta` ISO 8601 o `""` (sin fin). |
| DELETE | `/api/admin/vendedores/<id>` | — Borra el negocio con productos, fotos, reseñas y anuncios. La cuenta queda como comprador. |
| DELETE | `/api/admin/productos/<id>` | — Borra cualquier producto con su foto. |

### Anuncios (publicidad)

Hay 2 secciones (1 arriba, 2 abajo) con 3 posiciones cada una
(`seccionesPublicidad` y `anunciosPorSeccion` en `servidor/lib/apariencia.dart`).
La app rota las imágenes de cada sección cada 6 s.

| Método | Ruta | Cuerpo |
|--------|------|--------|
| PUT | `/api/admin/anuncios/<seccion>/<posicion>` | `{ imagenUrl, vendedorId? }` → lista completa de anuncios. `vendedorId` vacío = no abre nada. 404 si la posición o el negocio no existen. |
| DELETE | `/api/admin/anuncios/<seccion>/<posicion>` | — → lista completa. La imagen se queda en `/medios`. |

### Avisos, reseñas y registros

| Método | Ruta | Cuerpo |
|--------|------|--------|
| GET | `/api/admin/avisos` | — → todos, con `id, titulo, contenido, activo, publicadoEn` |
| POST | `/api/admin/avisos` | `{ titulo (≤120), contenido (≤2000), activo? }` → 201 aviso |
| PATCH | `/api/admin/avisos/<id>` | Cualquier subconjunto de lo anterior |
| DELETE | `/api/admin/avisos/<id>` | — |
| GET | `/api/admin/calificaciones` | — → últimas 100: `{ productoId, autorId, estrellas, comentario, creadoEn, producto, nombreNegocio, autor, correo }` |
| DELETE | `/api/admin/calificaciones/<productoId>/<autorId>` | — |
| GET | `/api/admin/tablas` | — → `[{ tabla, filas }]` de las tablas de `Repositorio.tablasVisibles` |
| GET | `/api/admin/tablas/<tabla>?pagina=1&limite=25` | — → `{ tabla, columnas, filas: [[…]], total, pagina, limite }`. **Solo lectura**, máx. 100 por página, nunca incluye `password_hash`. |

## Objetos

**usuario:** `id, nombre, apellido, correo, rol, telefono, numeroControl, carrera, fotoPerfilUrl, bloqueado, perfilEditable, correoVerificado, creadoEn`

**vendedor:** `id, userId, nombreNegocio, categoria, subtipo, descripcion, horarioApertura, horarioCierre, diasAtencion, horarioTexto, disponible, edificio, destacado, destacadoHasta, whatsapp, telegram, messenger, instagram, telefonoFijo, aceptaMensajesApp, promedioEstrellas, totalResenas` (las dos últimas suman las reseñas de todos sus productos)

**producto:** `id, sellerId, nombre, descripcion, precio, fotoUrl, agotado, vecesVendido, promedioEstrellas, totalResenas`
