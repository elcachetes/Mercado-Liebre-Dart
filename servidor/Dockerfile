# API de Mercado Liebre (Dart compilado a binario nativo).
# El contexto de build es la raíz del repositorio:
#   docker build -f servidor/Dockerfile -t mercado-liebre-api .

# ── Compilación ───────────────────────────────────────────────────────────
FROM dart:stable AS build
WORKDIR /app/servidor
# Primero solo las dependencias, para reutilizar la caché de Docker.
COPY servidor/pubspec.yaml servidor/pubspec.lock ./
RUN dart pub get
COPY servidor/ ./
RUN dart pub get --offline \
    && dart compile exe bin/servidor.dart -o /app/servidor_bin

# ── Imagen final ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim
# ca-certificates: PostgreSQL con SSL. curl: HEALTHCHECK.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --home-dir /app liebre \
    && mkdir -p /app/datos \
    && chown liebre /app/datos
WORKDIR /app
COPY --from=build /app/servidor_bin /app/servidor
COPY db/schema.sql /app/db/schema.sql

ENV PORT=8080 \
    APLICAR_ESQUEMA=true \
    SCHEMA_PATH=/app/db/schema.sql \
    DATOS_PATH=/app/datos

# /app/datos guarda fotos subidas y la conexión editada por el admin.
VOLUME ["/app/datos"]
USER liebre
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT}/salud" || exit 1
CMD ["/app/servidor"]
