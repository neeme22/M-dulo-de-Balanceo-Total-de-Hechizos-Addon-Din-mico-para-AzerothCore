--[[--------------------------------------------------------------------------
  SpellRegTooltip

  Reescribe los numeros de la descripcion del tooltip aplicando el porcentaje
  que mod-spellregulator usa en el servidor, sin tocar el Spell.dbc.

  Los datos llegan por AIO desde lua_scripts/spellregulator_tooltip_server.lua.
  Si AIO no manda nada, se puede probar a mano con:
      /spellreg set <spellId> <porcentaje>
      /spellreg clear
----------------------------------------------------------------------------]]

local NOMBRE = "SpellReg"

----------------------------------------------------------------- datos

SpellRegTooltipDB = SpellRegTooltipDB or {}

local PCT = {}          -- [spellId] = % de dano/curacion (lo que manda el servidor)
local PCT_COSTE = {}    -- [spellId] = % del coste de poder (mana, ira, energia...)
local MANUAL = {}       -- pruebas locales, tienen prioridad
local MANUAL_COSTE = {}

local function Msg(t)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff88" .. NOMBRE .. "|r " .. t)
end

local function PorcentajeDe(spellId)
    local p = MANUAL[spellId]
    if p then return p end
    return PCT[spellId] or PCT[tostring(spellId)]
end

local function PorcentajeCosteDe(spellId)
    local p = MANUAL_COSTE[spellId]
    if p then return p end
    return PCT_COSTE[spellId] or PCT_COSTE[tostring(spellId)]
end

----------------------------------------------------------------- numeros

local UNIDADES = {
    ["s"] = true, ["seg"] = true, ["segs"] = true,
    ["segundo"] = true, ["segundos"] = true,
    ["min"] = true, ["mins"] = true, ["minuto"] = true, ["minutos"] = true,
    ["hora"] = true, ["horas"] = true,
    ["sec"] = true, ["secs"] = true, ["second"] = true, ["seconds"] = true,
    ["m"] = true, ["yd"] = true, ["yards"] = true, ["metros"] = true,
}

-- Palabras que, si van DELANTE del numero, dicen que no es un valor que el
-- regulador toque. "durante"/"dura"/"cada" cubren las duraciones y periodos
-- sin depender de que unidad venga detras ni de que caracter las separe,
-- que es donde fallaba antes ("durante 8 s" se escalaba a "durante 4 s").
local ANTES_MALO = {
    ["nivel"] = true, ["niveles"] = true, ["rango"] = true,
    ["level"] = true, ["rank"] = true,
    ["durante"] = true, ["dura"] = true, ["duran"] = true,
    -- OJO: "en" NO puede ir aqui. Las curaciones dicen "cura en X p. de salud"
    -- y se dejarian de escalar.
    ["cada"] = true, ["tras"] = true,
    ["during"] = true, ["lasts"] = true, ["every"] = true,
    ["over"] = true, ["for"] = true, ["after"] = true, ["within"] = true,
}

local function ConMiles(n, sep)
    sep = sep or "."
    local resto, out = tostring(n), ""
    while string.len(resto) > 3 do
        out = sep .. string.sub(resto, -3) .. out
        resto = string.sub(resto, 1, string.len(resto) - 3)
    end
    return resto .. out
end

-- Devuelve el entero y el separador de miles que traia (o nil si no es un
-- entero: "2,5" y "8.00" son decimales y no se tocan).
local function Parsear(tok)
    if string.match(tok, "^%d+$") then return tonumber(tok), nil end

    local cabeza, sep = string.match(tok, "^(%d%d?%d?)([%.,])")
    if not cabeza then return nil end

    -- a partir de la cabeza solo valen grupos exactos de separador + 3 digitos
    local pos, n = string.len(cabeza) + 1, string.len(tok)
    while pos <= n do
        if string.sub(tok, pos, pos) ~= sep then return nil end
        if not string.match(string.sub(tok, pos + 1, pos + 3), "^%d%d%d$") then return nil end
        pos = pos + 4
    end
    return tonumber((string.gsub(tok, "[%.,]", ""))), sep
end

-- El cliente en espanol separa el numero de su unidad con un espacio DURO
-- (U+00A0), no con uno normal. Sin esto, "8<duro>s" no se reconocia como
-- duracion y se escalaba: era el fallo de "durante 8 s" -> "durante 1 s".
local ESPACIOS = {
    string.char(0xC2, 0xA0),        -- U+00A0 espacio duro
    string.char(0xE2, 0x80, 0x89),  -- U+2009 espacio fino
    string.char(0xE2, 0x80, 0xAF),  -- U+202F espacio duro estrecho
}

local function Normalizar(s)
    for i = 1, #ESPACIOS do
        s = string.gsub(s, ESPACIOS[i], " ")
    end
    return s
end

-- El tooltip viene con codigos de formato de WoW metidos en medio: los numeros
-- van envueltos en |cffFFFFFF...|r. Eso deja el "|r" pegado detras del numero
-- (tapando la unidad) y el "|cffFFFFFF" delante (tapando el "durante"), que era
-- justo lo que impedia distinguir un dano de una duracion.
local function SinCodigos(s)
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|T.-|t", "")
    s = string.gsub(s, "|H.-|h", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "|h", "")
    s = string.gsub(s, "|n", " ")
    return s
end

-- Tramos ocupados por codigos de formato, para no escalar por error los
-- digitos que puedan llevar dentro (p.ej. el color |cff20ff20).
local function RangosCodigo(texto)
    local rangos, pos = {}, 1
    while true do
        local i = string.find(texto, "|", pos, true)
        if not i then break end
        local c, fin = string.sub(texto, i + 1, i + 1), nil
        if c == "c" then
            fin = i + 9
        elseif c == "T" then
            local j = string.find(texto, "|t", i + 2, true); fin = j and (j + 1) or (i + 1)
        elseif c == "H" then
            local j = string.find(texto, "|h", i + 2, true); fin = j and (j + 1) or (i + 1)
        else
            fin = i + 1
        end
        rangos[#rangos + 1] = { i, fin }
        pos = fin + 1
    end
    return rangos
end

-- Saca los codigos del texto y deja una marca \1 en su sitio, para poder
-- escalar sin que los digitos de un color (|cff20ff20) se peguen al numero
-- de al lado y se lo traguen. Luego se devuelven en el mismo orden.
local MARCA = string.char(1)

local function Marcar(texto)
    local rangos = RangosCodigo(texto)
    local out, codigos, pos = "", {}, 1
    for k = 1, #rangos do
        local a, b = rangos[k][1], rangos[k][2]
        out = out .. string.sub(texto, pos, a - 1) .. MARCA
        codigos[#codigos + 1] = string.sub(texto, a, b)
        pos = b + 1
    end
    return out .. string.sub(texto, pos), codigos
end

local function Desmarcar(texto, codigos)
    local k = 0
    return (string.gsub(texto, MARCA, function()
        k = k + 1
        return codigos[k] or ""
    end))
end

local function DebeSaltar(antes, despues)
    -- llegan ya marcados: se quitan las marcas y los codigos sueltos, para que
    -- "durante <marca>8" y "8<marca> s" se lean como "durante 8" y "8 s".
    local M = string.char(1)
    antes   = Normalizar(SinCodigos((string.gsub(antes, M, ""))))
    despues = Normalizar(SinCodigos((string.gsub(despues, M, ""))))
    if string.match(despues, "^%s*(%%)") then return true end
    local palabra = string.match(despues, "^%s*(%a+)")
    if palabra and UNIDADES[string.lower(palabra)] then return true end
    local previa = string.match(antes, "(%a+)%s*$")
    if previa and ANTES_MALO[string.lower(previa)] then return true end
    return false
end

local function EscalarTexto(original, pct)
    -- se trabaja sobre el texto sin codigos; se devuelven al final
    local texto, codigos = Marcar(original)

    local sep = nil
    if string.find(texto, "%d%.%d%d%d") then sep = "."
    elseif string.find(texto, "%d,%d%d%d") then sep = "," end

    local salida, pos, tocados = "", 1, 0
    while true do
        local i, j = string.find(texto, "%d[%d%.,]*", pos)
        if not i then
            salida = salida .. string.sub(texto, pos)
            break
        end
        salida = salida .. string.sub(texto, pos, i - 1)
        local tok = string.sub(texto, i, j)
        -- ventanas anchas: un codigo de color se come 10 caracteres, asi que
        -- con ventanas cortas no se alcanzaba la palabra de verdad.
        local antes   = string.sub(texto, math.max(1, i - 34), i - 1)
        local despues = string.sub(texto, j + 1, j + 26)

        local valor, miles = Parsear(tok)
        if valor and not DebeSaltar(antes, despues) then
            local nuevo = math.floor(valor * pct / 100 + 0.5)
            if (miles or sep) and nuevo >= 1000 then
                salida = salida .. ConMiles(nuevo, miles or sep)
            else
                salida = salida .. tostring(nuevo)
            end
            tocados = tocados + 1
        else
            salida = salida .. tok
        end
        pos = j + 1
    end
    return Desmarcar(salida, codigos), tocados
end

----------------------------------------------------------------- tooltip

local META = {
    "de man", "de energ", "de rabia", "de runa", "de concentraci",
    "Reutilizaci", "recarga", "cooldown",
    "de alcance", "yd range", "Alcance",
    "lanzamiento", "cast time", "Canalizado",
    "Requiere", "Requires", "Necesita",
    "Spell ID", "SpellID", "Item ID", "ItemID",
}

local function EsMeta(t)
    for i = 1, #META do
        if string.find(t, META[i]) then return true end
    end
    return false
end

-- Devuelve TODAS las lineas candidatas, de abajo arriba. Antes se elegia solo
-- una y se fallaba: en el tooltip de un buff, "11 segundos restantes" lleva
-- numeros y se llevaba el puesto, dejando sin tocar la linea de verdad.
local function LineasCandidatas(tt)
    local nombre, n = tt:GetName(), tt:NumLines()
    local buenas, resto = {}, {}
    for i = n, 2, -1 do
        local fs = _G[nombre .. "TextLeft" .. i]
        if fs then
            local t = fs:GetText()
            if t and t ~= "" and string.find(t, "%d") then
                if EsMeta(t) then
                    resto[#resto + 1] = { fs, t }
                else
                    buenas[#buenas + 1] = { fs, t }
                end
            end
        end
    end
    for i = 1, #resto do buenas[#buenas + 1] = resto[i] end
    return buenas
end

-- compatibilidad: la primera candidata, para el registro
local function LineaDescripcion(tt)
    local c = LineasCandidatas(tt)
    if c[1] then return c[1][1], c[1][2] end
    return nil
end

local DEPURAR = false

-- Ultimo recurso cuando el gancho no da un id: resolverlo por el nombre que
-- ya esta escrito en la primera linea del tooltip. Sirve para la barra de
-- formas (auras de paladin, sigilo, formas de druida) y para cualquier otro
-- camino que no exponga el id.
local function IdPorNombre(tt)
    if type(GetSpellLink) ~= "function" then return nil end
    local fs = _G[tt:GetName() .. "TextLeft1"]
    local nombre = fs and fs:GetText()
    if not nombre or nombre == "" then return nil end
    nombre = SinCodigos(nombre)
    local ok, link = pcall(GetSpellLink, nombre)
    if not ok or not link then return nil end
    local id = string.match(tostring(link), "spell:(%d+)")
    return id and tonumber(id) or nil
end

local function RetocarValor(tt, spellId)
    local pct = PorcentajeDe(spellId)
    if not pct or pct == 100 then
        if DEPURAR then Msg("hechizo " .. tostring(spellId) .. ": sin regular") end
        return
    end

    local candidatas = LineasCandidatas(tt)
    if #candidatas == 0 then
        if DEPURAR then Msg("hechizo " .. tostring(spellId) .. ": ninguna linea con numeros") end
        return
    end

    -- ya aplicado a este mismo tooltip: no repetir (la barra de accion
    -- reconstruye el tooltip cada pocas decimas)
    for k = 1, #candidatas do
        if tt.__srId == spellId and candidatas[k][2] == tt.__srOut then return end
    end

    -- se prueba linea por linea y se queda con la primera donde algo cambie
    for k = 1, #candidatas do
        local fs, texto = candidatas[k][1], candidatas[k][2]
        local nuevo, tocados = EscalarTexto(texto, pct)
        if tocados > 0 then
            fs:SetText(nuevo)
            tt.__srId, tt.__srOut = spellId, nuevo
            if DEPURAR then
                Msg("hechizo " .. tostring(spellId) .. " al " .. tostring(pct)
                    .. "%, linea " .. k .. ", numeros cambiados: " .. tocados)
            end
            tt:AddLine("Regulador: " .. tostring(pct) .. "% del valor base", 0.4, 1, 0.4)
            tt:Show()
            return
        end
    end

    if DEPURAR then
        Msg("hechizo " .. tostring(spellId) .. ": ninguna linea tenia un valor escalable")
    end
end

-- Lineas del coste de poder. Van aparte de RetocarValor porque el regulador
-- las trata como dos ajustes independientes: puedes dejar el dano intacto y
-- tocar solo el mana. Ademas RetocarValor para en la primera linea que cambia,
-- asi que nunca llegaria hasta aqui.
local COSTE = {
    "de man", "de energ", "de rabia", "de ira", "de runa",
    "de poder r", "de concentraci", "de foco",
    "Mana", "Energy", "Rage", "Runic Power", "Focus",
}

local LADOS = { "TextLeft", "TextRight" }

local function EsCoste(t)
    for i = 1, #COSTE do
        if string.find(t, COSTE[i]) then return true end
    end
    return false
end

local function RetocarCoste(tt, spellId)
    local pct = PorcentajeCosteDe(spellId)
    if not pct or pct == 100 then return end

    local nombre = tt:GetName()
    if not nombre then return end

    for i = 1, tt:NumLines() do
        for l = 1, #LADOS do
            local fs = _G[nombre .. LADOS[l] .. i]
            local t  = fs and fs:GetText()
            if t and t ~= "" and string.find(t, "%d") and EsCoste(t) then
                -- ya aplicado a este mismo tooltip: la barra de accion lo
                -- reconstruye cada pocas decimas y lo escalaria en bucle
                if tt.__srCosteId == spellId and t == tt.__srCosteOut then return end

                local nuevo, tocados = EscalarTexto(t, pct)
                if tocados > 0 then
                    fs:SetText(nuevo)
                    tt.__srCosteId, tt.__srCosteOut = spellId, nuevo
                    if DEPURAR then
                        Msg("hechizo " .. tostring(spellId) .. ": coste al "
                            .. tostring(pct) .. "%, linea " .. i .. " " .. LADOS[l])
                    end
                    tt:AddLine("Regulador: " .. tostring(pct) .. "% del coste", 0.4, 1, 0.4)
                    tt:Show()
                    return
                end
            end
        end
    end
end

-- Punto de entrada unico: resuelve el id una vez y hace las dos pasadas.
local function Retocar(tt, spellId)
    if not spellId then
        spellId = IdPorNombre(tt)
    end
    if not spellId then return end
    RetocarValor(tt, spellId)
    RetocarCoste(tt, spellId)
end

local function IdDeLink(link)
    if not link then return nil end
    local id = string.match(link, "spell:(%d+)")
    return id and tonumber(id) or nil
end

----------------------------------------------------------------- diagnostico
-- Deja constancia en SavedVariables de que engancha, con que datos y con que
-- texto exacto, para poder mirarlo desde fuera del juego.
-- Se vuelca a disco al hacer /reload o al salir.

local function Apuntar(gancho, arg, id, nota, linea)
    local L = SpellRegTooltipDB.log
    if not L then L = {}; SpellRegTooltipDB.log = L end
    if #L > 60 then table.remove(L, 1) end
    L[#L + 1] = {
        gancho = gancho,
        arg    = tostring(arg),
        id     = tostring(id),
        nota   = nota or "",
        linea  = linea or "",
    }
end

SpellRegTooltipDB = SpellRegTooltipDB or {}
SpellRegTooltipDB.log = {}
SpellRegTooltipDB.api = {}

-- Inventario de lo que existe de verdad en este cliente.
for _, m in ipairs({"SetSpell","SetSpellBookItem","SetAction","SetHyperlink","SetUnitAura","SetUnitBuff"}) do
    SpellRegTooltipDB.api[m] = (type(GameTooltip[m]) == "function")
end
for _, g in ipairs({"GetSpellLink","GetActionInfo","GetSpellInfo","GetActionText"}) do
    SpellRegTooltipDB.api[g] = (type(_G[g]) == "function")
end

local function Enganchar(metodo, fn)
    if type(GameTooltip[metodo]) ~= "function" then return false end
    hooksecurefunc(GameTooltip, metodo, fn)
    return true
end

-- Del libro de hechizos: el argumento es el INDICE del hueco, no el id.
local function DesdeLibro(self, index, libro)
    local id, nota = nil, "sin GetSpellLink"
    if type(GetSpellLink) == "function" then
        local ok, link = pcall(GetSpellLink, index, libro)
        if ok then id, nota = IdDeLink(link), tostring(link) end
    end
    local _, linea = LineaDescripcion(self)
    Apuntar("libro", tostring(index) .. "/" .. tostring(libro), id, nota, linea)
    Retocar(self, id)
end

Enganchar("SetSpell", DesdeLibro)
Enganchar("SetSpellBookItem", DesdeLibro)

-- OJO: en 3.3.5 GetActionInfo devuelve para los hechizos el INDICE del libro,
-- no el spellId (para Consagracion devolvia 60, siendo el id 20924). Hay que
-- pasarlo por GetSpellLink igual que en el libro de hechizos.
Enganchar("SetAction", function(self, slot)
    local id, nota = nil, "sin GetActionInfo"
    if type(GetActionInfo) == "function" then
        local ok, tipo, a, b = pcall(GetActionInfo, slot)
        if ok then
            nota = "tipo=" .. tostring(tipo) .. " a=" .. tostring(a) .. " b=" .. tostring(b)
            if tipo == "spell" and tonumber(a) and tonumber(a) > 0 then
                local ok2, link = pcall(GetSpellLink, tonumber(a), b or "spell")
                if ok2 then id = IdDeLink(link) end
                -- si el cliente ya diera el id de verdad, esto lo respeta
                if not id then id = tonumber(a) end
                nota = nota .. " -> id " .. tostring(id)
            end
        end
    end
    local _, linea = LineaDescripcion(self)
    Apuntar("barra", slot, id, nota, linea)
    Retocar(self, id)
end)

Enganchar("SetHyperlink", function(self, link)
    local id = IdDeLink(link)
    local _, linea = LineaDescripcion(self)
    Apuntar("enlace", tostring(link), id, "", linea)
    Retocar(self, id)
end)

-- Auras (buffs y debuffs): el id sale del 11o valor que devuelve UnitAura.
local function DesdeAura(metodo, filtroFijo)
    return function(self, unidad, indice, filtro)
        local id, nota = nil, "sin UnitAura"
        if type(UnitAura) == "function" then
            local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 =
                pcall(UnitAura, unidad, indice, filtro or filtroFijo)
            if ok then
                nota = "nombre=" .. tostring(a1)
                if tonumber(a11) then id = tonumber(a11) end
            end
        end
        local _, linea = LineaDescripcion(self)
        Apuntar(metodo, tostring(unidad) .. "/" .. tostring(indice), id, nota, linea)
        Retocar(self, id)
    end
end

Enganchar("SetUnitAura",   DesdeAura("aura", nil))
Enganchar("SetUnitBuff",   DesdeAura("buff", "HELPFUL"))
Enganchar("SetUnitDebuff", DesdeAura("debuff", "HARMFUL"))

-- Barra de formas: auras del paladin, sigilo del picaro, formas del druida.
-- Aqui no hay id por ninguna via, asi que se resuelve por el nombre.
Enganchar("SetShapeshift", function(self, indice)
    local id, nota = nil, "sin GetShapeshiftFormInfo"
    if type(GetShapeshiftFormInfo) == "function" then
        local ok, _, nombre = pcall(GetShapeshiftFormInfo, indice)
        if ok then
            nota = "nombre=" .. tostring(nombre)
            if nombre and type(GetSpellLink) == "function" then
                local ok2, link = pcall(GetSpellLink, nombre)
                if ok2 and link then
                    local n = string.match(tostring(link), "spell:(%d+)")
                    id = n and tonumber(n) or nil
                end
            end
        end
    end
    local _, linea = LineaDescripcion(self)
    Apuntar("formas", indice, id, nota, linea)
    Retocar(self, id)
end)

GameTooltip:HookScript("OnHide", function(self)
    self.__srId, self.__srOut = nil, nil
end)

----------------------------------------------------------------- AIO

local function ConectarAIO()
    if type(AIO) ~= "table" or type(AIO.AddHandlers) ~= "function" then
        return false
    end
    local H = AIO.AddHandlers(NOMBRE, {})
    function H.Set(_, tabla, tablaCoste)
        PCT = tabla or {}
        PCT_COSTE = tablaCoste or {}
        local n, c = 0, 0
        for _ in pairs(PCT) do n = n + 1 end
        for _ in pairs(PCT_COSTE) do c = c + 1 end
        if DEPURAR then
            Msg("recibidos del servidor: " .. n .. " hechizos regulados, "
                .. c .. " con el coste tocado")
        end
    end
    return true
end

----------------------------------------------------------------- comandos

SLASH_SPELLREG1 = "/spellreg"
SlashCmdList["SPELLREG"] = function(txt)
    local cmd, a, b = string.match(txt or "", "^(%a*)%s*(%-?%d*)%s*(%-?%d*)")
    cmd = string.lower(cmd or "")

    if cmd == "set" and a ~= "" and b ~= "" then
        MANUAL[tonumber(a)] = tonumber(b)
        Msg("prueba local: hechizo " .. a .. " al " .. b .. "%")
        return
    elseif cmd == "cost" and a ~= "" and b ~= "" then
        MANUAL_COSTE[tonumber(a)] = tonumber(b)
        Msg("prueba local: coste del hechizo " .. a .. " al " .. b .. "%")
        return
    elseif cmd == "clear" then
        MANUAL, MANUAL_COSTE = {}, {}
        Msg("pruebas locales borradas")
        return
    elseif cmd == "debug" then
        DEPURAR = not DEPURAR
        Msg("depuracion " .. (DEPURAR and "activada" or "desactivada"))
        return
    elseif cmd == "dump" then
        local L = SpellRegTooltipDB.log
        if not L or #L == 0 then
            Msg("nada apuntado todavia: pasa el raton por un hechizo y repite")
            return
        end
        -- resumen de los ultimos ganchos, para ver de un vistazo cuales saltan
        Msg("ultimos ganchos (el mas reciente al final):")
        for k = math.max(1, #L - 5), #L do
            Msg("  " .. L[k].gancho .. " arg=" .. L[k].arg .. " id=" .. L[k].id .. " (" .. L[k].nota .. ")")
        end
        local ult = L[#L]
        if ult.linea == "" then
            Msg("el ultimo no traia linea de descripcion")
            return
        end
        Msg("linea: " .. ult.linea)
        -- volcado en hexadecimal de lo que rodea a cada numero, que es donde
        -- estaba la duda de que caracter separa el numero de su unidad
        local pos = 1
        while true do
            local i, j = string.find(ult.linea, "%d+", pos)
            if not i then break end
            local trozo = string.sub(ult.linea, j + 1, j + 4)
            local hex = ""
            for k = 1, string.len(trozo) do
                hex = hex .. string.format("%02X ", string.byte(trozo, k))
            end
            Msg("  tras '" .. string.sub(ult.linea, i, j) .. "' -> " .. hex)
            pos = j + 1
        end
        return
    end

    local n = 0
    for id, pct in pairs(PCT) do
        Msg("servidor: hechizo " .. tostring(id) .. " -> " .. tostring(pct) .. "%")
        n = n + 1
    end
    for id, pct in pairs(MANUAL) do
        Msg("local:    hechizo " .. tostring(id) .. " -> " .. tostring(pct) .. "%")
        n = n + 1
    end
    if n == 0 then
        Msg("sin hechizos regulados. Prueba: /spellreg set 20924 5")
    end
    Msg("comandos: /spellreg set <id> <pct> | clear | debug")
end

----------------------------------------------------------------- arranque

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
local avisado = false
f:SetScript("OnEvent", function()
    if avisado then return end
    avisado = true
    -- Las SavedVariables se cargan despues del fichero, asi que el inventario
    -- de API y el borrado del log se rehacen aqui para que no se pisen.
    SpellRegTooltipDB = SpellRegTooltipDB or {}
    SpellRegTooltipDB.log = {}
    SpellRegTooltipDB.api = {}
    for _, m in ipairs({"SetSpell","SetSpellBookItem","SetAction","SetHyperlink",
                        "SetUnitAura","SetUnitBuff","SetUnitDebuff"}) do
        SpellRegTooltipDB.api["GameTooltip:" .. m] = (type(GameTooltip[m]) == "function")
    end
    for _, g in ipairs({"GetSpellLink","GetActionInfo","GetSpellInfo","UnitAura"}) do
        SpellRegTooltipDB.api[g] = (type(_G[g]) == "function")
    end
    if ConectarAIO() then
        AIO.Handle(NOMBRE, "Pedir")
        Msg("cargado y conectado a AIO. /spellreg para ver los datos.")
    else
        Msg("cargado, pero |cffff4444AIO no esta disponible|r. Los tooltips solo cambiaran con /spellreg set.")
    end
end)
