-- Anade la columna del coste de poder a una instalacion que ya existe.
-- Es seguro de ejecutar mas de una vez: si la columna ya esta, no hace nada.
-- Las filas existentes quedan a 100, es decir, sin ningun cambio de coste.

SET @existe := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME   = 'spellregulator'
     AND COLUMN_NAME  = 'power_pct'
);

SET @sql := IF(@existe = 0,
  'ALTER TABLE `spellregulator`
     ADD COLUMN `power_pct` FLOAT NOT NULL DEFAULT 100
     COMMENT ''% del coste de poder. 100 = sin cambios, 0 = gratis''
     AFTER `percentage`',
  'DO 0');

PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
