-- ============================================================
-- quiz_db_final.sql — Esquema completo para el Quiz de Nube
-- Reemplaza quiz_db.sql + quiz_db_recomendacion.sql
--
-- Crear BD desde cero:
--   mysql -u root -p < quiz_db_final.sql
--
-- Si ya existe la BD (migración):
--   mysql -u root -p quiz_db < quiz_db_final.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS quiz_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE quiz_db;

-- ------------------------------------------------------------
-- Eliminar objetos previos si existen (para migración limpia)
-- ------------------------------------------------------------
DROP VIEW  IF EXISTS vista_intentos;
DROP VIEW  IF EXISTS vista_resultados_completa;
DROP VIEW  IF EXISTS vista_resultados;
DROP TABLE IF EXISTS respuestas;        -- ya no se utiliza
DROP TABLE IF EXISTS intentos;
DROP TABLE IF EXISTS recomendaciones;

-- ------------------------------------------------------------
-- 1. Catálogo de recomendaciones
-- ------------------------------------------------------------
CREATE TABLE recomendaciones (
  id          TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clave       VARCHAR(30)  NOT NULL UNIQUE,   -- 'publica' | 'hibrida' | 'privada'
  titulo      VARCHAR(100) NOT NULL,
  perfil      TEXT         NOT NULL,
  razon       TEXT         NOT NULL,
  tecnologias TEXT         NOT NULL,
  icono       VARCHAR(10)  NOT NULL DEFAULT '☁',
  color_hex   VARCHAR(7)   NOT NULL DEFAULT '#00d4ff'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed: las 3 recomendaciones posibles
INSERT INTO recomendaciones (clave, titulo, perfil, razon, tecnologias, icono, color_hex) VALUES
(
  'publica',
  'Nube Pública (Public Cloud)',
  'Startups, PYMES o empresas digitales modernas.',
  'Buscan agilidad, bajo costo inicial (OpEx), elasticidad para picos impredecibles y no tienen restricciones legales fuertes ni equipos grandes de infraestructura.',
  'AWS, Azure, Google Cloud — enfocándose en PaaS y Serverless.',
  '🌐',
  '#00d4ff'
),
(
  'hibrida',
  'Nube Híbrida',
  'Grandes corporativos, Banca, Retail con sucursales.',
  'Tienen sistemas heredados (Legacy) que no pueden mover fácilmente, pero necesitan la agilidad de la nube para aplicaciones nuevas. Mantener el Core en sitio o Colocation y construir las nuevas apps en Nube Pública conectadas vía VPN/Interconnect.',
  'Azure Arc, AWS Outposts, VMware Cloud Foundation, VPN/Interconnect.',
  '🔀',
  '#f0c040'
),
(
  'privada',
  'Nube Privada / On-Premises',
  'Gobierno, Defensa, Salud, Industria pesada.',
  'La regulación, la latencia ultra-baja o la depreciación de activos ya comprados hacen que la nube pública sea inviable o más cara.',
  'Modernizar el Data Center propio con Hiperconvergencia (HCI) o Nube Privada Virtual (OpenStack, Nutanix, VMware vSphere).',
  '🏛',
  '#39d353'
);

-- ------------------------------------------------------------
-- 2. Tabla de intentos (un registro por cada envío)
--    Sin columnas de calificación (puntaje / porcentaje)
-- ------------------------------------------------------------
CREATE TABLE intentos (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  equipo           VARCHAR(100)     NOT NULL DEFAULT 'Team Alpha',
  ip_cliente       VARCHAR(45)      NOT NULL,          -- soporta IPv6
  user_agent       VARCHAR(255)     NULL,
  recomendacion_id TINYINT UNSIGNED NULL
    COMMENT 'FK a recomendaciones.id',
  conteo_a         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  conteo_b         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  conteo_c         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  conteo_d         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  creado_en        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_recomendacion
    FOREIGN KEY (recomendacion_id) REFERENCES recomendaciones(id)
    ON DELETE SET NULL,
  INDEX idx_equipo     (equipo),
  INDEX idx_creado_en  (creado_en),
  INDEX idx_rec        (recomendacion_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 3. Vista de resultados con recomendación
-- ------------------------------------------------------------
CREATE VIEW vista_intentos AS
SELECT
  i.id              AS intento_id,
  i.equipo,
  i.ip_cliente,
  i.conteo_a,
  i.conteo_b,
  i.conteo_c,
  i.conteo_d,
  r.clave           AS recomendacion_clave,
  r.titulo          AS recomendacion_titulo,
  r.perfil          AS recomendacion_perfil,
  r.razon           AS recomendacion_razon,
  r.tecnologias     AS recomendacion_tecnologias,
  r.icono,
  r.color_hex,
  i.creado_en
FROM intentos i
LEFT JOIN recomendaciones r ON r.id = i.recomendacion_id
ORDER BY i.creado_en DESC;
