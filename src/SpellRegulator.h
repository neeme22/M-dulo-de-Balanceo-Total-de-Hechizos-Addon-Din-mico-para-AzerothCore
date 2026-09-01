/*
 * Spell Regulator - regulacion de hechizos para AzerothCore
 *
 * Copyright (C) 2026 pelianzaba
 *
 * Este programa es software libre: puedes redistribuirlo y/o modificarlo
 * bajo los terminos de la Licencia Publica General GNU version 3, tal y
 * como la publica la Free Software Foundation.
 *
 * Se distribuye con la esperanza de que sea util, pero SIN NINGUNA
 * GARANTIA. Consulta el fichero LICENSE para mas detalles.
 */

#pragma once
#include "DatabaseEnv.h"
#include "QueryResult.h"
#include "ScriptMgr.h"
#include "Unit.h"
#include "Creature.h"

class SpellRegulator
{
public:
    static SpellRegulator* instance()
    {
        static SpellRegulator instance;
        return &instance;
    }

    // Aplica amplificacion al damage/heal/amount segun:
    //   1) override per-NPC (creature_entry + spellId) si caster es Creature
    //   2) regulacion global del spell
    //   3) sin cambios
    void Regulate(uint32& damage, uint32 spellId, Unit const* caster = nullptr, char const* /*tag*/ = nullptr)
    {
        float val = LookupPercent(spellId, caster);
        if (!val || val == 100.0f)
            return;
        damage = static_cast<uint32>((damage / 100.0f) * val);
    }

    // Ajusta el coste de poder (mana, ira, energia, runas, foco...) segun la
    // columna `power_pct` de la tabla global `spellregulator`.
    //   100 = sin cambios, 50 = la mitad, 200 = el doble, 0 = gratis.
    // Se aplica al final de SpellInfo::CalcPowerCost, asi que respeta los
    // talentos y auras de reduccion de coste que ya se hayan calculado.
    void RegulatePowerCost(int32& cost, uint32 spellId)
    {
        auto it = PowerContainer.find(spellId);
        if (it == PowerContainer.end())
            return;

        float const pct = it->second;
        if (pct == 100.0f)
            return;

        cost = static_cast<int32>((cost / 100.0f) * pct);
        if (cost < 0)
            cost = 0;
    }

    void LoadFromDB()
    {
        RegulatorContainer.clear();
        PowerContainer.clear();
        NpcRegulatorContainer.clear();
        uint32 msTime = getMSTime();

        // Global por spell
        {
            QueryResult result = WorldDatabase.Query(
                "SELECT spellid, percentage, power_pct FROM spellregulator");
            uint32 count = 0;
            uint32 powerCount = 0;
            if (result)
            {
                do
                {
                    Field* f = result->Fetch();
                    uint32 const spellId = f[0].Get<uint32>();
                    RegulatorContainer[spellId] = f[1].Get<float>();

                    // Solo guardamos las que cambian algo, para que el lookup
                    // del coste no toque los hechizos sin regular.
                    float const power = f[2].Get<float>();
                    if (power != 100.0f)
                    {
                        PowerContainer[spellId] = power;
                        ++powerCount;
                    }
                    ++count;
                } while (result->NextRow());
            }
            LOG_INFO("server.loading", "SpellRegulator: loaded {} global spells ({} with power cost changes) in {} ms",
                     count, powerCount, GetMSTimeDiffToNow(msTime));
        }

        // Per-NPC override
        {
            uint32 t = getMSTime();
            QueryResult result = WorldDatabase.Query(
                "SELECT creature_entry, spell_id, amplification FROM npc_spell_amplification");
            uint32 count = 0;
            if (result)
            {
                do
                {
                    Field* f = result->Fetch();
                    uint32 entry = f[0].Get<uint32>();
                    uint32 spellId = f[1].Get<uint32>();
                    float pct = static_cast<float>(f[2].Get<uint32>());
                    NpcRegulatorContainer[std::make_pair(entry, spellId)] = pct;
                    ++count;
                } while (result->NextRow());
            }
            LOG_INFO("server.loading", "SpellRegulator: loaded {} npc-spell overrides in {} ms",
                     count, GetMSTimeDiffToNow(t));
        }
    }

private:
    // Devuelve el % a aplicar (100.0f = sin cambios). Per-NPC tiene prioridad.
    float LookupPercent(uint32 spellId, Unit const* caster) const
    {
        if (caster)
        {
            if (Creature const* c = caster->ToCreature())
            {
                auto it = NpcRegulatorContainer.find(std::make_pair(c->GetEntry(), spellId));
                if (it != NpcRegulatorContainer.end())
                    return it->second;
            }
        }
        auto it = RegulatorContainer.find(spellId);
        return (it != RegulatorContainer.end()) ? it->second : 0.0f;
    }

    struct PairHash
    {
        std::size_t operator()(std::pair<uint32, uint32> const& p) const noexcept
        {
            return (static_cast<std::size_t>(p.first) << 32) ^ p.second;
        }
    };

    std::unordered_map<uint32, float> RegulatorContainer;                              // spellId -> % de dano/heal
    std::unordered_map<uint32, float> PowerContainer;                                  // spellId -> % de coste de poder
    std::unordered_map<std::pair<uint32, uint32>, float, PairHash> NpcRegulatorContainer; // (entry, spellId) -> %
};

#define sSpellRegulator SpellRegulator::instance()

class RegulatorLoader : public WorldScript
{
public:
    RegulatorLoader() : WorldScript("SpellRegulatorLoader", {
        WORLDHOOK_ON_STARTUP
    }) {}

    void OnStartup() override
    {
        sSpellRegulator->LoadFromDB();
    }
};
