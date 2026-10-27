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
| 500 | Error inesperado (el detalle queda en los logs del servidor) |

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
| GET | `/api/calificaciones?producto=<id>` | Últimas 20 reseñas. |
| GET | `/medios/<archivo>` | Imagen subida por el admin (caché de un año). |

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
| POST | `/api/usuarios` | `{ nombre, apellido, correo, password, rol?, telefono?, numeroControl?, carrera?, nombreNegocio?, categoria?, subtipo?, descripcion? }` | 201 `{ token, usuario }` |
| GET | `/api/yo` | — | `usuario` |
| PATCH | `/api/yo` | `{ telefono?, numeroControl?, carrera? }` | `usuario`. Clave ausente = sin cambio; `""` = borrar. |

Datos opcionales (registro y `PATCH /api/yo`): `telefono` con 7–15 dígitos
(admite espacios, `+`, `-`, paréntesis); `numeroControl` de 6–10 dígitos con
una letra inicial opcional (se guarda en mayúsculas); `carrera` hasta 80
caracteres.

En el registro público `rol` solo puede ser `comprador` (por defecto) o
`vendedor`; un vendedor necesita `nombreNegocio` y `categoria`.

## Cuenta con sesión

| Método | Ruta | Cuerpo | Respuesta |
|--------|------|--------|-----------|
| GET | `/api/favoritos` | — | `["sellerId", …]` |
| POST | `/api/favoritos/<sellerId>` | — | `{ marcado: bool }` (alterna) |
| POST | `/api/calificaciones` | `{ productoId, estrellas: 1-5, comentario? }` | `{ ok }`. Solo comprador o admin; no sobre productos propios. Una reseña por persona y producto (se sobrescribe). |

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
| DELETE | `/api/moderacion/usuarios/<id>` | admin | — (borra negocio, productos y favoritos en cascada) |

Nadie puede bloquear ni borrar su propia cuenta (400). Un moderador no puede
bloquear a otro moderador ni a un administrador (403). Un `id` que no es UUID
responde 404.

## Administración (solo `admin`)

| Método | Ruta | Cuerpo |
|--------|------|--------|
| POST | `/api/admin/usuarios` | Igual que el registro, con `rol` cualquiera de los cuatro. |
| PATCH | `/api/admin/apariencia` | Cualquier subconjunto de `titulo, menuInicio, menuBusqueda, menuMapa, menuPerfil, iconoInicio, iconoBusqueda, iconoMapa, iconoPerfil, logoUrl, iconoUrl, fotoPortadaUrl`. |
| POST | `/api/admin/medios` | `{ nombre: "foto.png", datos: "<base64>" }` → 201 `{ url: "/medios/…" }`. JPG/PNG/WEBP/GIF, máx. 1.5 MB. |
| GET | `/api/admin/conexion` | — → `{ host, puerto, base, usuario, ssl, tieneContrasena, conectada, usaEntorno }` |
| POST | `/api/admin/conexion/probar` | `{ host, puerto, base, usuario, contrasena?, ssl }` |
| PATCH | `/api/admin/conexion` | Igual que probar, o `{ restaurarEntorno: true }`. Reconecta en caliente y guarda en `DATOS_PATH/conexion.json`. |

## Objetos

**usuario:** `id, nombre, apellido, correo, rol, telefono, numeroControl, carrera, fotoPerfilUrl, bloqueado, perfilEditable`

**vendedor:** `id, userId, nombreNegocio, categoria, subtipo, descripcion, horarioApertura, horarioCierre, diasAtencion, horarioTexto, disponible, edificio, destacado, whatsapp, telegram, messenger, instagram, telefonoFijo, aceptaMensajesApp, promedioEstrellas, totalResenas` (las dos últimas suman las reseñas de todos sus productos)

**producto:** `id, sellerId, nombre, descripcion, precio, fotoUrl, agotado, vecesVendido, promedioEstrellas, totalResenas`
