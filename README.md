# Módulo de Balanceo Total de Hechizos + Addon Dinámico

### Para AzerothCore 3.3.5a

**Rebalancea cualquier hechizo del juego desde una tabla de la base de datos — y que el jugador vea los números reales en su tooltip, sin repartirle un solo parche.**

Cambias un número, escribes `.reload spell_regulator` y ya está: sin recompilar, sin reiniciar el servidor y sin tocar los DBC del cliente.

```sql
UPDATE spellregulator SET percentage = 60 WHERE spellId = 133;
```
```
.reload spell_regulator
```

Bola de Fuego pega ahora un 60%. Y el tooltip de todos tus jugadores lo dice.

---

## El problema que resuelve

Rebalancear un servidor privado siempre ha tenido el mismo cuello de botella: puedes cambiar el daño en el servidor, pero el cliente sigue leyendo su `Spell.dbc` y enseñando el número viejo. El jugador lee 564 y recibe 282, y no entiende nada.

La salida clásica es editar los DBC y repartir un parche nuevo cada vez que ajustas algo. Aquí no: el servidor le manda al addon lo que ha cambiado y el tooltip se reescribe solo, en caliente.

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

Hace **dos pasadas independientes**, igual que las dos columnas de la tabla: una sobre los números de la descripción (`percentage`) y otra sobre la línea del coste (`power_pct`). Puedes tocar solo el maná y dejar el daño intacto, y el tooltip lo refleja.

No toca ningún DBC. El servidor le envía las dos tablas por AIO al entrar y cada vez que cambian, así que un `.reload spell_regulator` se refleja solo.


### Lo que el addon no puede saber

El número que muestra es *valor del DBC × porcentaje de la tabla*: una predicción, no una lectura del aura aplicada.

Sale igual para todos los que tengan el addon, porque no depende de quién lanzó el hechizo. Pero por esa misma razón, si el lanzador tiene talentos o equipo que mejoran el efecto, verás la base regulada y no su valor real mejorado.

No es un fallo del addon: en 3.3.5 el servidor no le manda al cliente la cantidad real de cada efecto de aura, así que el WoW original tiene exactamente la misma limitación.

---

## Instalación

**1. El módulo**

```bash
cd azerothcore/modules
git clone https://github.com/neeme22/M-dulo-de-Balanceo-Total-de-Hechizos-Addon-Din-mico-para-AzerothCore.git mod-spellregulator
```

> La carpeta **tiene que llamarse** `mod-spellregulator`: las rutas de los `#include` del core apuntan ahí.

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

**neeme22**

Reescritura y ampliación sobre la idea original de [mod-spell-regulator](https://github.com/azerothcore/mod-spell-regulator) de ViperDev. Publicado bajo GPL-3, igual que el original.

Añadido en esta versión: regulación del coste de poder, ajuste por criatura, enganche en curación y en el valor de auras, columna de comentarios, SQL no destructivo y el addon de tooltips para el cliente.
