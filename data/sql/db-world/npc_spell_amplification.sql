-- =========================================================
-- mod-spellregulator: per-NPC spell amplification
-- =========================================================
-- Override per-NPC del % de amplificacion. Toma prioridad sobre
-- la tabla `spellregulator` (global). Si una fila (entry, spellId)
-- existe aqui, se usa esa; si no, cae a `spellregulator`; si tampoco
-- esta ahi, no se modifica el daño/heal/amount.
--
-- amplification: 100 = sin cambios, 50 = mitad, 200 = doble.
-- Aplica a todo lo que mod-spellregulator ya hookea:
--   - daño directo de spell
--   - DoT/HoT ticks
--   - heal directo
--   - absorbs (escudos)
-- =========================================================

SET FOREIGN_KEY_CHECKS=0;

DROP TABLE IF EXISTS `npc_spell_amplification`;
CREATE TABLE `npc_spell_amplification` (
  `creature_entry` int(10) unsigned NOT NULL,
  `spell_id`       int(10) unsigned NOT NULL,
  `amplification`  int(10) unsigned NOT NULL DEFAULT '100' COMMENT '100=base, 50=mitad, 200=doble',
  PRIMARY KEY (`creature_entry`,`spell_id`),
  KEY `idx_creature_entry` (`creature_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS=1;
