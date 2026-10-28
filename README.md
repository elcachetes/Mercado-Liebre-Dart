# Mercado Liebre

Mercado estudiantil del **ITCJ**. Las personas del plantel encuentran quién
vende comida, productos o servicios, dónde está su puesto en el mapa del
campus y si está abierto ahora. Quien vende administra su catálogo, horario y
contacto desde la misma app.

- **Sin cuenta:** ver vendedores abiertos, destacados, más vendidos, buscar y
  usar el mapa.
- **Con cuenta:** calificar productos, guardar favoritos y, si se quiere,
  registrar teléfono, número de control y carrera para recibir promociones.
- **Buscar y explorar:** por texto o por categoría, solo lo abierto o todo, y
  ordenado por nombre, estrellas o número de reseñas.
- **Vendedor:** abrir/cerrar el puesto, catálogo con fotos, horario por días,
  contacto y punto en el mapa.
- **Moderador / Administrador:** bloquear o eliminar cuentas, crear cuentas,
  cambiar la apariencia (nombre, menús, logo, portada) y la conexión a la base.

## Arquitectura

```
Navegador / Android / iOS / Windows
            │  HTTPS
            ▼
┌───────────────────────┐   /api, /medios, /salud   ┌──────────────────┐        ┌────────────┐
│ web  (nginx + Flutter)│ ────────────────────────▶ │ api  (Dart/shelf)│ ─────▶ │ PostgreSQL │
│ cliente/              │                           │ servidor/        │        │ db/        │
└───────────────────────┘                           └──────────────────┘        └────────────┘
```

| Carpeta      | Qué es                                                            | Lenguaje            |
|--------------|-------------------------------------------------------------------|---------------------|
| `cliente/`   | App Flutter (web, Android, iOS, Windows). Solo habla HTTP.        | Dart + Flutter      |
| `servidor/`  | API REST. **Único** proceso que se conecta a PostgreSQL.          | Dart (`shelf`)      |
| `db/`        | `schema.sql`: tablas, tipos, índices. Se aplica en cada arranque. | SQL                 |
| `docs/`      | Despliegue y referencia de la API.                                | Markdown            |

La app nunca recibe credenciales de la base. Las contraseñas se guardan como
hash PBKDF2-SHA256 y la sesión es un token firmado (HS256) de 7 días.

## Arrancar en tu máquina

### Opción A: todo con Docker (lo más parecido a producción)

```bash
cp .env.example .env        # y cambia las contraseñas
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build
```

Abre <http://localhost:8080>. Entra con `ADMIN_CORREO` / `ADMIN_PASSWORD` del `.env`.

### Opción B: API y app por separado (para desarrollar)

Necesitas Flutter 3.41+ y un PostgreSQL 13+ con una base `mercado_liebre`.

```bash
# 1. API (lee ../.env; aplica db/schema.sql al arrancar)
cd servidor
dart pub get
dart run bin/servidor.dart          # escucha en http://127.0.0.1:8080

# 2. App (en otra terminal)
cd cliente
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

En el emulador de Android usa `API_BASE_URL=http://10.0.2.2:8080`.

## Pruebas y análisis

```bash
cd servidor && dart analyze && dart test
cd cliente  && flutter analyze && flutter test
```

`cliente/test/plano_sincronizado_test.dart` verifica que los códigos del mapa
coincidan entre cliente y servidor.

## Desplegar

Guía paso a paso para **Ubuntu Server 22.04 + Coolify**:
[docs/DESPLIEGUE.md](docs/DESPLIEGUE.md).

## Variables de entorno

| Variable            | Obligatoria | Uso                                                                 |
|---------------------|-------------|---------------------------------------------------------------------|
| `DATABASE_URL`      | Sí          | URL de PostgreSQL. En Coolify, la *Postgres URL (internal)* del recurso de base. Nunca en el repositorio. |
| `APP_SECRET_KEY`    | Sí          | Firma de los tokens. ≥ 16 caracteres (`openssl rand -hex 32`).      |
| `ADMIN_CORREO`      | No          | Crea esta cuenta admin al arrancar si no existe.                    |
| `ADMIN_PASSWORD`    | No          | Contraseña de esa cuenta (≥ 8 caracteres).                          |
| `CORS_ORIGEN`       | No          | Origen permitido si otra web llama a la API. `*` por defecto.       |
| `DATABASE_SSL`      | No          | `true` si la base exige SSL (bases administradas externas).         |
| `APLICAR_ESQUEMA`   | No          | `true` por defecto: ejecuta `db/schema.sql` en cada arranque.       |
| `DATOS_PATH`        | No          | Carpeta de fotos subidas y conexión guardada. `/app/datos` en Docker.|

## Más documentación

- [docs/API.md](docs/API.md): todos los endpoints, permisos y cuerpos JSON.
- [docs/DESPLIEGUE.md](docs/DESPLIEGUE.md): servidor, Coolify, respaldos y problemas comunes.
- [AGENTS.md](AGENTS.md): convenciones del código y cómo hacer cambios comunes
  (pensado para personas nuevas y para agentes de IA).
