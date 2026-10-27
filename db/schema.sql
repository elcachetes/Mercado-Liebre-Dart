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

CREATE OR REPLACE VIEW product_ratings_summary AS
SELECT
  product_id,
  AVG(estrellas)::float8 AS promedio_estrellas,
  COUNT(*)::int AS total_resenas
FROM ratings
GROUP BY product_id;
