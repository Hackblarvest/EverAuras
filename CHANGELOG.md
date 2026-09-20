# Changelog

## 0.3.2-alpha (2026-09-21)

- **Load conditions work on Forever.** The load scanner called the load function with a retail-shaped
  argument list while the prototype builds a different parameter list for Forever, so every condition after
  *In Combat* / *Alive* (Player Class, Mounted, Zone, Level, ...) was evaluated against the wrong value. The
  argument list is now generated from the load prototype, so the two can never disagree.
- `/fdload` probe in ForeverDevInfo (flavour facts + loaded state of class-filtered displays).

## 0.3.1-alpha (2026-09-20)

- **Spell Usable trigger works in combat.** Cooldown, charges and cast count are secret in combat on Forever
  and the trigger's generated code compared them directly ("attempt to compare local 'spellCount'"). It now
  mirrors the Cooldown Progress trigger: ready-ness from `IsSpellReady`, stacks from the secret-aware helpers.
- Displays without an Aura trigger now say *Nothing to delegate* instead of *Not engine-driven (blind while
  auras are secret)*; the engine and range-gate toggles are hidden there since they have no effect.
- Release tooling: `tools/make_release_zip.py`, full upstream hash in `tools/UPSTREAM`, README points at Releases.

## 0.3.0-alpha (2026-09-20)

- **Range gate** for engine-driven displays: *Only while the spell is in range of the unit*, with an optional
  *Range check spell* override. `C_Spell.IsSpellInRange` answers with a plain boolean on Forever, in combat too,
  and honours the spell's own min/max range (Serpent Sting: 8–35 yd). Gated at the region's `SetAlpha`, so the
  display's own alpha, conditions and animations still apply; the range spell is validated (known + has a range)
  and the status line says when the gate cannot work.
- **Spell names on Forever**: the options spell cache is seeded from your spellbook (upstream disables it on test
  builds, which blanked typed names); a name with no match is kept as typed; the icon button beside a Name entry
  shows the spell's icon.
- **Rank-aware names**: a spell name resolves to every rank you know and is re-resolved as you learn spells and
  see auras.
- `/fdrange` probe in ForeverDevInfo.
- Upstream pinned to `f170ed7` (`tools/UPSTREAM`).

## 0.2.0-alpha (2026-09-19)

- Rebrand ForeverAuras → EverAuras (new logo, `/ea` and `/everauras`, project links).
- Engine-driven aura displays (found / missing / always) confirmed working in combat; cooldown displays and
  `%p` remaining-time text through duration objects; *Is Ready (Secret)* → *Alpha (Boolean)* conditions.
- SavedVariables bridge: never-shrink guard against an empty aura database overwriting a good seed.
