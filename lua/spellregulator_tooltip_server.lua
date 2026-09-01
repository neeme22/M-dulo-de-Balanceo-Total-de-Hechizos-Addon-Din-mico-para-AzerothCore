--[[--------------------------------------------------------------------------
  spellregulator_tooltip_server.lua

  Manda a los clientes el porcentaje que mod-spellregulator aplica a cada
  hechizo, para que el addon pueda reescribir la descripcion del tooltip.

  Solo se envia la tabla GLOBAL (`spellregulator`). Los overrides por NPC
  (`npc_spell_amplification`) no se mandan a proposito: son hechizos de
  criatura, de los que el jugador nunca ve el tooltip.

  Se salta las filas con 100 y con 0, porque el modulo trata las dos como
  "sin cambios" (mira LookupPercent/Regulate en SpellRegulator.h).
----------------------------------------------------------------------------]]

local AIO = AIO or require("AIO")

local INTERVALO_MS = 5000   -- cada cuanto se mira si la tabla cambio

local Handlers = AIO.AddHandlers("SpellReg", {})

local cache  = {}   -- [spellId] = porcentaje
local firma  = nil  -- huella de la tabla, para detectar cambios

local function LeerTabla()
    local t, trozos = {}, {}
    local q = WorldDBQuery(
        "SELECT spellId, percentage FROM spellregulator " ..
        "WHERE percentage <> 100 AND percentage <> 0 ORDER BY spellId")
    if q then
        repeat
            local id  = q:GetUInt32(0)
            local pct = q:GetFloat(1)
            t[id] = pct
            trozos[#trozos + 1] = id .. "=" .. pct
        until not q:NextRow()
    end
    return t, table.concat(trozos, ",")
end

local function Enviar(player)
    if player then
        AIO.Handle(player, "SpellReg", "Set", cache)
    end
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

-- Vigila la tabla. Asi se entera igual de un `.reload spell_regulator`
-- que de una edicion directa en la base de datos.
local function Vigilar()
    local t, f = LeerTabla()
    if f ~= firma then
        local primera = (firma == nil)
        firma, cache = f, t
        if not primera then
            EnviarATodos()
        end
    end
end

local function AlEntrar(event, player)
    Enviar(player)
end

Vigilar()                                   -- carga inicial
CreateLuaEvent(Vigilar, INTERVALO_MS, 0)    -- 0 = repetir siempre
RegisterPlayerEvent(3, AlEntrar)            -- 3 = PLAYER_EVENT_ON_LOGIN

print("[SpellRegulator] tooltip: servidor listo, vigilando `spellregulator` cada "
      .. (INTERVALO_MS / 1000) .. " s")
