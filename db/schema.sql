-- Esquema de Mercado Liebre. Se puede aplicar en cada arranque:
-- los tipos ignoran duplicate_object y las tablas usan IF NOT EXISTS.

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('admin', 'moderador', 'vendedor', 'comprador');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE seller_category AS ENUM ('producto', 'comida', 'servicio');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL,
  apellido TEXT NOT NULL,
  correo TEXT NOT NULL UNIQUE,
  telefono TEXT,
  numero_control TEXT,
  carrera TEXT,
  password_hash TEXT NOT NULL,
  rol user_role NOT NULL DEFAULT 'comprador',
  bloqueado BOOLEAN NOT NULL DEFAULT FALSE,
  foto_perfil_url TEXT,
  perfil_editable BOOLEAN NOT NULL DEFAULT FALSE,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sellers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users (id) ON DELETE CASCADE,
  nombre_negocio TEXT NOT NULL,
  categoria seller_category NOT NULL,
  subtipo TEXT,
  descripcion TEXT,
  horario_apertura TIME,
  horario_cierre TIME,
  dias_atencion TEXT NOT NULL DEFAULT 'Lun-Vie',
  disponible BOOLEAN NOT NULL DEFAULT TRUE,
  edificio TEXT,
  destacado BOOLEAN NOT NULL DEFAULT FALSE,
  destacado_hasta TIMESTAMPTZ,
  whatsapp TEXT,
  telegram TEXT,
  messenger TEXT,
  instagram TEXT,
  telefono_fijo TEXT,
  acepta_mensajes_app BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id UUID NOT NULL REFERENCES sellers (id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  precio NUMERIC(12, 2) NOT NULL,
  descripcion TEXT,
  foto_url TEXT,
  agotado BOOLEAN NOT NULL DEFAULT FALSE,
  veces_vendido INTEGER NOT NULL DEFAULT 0,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ratings (
  product_id UUID NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  buyer_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  estrellas INTEGER NOT NULL CHECK (estrellas BETWEEN 1 AND 5),
  comentario TEXT,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (product_id, buyer_id)
);

CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  seller_id UUID NOT NULL REFERENCES sellers (id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, seller_id)
);

CREATE TABLE IF NOT EXISTS ajustes (
  clave TEXT PRIMARY KEY,
  valor TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo TEXT NOT NULL,
  contenido TEXT NOT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  publicado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices para las consultas frecuentes de la API. Las llaves primarias y
-- UNIQUE ya crean los suyos (users.correo, sellers.user_id, favorites, ratings).
CREATE INDEX IF NOT EXISTS idx_products_seller ON products (seller_id);
CREATE INDEX IF NOT EXISTS idx_products_vendidos ON products (veces_vendido DESC);
CREATE INDEX IF NOT EXISTS idx_sellers_disponible ON sellers (disponible) WHERE disponible;
CREATE INDEX IF NOT EXISTS idx_ratings_buyer ON ratings (buyer_id);
CREATE INDEX IF NOT EXISTS idx_favorites_seller ON favorites (seller_id);

-- Verificación de correo. Las cuentas que ya existían quedan verificadas
-- (DEFAULT TRUE al agregar la columna); el registro público inserta FALSE
-- explícitamente y la cuenta se verifica con el enlace del correo.
ALTER TABLE users ADD COLUMN IF NOT EXISTS correo_verificado BOOLEAN NOT NULL DEFAULT TRUE;

-- Reseñas escritas por vendedores: nacen sin aprobar (aprobada = FALSE) y no
-- se muestran ni cuentan en los promedios hasta que el administrador las
-- aprueba, para frenar reseñas falsas de la competencia. Las de compradores
-- y las que ya existían quedan aprobadas (DEFAULT TRUE).
ALTER TABLE ratings ADD COLUMN IF NOT EXISTS aprobada BOOLEAN NOT NULL DEFAULT TRUE;
CREATE INDEX IF NOT EXISTS idx_ratings_pendientes ON ratings (creado_en) WHERE NOT aprobada;

CREATE OR REPLACE VIEW product_ratings_summary AS
SELECT
  product_id,
  AVG(estrellas)::float8 AS promedio_estrellas,
  COUNT(*)::int AS total_resenas
FROM ratings
WHERE aprobada
GROUP BY product_id;

-- Carruseles de publicidad: 2 secciones (arriba y abajo de la barra lateral)
-- con 3 posiciones cada una. Cada anuncio lleva a la ficha de un negocio;
-- si ese negocio se elimina, su anuncio se borra con él (ON DELETE CASCADE).
-- Un anuncio sin negocio (seller_id NULL) solo se muestra, no abre nada.
CREATE TABLE IF NOT EXISTS anuncios (
  seccion SMALLINT NOT NULL CHECK (seccion BETWEEN 1 AND 2),
  posicion SMALLINT NOT NULL CHECK (posicion BETWEEN 1 AND 3),
  imagen_url TEXT NOT NULL,
  seller_id UUID REFERENCES sellers (id) ON DELETE CASCADE,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (seccion, posicion)
);

-- Migración: antes había un solo anuncio por sección guardado en `ajustes`.
-- Se copia a la posición 1 y se borra la clave vieja para que no regrese
-- en el siguiente arranque si el administrador lo quita.
INSERT INTO anuncios (seccion, posicion, imagen_url)
SELECT 1, 1, valor FROM ajustes WHERE clave = 'publicidad1Url' AND valor <> ''
ON CONFLICT DO NOTHING;
INSERT INTO anuncios (seccion, posicion, imagen_url)
SELECT 2, 1, valor FROM ajustes WHERE clave = 'publicidad2Url' AND valor <> ''
ON CONFLICT DO NOTHING;
DELETE FROM ajustes
WHERE clave IN ('publicidad1Url', 'publicidad1Enlace', 'publicidad2Url', 'publicidad2Enlace');

-- Restablecimientos de contraseña. Cada enlace enviado por correo apunta a
-- una fila (el token firmado lleva su id) y solo sirve una vez: al usarse se
-- llena usado_en. El administrador puede anularlos desde su panel.
-- origen: 'correo' (la persona lo pidió) o 'admin' (enlace o cambio directo).
CREATE TABLE IF NOT EXISTS restablecimientos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  origen TEXT NOT NULL,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  vence_en TIMESTAMPTZ NOT NULL,
  usado_en TIMESTAMPTZ,
  anulado BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_restablecimientos_user ON restablecimientos (user_id);
CREATE INDEX IF NOT EXISTS idx_restablecimientos_creado ON restablecimientos (creado_en DESC);

-- Último uso de la app: inicio de sesión o cualquier petición con token.
-- Se anota como máximo una vez por hora. El panel de administración lo usa
-- para encontrar negocios abandonados ("fantasma"). El DEFAULT cuenta el
-- registro como uso; las cuentas que ya existían empiezan con la fecha en
-- que se agregó la columna (la inactividad se mide desde ese despliegue).
ALTER TABLE users ADD COLUMN IF NOT EXISTS ultimo_acceso TIMESTAMPTZ DEFAULT now();

-- Logo y foto de la tienda que sube el vendedor (`/medios/...`). Se borran
-- del disco al eliminar el negocio o la cuenta (Repositorio.eliminarNegocio
-- y eliminarUsuario los devuelven).
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS logo_url TEXT;
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS portada_url TEXT;
