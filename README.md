# Total Spell Balancing Module + Dynamic Addon

### For AzerothCore 3.3.5a

*[Léeme en español](README.es.md)*

**Rebalance any spell in the game from a single database table — and let players see the real numbers in their tooltips, without shipping them a single patch.**

Change a number, type `.reload spell_regulator`, and that's it: no recompiling, no server restart, and no touching the client's DBC files.

```sql
UPDATE spellregulator SET percentage = 60 WHERE spellId = 133;
```
```
.reload spell_regulator
```

Fireball now hits for 60%. And every one of your players' tooltips says so.

---

## The problem it solves

Rebalancing a private server has always hit the same wall: you can change the damage on the server, but the client keeps reading its own `Spell.dbc` and showing the old number. The player reads 564, takes 282, and has no idea what happened.

The usual way out is editing the DBCs and shipping a new patch every time you tweak something. Not here: the server tells the addon what changed and the tooltip rewrites itself, live.

---

## What it does

| Adjustment | Column | Scope |
|---|---|---|
| Direct damage | `percentage` | player and creature spells |
| Periodic damage (DoT) | `percentage` | every tick |
| Direct and periodic healing | `percentage` | HoTs included |
| Aura amounts | `percentage` | stat buffs, absorption shields |
| **Power cost** | **`power_pct`** | **mana, rage, energy, runes, focus** |

Plus **per-creature** adjustment: the same spell can hit for different amounts depending on which NPC casts it.

In every column: `100` = unchanged, `50` = half, `200` = double. In `power_pct`, `0` makes the spell free.

---

## Example

```sql
INSERT INTO spellregulator (spellId, percentage, power_pct, comment) VALUES
  (133,  50, 100, 'Fireball: half damage, normal cost'),
  (585, 100,  50, 'Smite: normal damage, half mana'),
  (100,  75,   0, 'Charge: 75% damage and no rage cost');
```

```
.reload spell_regulator
```

To make one specific boss hit harder with Fireball without touching mages:

```sql
INSERT INTO npc_spell_amplification (creature_entry, spell_id, amplification)
VALUES (12435, 133, 300);
```

The per-NPC table **takes priority** over the global one. An NPC with no row of its own inherits the global percentage.

---

## The client addon

The server can cut a spell to 50%, but the client keeps reading its `Spell.dbc` and showing the old number in the description. The player sees 564 and takes 282.

`client-addon/SpellRegTooltip` fixes that. It rewrites the tooltip numbers with the real values — in the spellbook, the action bar, the aura bar and the shapeshift bar.

It makes **two independent passes**, mirroring the two columns of the table: one over the description numbers (`percentage`) and one over the cost line (`power_pct`). You can touch only the mana and leave the damage alone, and the tooltip reflects it.

It touches no DBC. The server sends both tables over AIO on login and whenever they change, so a `.reload spell_regulator` shows up on its own.

### What the addon cannot know

The number it shows is *DBC value × table percentage*: a prediction, not a reading of the applied aura.

It comes out the same for everyone running the addon, because it does not depend on who cast the spell. But for that very reason, if the caster has talents or gear that improve the effect, you will see the regulated base rather than their real, improved value.

This is not an addon bug: on 3.3.5 the server never sends the client the real amount of each aura effect, so vanilla WoW has exactly the same limitation.

---

## Installation

**1. The module**

```bash
cd azerothcore/modules
git clone https://github.com/neeme22/M-dulo-de-Balanceo-Total-de-Hechizos-Addon-Din-mico-para-AzerothCore.git mod-spellregulator
```

> The folder **must be named** `mod-spellregulator`: the core's `#include` paths point there.

**2. The database**

Fresh install:
```
data/sql/db-world/spellregulator.sql
data/sql/db-world/npc_spell_amplification.sql
```

Already had an older version? Just this one, which adds the cost column without touching your rows:
```
data/sql/db-world/updates/2026_09_01_00_power_pct.sql
```

**3. Re-run cmake** and build.

**4. The addon** (optional): copy `client-addon/SpellRegTooltip` into `Interface/AddOns` and `lua/spellregulator_tooltip_server.lua` into your Eluna folder. Requires AIO.

---

## How it works

Two `unordered_map`s held in memory, loaded at startup and on every `.reload`. The cost lookup only stores rows that actually change something, so unregulated spells pay nothing for the extra step.

The cost adjustment is applied in `SpellInfo::CalcPowerCost`, the single choke point every calculation goes through: the real spend on cast, the one pet AI checks to decide whether it can afford the spell, and the one creature scripts use. No path is left out.

---

### Languages

Tested on **esES** and **enUS**. The addon does not depend on any particular language: it identifies the spell with `GetSpellLink` using the name the client itself displays, and the number scaling is pure arithmetic. It recognises whichever thousands separator the client uses (`1.234` or `1,234`) and writes it back the same way.

The words used to classify lines — cost, range, cast time, duration — are present in both languages. For another language, add its terms to `META`, `UNIDADES` and `ANTES_MALO` at the top of the addon file.

---

## Requirements

- AzerothCore (`master` branch)
- MySQL 5.7 or newer
- For the addon: Eluna with AIO, and a 3.3.5a client

---

## Author

**neeme22**

A rewrite and extension of the original idea behind [mod-spell-regulator](https://github.com/azerothcore/mod-spell-regulator) by ViperDev. Released under GPL-3, same as the original.

Added in this version: power cost regulation, per-creature adjustment, hooks into healing and aura amounts, a comment column, non-destructive SQL, and the client-side tooltip addon.
