-- =========================================================
-- mod-spellregulator: tabla global de regulacion
-- =========================================================
-- Una fila por hechizo. Los porcentajes son independientes:
--
--   percentage  -> % de dano, curacion y valor de aura (buffs, escudos, DoT)
--   power_pct   -> % del coste de poder (mana, ira, energia, runas, foco)
--
-- En ambos: 100 = sin cambios, 50 = la mitad, 200 = el doble.
-- En power_pct, 0 = el hechizo pasa a ser gratuito.
--
-- Para ajustes por criatura concreta, ver npc_spell_amplification.sql,
-- que tiene prioridad sobre esta tabla para el dano/curacion.
-- =========================================================

CREATE TABLE IF NOT EXISTS `spellregulator` (
  `spellId`    INT(11) UNSIGNED NOT NULL,
  `percentage` FLOAT NOT NULL DEFAULT 100 COMMENT '% de dano/curacion/aura. 100 = sin cambios',
  `power_pct`  FLOAT NOT NULL DEFAULT 100 COMMENT '% del coste de poder. 100 = sin cambios, 0 = gratis',
  `comment`    VARCHAR(128) DEFAULT NULL COMMENT 'nota para acordarte de que es este hechizo',
  PRIMARY KEY (`spellId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ejemplos (descomentar para probar):
-- INSERT INTO `spellregulator` VALUES (133,  50, 100, 'Bola de Fuego: mitad de dano, coste normal');
-- INSERT INTO `spellregulator` VALUES (585, 100,  50, 'Descarga: dano normal, mitad de mana');
-- INSERT INTO `spellregulator` VALUES (100,  75,   0, 'Carga: 75% de dano y sin coste de ira');
