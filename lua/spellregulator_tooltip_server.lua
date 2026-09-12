--[[--------------------------------------------------------------------------
  spellregulator_tooltip_server.lua

  Manda a los clientes el porcentaje que mod-spellregulator aplica a cada
  hechizo, para que el addon pueda reescribir la descripcion del tooltip.

  Se envian las dos columnas de la tabla GLOBAL (`spellregulator`):
  `percentage` (dano/curacion) y `power_pct` (coste de poder).
  Los overrides por NPC
  (`npc_spell_amplification`) no se mandan a proposito: son hechizos de
  criatura, de los que el jugador nunca ve el tooltip.

  Se salta las filas con 100 y con 0, porque el modulo trata las dos como
  "sin cambios" (mira LookupPercent/Regulate en SpellRegulator.h).

  CUANDO SE RELEE LA TABLA
  Antes se sondeaba la base de datos cada 5 s para siempre. Ahora se relee
  solo cuando alguien recarga el modulo de verdad, escuchando el comando
  (evento 42). Asi el cliente se entera exactamente cuando se entera el C++,
  y no hay un SELECT en el hilo del mundo cada 5 segundos.

  Comandos que recargan la tabla en el core (cs_reload.cpp):
      .reload spell_regulator      -> HandleReloadSpellRegulator
      .reload all spell            -> HandleReloadAllSpellCommand
      .reload all                  -> HandleReloadAllCommand
----------------------------------------------------------------------------]]

local AIO = AIO or require("AIO")

local Handlers = AIO.AddHandlers("SpellReg", {})

local cache      = {}   -- [spellId] = % de dano/curacion
local cacheCoste = {}   -- [spellId] = % del coste de poder
local firma      = nil  -- huella de la tabla, para no reenviar sin cambios

----------------------------------------------------------------- lectura

-- Devuelve las dos tablas y una huella NUMERICA.
-- La huella de antes concatenaba una cadena por fila ("id=pct/coste") y las
-- pegaba todas: con muchas filas eso son cientos de KB de basura por lectura.
-- Aqui se acumula un entero y se construye una sola cadena corta al final.
local function LeerTabla()
    local t, tc = {}, {}
    local n, suma = 0, 0
    -- Se piden las filas donde cambie ALGO: una fila puede dejar el dano
    -- intacto y tocar solo el mana, o al reves.
    local q = WorldDBQuery(
        "SELECT spellId, percentage, power_pct FROM spellregulator " ..
        "WHERE (percentage <> 100 AND percentage <> 0) OR power_pct <> 100 " ..
        "ORDER BY spellId")
    if q then
        repeat
            local id    = q:GetUInt32(0)
            local pct   = q:GetFloat(1)
            local coste = q:GetFloat(2)
            if pct ~= 100 and pct ~= 0 then
                t[id] = pct
            end
            if coste ~= 100 then
                tc[id] = coste
            end
            n = n + 1
            suma = (suma + id * 31 + pct * 7 + coste * 13) % 2147483647
        until not q:NextRow()
    end
    return t, tc, n .. ":" .. suma
end

----------------------------------------------------------------- envio

-- Los bots de playerbots no tienen addon (ni cliente), pero el evento de
-- login dispara igual con ellos. Sin este corte, cada bot que entra obliga a
-- serializar y comprimir la tabla entera en AIO para tirarla a la basura.
local function EsBot(player)
    if type(player.IsBot) ~= "function" then return false end
    local ok, res = pcall(player.IsBot, player)
    return ok and res == true
end

local function Enviar(player)
    if not player then return end
    if EsBot(player) then return end
    AIO.Handle(player, "SpellReg", "Set", cache, cacheCoste)
end

local function EnviarATodos()
    local jugadores = GetPlayersInWorld()
    if not jugadores then return end
    for _, p in pairs(jugadores) do
        Enviar(p)
    end
end

-- El cliente puede pedir la tabla por su cuenta (al cargar el addon).
function Handlers.Pedir(player)
    Enviar(player)
end

----------------------------------------------------------------- recarga

local function Recargar(avisar)
    local t, tc, f = LeerTabla()
    if f == firma then return false end
    firma, cache, cacheCoste = f, t, tc
    if avisar then EnviarATodos() end
    return true
end

-- `reload all locales` tambien empieza por "reload all", asi que "all" se
-- acepta solo cuando no lleva nada detras.
local function EsComandoDeRecarga(cmd)
    cmd = string.gsub(string.lower(cmd or ""), "^%s+", "")
    if string.find(cmd, "^reload%s+spell_regulator") then return true end
    if string.find(cmd, "^reload%s+all%s+spell") then return true end
    if string.find(cmd, "^reload%s+all%s*$") then return true end
    return false
end

-- OJO: el evento 42 es un hook PREVIO, salta antes de que el core ejecute el
-- comando. Leemos la tabla nosotros (no los mapas del C++), asi que el orden
-- da igual, pero se espera un tick para no depender de eso.
-- Devolver true NO bloquea el comando: CallAllFunctionsBool solo invierte el
-- resultado si un handler devuelve false.
local function AlComando(event, player, command, handler)
    if EsComandoDeRecarga(command) then
        CreateLuaEvent(function() Recargar(true) end, 100, 1)
    end
    return true
end

local function AlEntrar(event, player)
    Enviar(player)
end

Recargar(false)                             -- carga inicial
RegisterPlayerEvent(42, AlComando)          -- 42 = PLAYER_EVENT_ON_COMMAND
RegisterPlayerEvent(3, AlEntrar)            -- 3  = PLAYER_EVENT_ON_LOGIN

print("[SpellRegulator] tooltip: servidor listo. Se relee con "
      .. ".reload spell_regulator (tambien .reload all spell / .reload all)")
