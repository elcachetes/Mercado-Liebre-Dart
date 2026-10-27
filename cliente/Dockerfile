# App web de Mercado Liebre (Flutter → HTML/JS servido por nginx).
# El contexto de build es la raíz del repositorio:
#   docker build -f cliente/Dockerfile --build-arg API_BASE_URL=same -t mercado-liebre-web .
#
# API_BASE_URL=same hace que la app llame a /api en su mismo dominio;
# nginx reenvía esas rutas al servicio "api" (ver cliente/nginx.conf).

# Imagen de Flutter. Para fijar una versión exacta usa, por ejemplo,
#   --build-arg FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:3.41.0
ARG FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:stable

# ── Compilación ───────────────────────────────────────────────────────────
FROM ${FLUTTER_IMAGE} AS build
WORKDIR /app
# Primero solo las dependencias, para reutilizar la caché de Docker.
COPY cliente/pubspec.yaml cliente/pubspec.lock ./
RUN flutter pub get
COPY cliente/ ./
ARG API_BASE_URL=same
RUN flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=${API_BASE_URL}

# ── Imagen final ──────────────────────────────────────────────────────────
FROM nginx:1.27-alpine
COPY cliente/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/nginx-salud || exit 1
