# Spell Regulator

**Ajusta el daño, la curación y el coste de cualquier hechizo de AzerothCore desde la base de datos, sin tocar los DBC del cliente.**

Cambias un número en una tabla, escribes `.reload spell_regulator` y el efecto es inmediato: sin recompilar, sin reiniciar y sin repartir parches a los jugadores.

---

## Qué hace

| Ajuste | Columna | Alcance |
|---|---|---|
| Daño directo | `percentage` | hechizos de jugadores y criaturas |
| Daño periódico (DoT) | `percentage` | cada tick |
| Curación directa y periódica | `percentage` | incluye HoT |
| Valor de auras | `percentage` | buffs de estadísticas, escudos de absorción |
| **Coste de poder** | **`power_pct`** | **maná, ira, energía, runas, foco** |

Y además, ajuste **por criatura concreta**: el mismo hechizo puede pegar distinto según qué NPC lo lance.

En todas las columnas: `100` = sin cambios, `50` = la mitad, `200` = el doble. En `power_pct`, `0` deja el hechizo gratuito.

---

## Ejemplo

```sql
INSERT INTO spellregulator (spellId, percentage, power_pct, comment) VALUES
  (133,  50, 100, 'Bola de Fuego: mitad de daño, coste normal'),
  (585, 100,  50, 'Descarga: daño normal, mitad de maná'),
  (100,  75,   0, 'Carga: 75% de daño y sin coste de ira');
```

```
.reload spell_regulator
```

Para que un jefe concreto pegue más fuerte con Bola de Fuego sin tocar a los magos:

```sql
INSERT INTO npc_spell_amplification (creature_entry, spell_id, amplification)
VALUES (12435, 133, 300);
```

La tabla por NPC **tiene prioridad** sobre la global. Si un NPC no tiene fila propia, hereda el porcentaje global.

---

## El addon del cliente

El servidor puede reducir un hechizo al 50%, pero el cliente sigue leyendo su `Spell.dbc` y enseñando el número viejo en la descripción. El jugador ve 564 y recibe 282.

`client-addon/SpellRegTooltip` corrige eso. Reescribe los números del tooltip con los valores reales, en el libro de hechizos, la barra de acciones, las auras y la barra de formas.

No toca ningún DBC. El servidor le envía la tabla por AIO al entrar y cada vez que cambia, así que un `.reload spell_regulator` se refleja solo.

```
/spellreg          ver estado
/spellreg debug    ver qué líneas está tocando
```

---

## Instalación

**1. El módulo**

```bash
cd azerothcore/modules
git clone <este-repo> mod-spellregulator
```

**2. Los enganches al core**

El módulo necesita seis puntos de enganche. En cada fichero, añade el `include` arriba:

```cpp
#include "../../../../../modules/mod-spellregulator/src/SpellRegulator.h"
```

<details>
<summary><b>src/server/game/Entities/Unit/Unit.cpp</b> — cuatro llamadas</summary>

```cpp
// En DealDamage, tras el hook sScriptMgr->OnDamage:
if ((damagetype == SPELL_DIRECT_DAMAGE || damagetype == DOT) && spellProto)
    sSpellRegulator->Regulate(damage, spellProto->Id, attacker, "DealDmg");

// Al principio de SendSpellNonMeleeDamageLog:
sSpellRegulator->Regulate(log->damage, log->spellInfo->Id, log->attacker, "NonMeleeLog");

// Al principio de SendPeriodicAuraLog:
sSpellRegulator->Regulate(pInfo->damage, aura->GetId(), aura->GetCaster(), "PeriodicLog");

// En el cálculo de curación:
sSpellRegulator->Regulate(heal, healInfo.GetSpellInfo()->Id, healInfo.GetHealer(), "Heal");
```
</details>

<details>
<summary><b>src/server/game/Spells/Auras/SpellAuraEffects.cpp</b> — valor de auras</summary>

```cpp
// En CalculateAmount, sobre el valor ya calculado:
sSpellRegulator->Regulate(tmp, GetId(), caster, "CalcAmt");
```
</details>

<details>
<summary><b>src/server/game/Spells/SpellInfo.cpp</b> — coste de poder</summary>

Al final de `CalcPowerCost`, **después** del multiplicador por escuela y **antes** del `if (powerCost < 0)`:

```cpp
sSpellRegulator->RegulatePowerCost(powerCost, Id);
```

Va ahí a propósito: así el porcentaje se aplica sobre el coste que ya han modificado los talentos y las auras de reducción, no sobre el coste base del DBC.
</details>

<details>
<summary><b>src/server/scripts/Commands/cs_reload.cpp</b> — el comando</summary>

```cpp
{ "spell_regulator", HandleReloadSpellRegulator, SEC_ADMINISTRATOR, Console::Yes },
```

```cpp
static bool HandleReloadSpellRegulator(ChatHandler* handler)
{
    sSpellRegulator->LoadFromDB();
    handler->SendGlobalGMSysMessage("DB table `spellregulator` reloaded.");
    return true;
}
```
</details>

**3. La base de datos**

Instalación nueva:
```
data/sql/db-world/spellregulator.sql
data/sql/db-world/npc_spell_amplification.sql
```

¿Ya tenías el módulo de antes? Solo esto, que añade la columna del coste sin tocar tus filas:
```
data/sql/db-world/updates/2026_09_01_00_power_pct.sql
```

**4. Compila** y ejecuta cmake de nuevo.

**5. El addon** (opcional): copia `client-addon/SpellRegTooltip` a `Interface/AddOns` y `lua/spellregulator_tooltip_server.lua` a tu carpeta de Eluna. Necesita AIO.

---

## Cómo funciona

Dos `unordered_map` en memoria, cargados al arrancar y en cada `.reload`. El lookup del coste solo guarda las filas que cambian algo, así que los hechizos sin regular no pagan nada por el paso extra.

El ajuste de coste se aplica en `SpellInfo::CalcPowerCost`, que es el punto único por el que pasan todos los cálculos: el gasto real al lanzar, el que mira la IA de las mascotas para decidir si puede permitirse el hechizo y el que usan los scripts de criatura. Ningún camino se queda fuera.

---

## Requisitos

- AzerothCore (rama `master`)
- MySQL 5.7 o superior
- Para el addon: Eluna con AIO, y cliente 3.3.5a

---

## Autor

**pelianzaba**

Reescritura y ampliación sobre la idea original de [mod-spell-regulator](https://github.com/azerothcore/mod-spell-regulator) de ViperDev. Publicado bajo GPL-3, igual que el original.

Añadido en esta versión: regulación del coste de poder, ajuste por criatura, enganche en curación y en el valor de auras, columna de comentarios, SQL no destructivo y el addon de tooltips para el cliente.
