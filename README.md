# EverAuras

**WeakAuras-lineage auras for World of Warcraft: Forever — working in combat.**

EverAuras is a fork of [M33kAuras](https://github.com/m33shoq/M33kAuras) (itself a fork of
[WeakAuras 2](https://github.com/WeakAuras/WeakAuras2)), rebuilt for the *World of Warcraft: Forever*
client. Forever runs on the mainline (retail) engine and inherits the 12.1 "secret values" system,
which makes ordinary aura and cooldown data unreadable to addons the moment you enter combat —
even in the open world, even at level 2. Ported-as-is, WeakAuras is blind exactly when you need it.

EverAuras is not blind. It never reads the secret data; it hands the display to the game engine
and lets the client draw it.

> **Status:** alpha, developed against the Forever *beta* client (interface 16001). Things break
> when Blizzard patches. Expect rough edges.

## What works in combat

| Display | How |
|---|---|
| **Your own auras** on player / target / focus / pet, by spell **name** (every rank you know, re-resolved as you level) or exact spell ID — *show when present*, *show when missing*, or both | The engine draws them through Blizzard's `CustomAuraContainerTemplate`. "Missing" is rendered by geometry the engine controls, so the icon genuinely disappears while the aura is up. |
| **Cooldown icons** with swipe and countdown, **progress bars**, and `%p` remaining-time text | Duration objects: the engine formats and animates values the addon cannot read. |
| **Show On: Ready / On Cooldown** | Exact, from fields Blizzard left readable. |
| **Conditions on secret state** — e.g. *Is Ready (Secret)* → *Alpha (Boolean)* | The secret boolean goes straight to the engine via `SetAlphaFromBoolean`; the addon never sees it. |
| Spell usable, in range, resources, item cooldowns, casts, swing timers | Plain readable data. |

Together these are the building blocks of a rotation display: a row of icons, each showing when
its spell should be cast, in combat, correctly. See the [design notes](#how-it-works) for what is
*not* possible and why.

## Install

1. Have a working Forever install and the Battle.net app running.
2. Copy the built addon folders (`EverAuras`, `EverAurasOptions`, `EverAurasArchive`,
   `EverAurasModelPaths`, `EverAurasTemplates`) plus `addons/!ForeverCompat` into
   `_classic_beta_\Interface\AddOns`.
3. **Beta client bug:** the Forever beta writes SavedVariables on logout but never reads them back,
   so your auras vanish after `/reload`. Until Blizzard fixes it, run `start_sv_bridge.cmd`
   (see `tools/sv_bridge.py`) and keep it open while you play. It regenerates a tiny
   `!ForeverSVBridge` addon that restores your settings on every load, and switches itself off the
   day the client behaves.
4. In game: `/ea` (or `/everauras`, `/wa`).

Releases are not published yet; build from source (below).

## Build from source

The repository does **not** vendor WeakAuras. The build script downloads the latest upstream
release and `main` branch, applies our patches, renames everything to EverAuras and installs it:

```bash
bash tools/rebuild_everauras.sh
# EVERAURAS_ADDONS="<path to Interface/AddOns>"  overrides the install location
# EVERAURAS_UPSTREAM="<commit|tag|branch>"       pins the upstream source (default: latest main);
#                                                 a tools/UPSTREAM file does the same for everyone
```

Requirements: Git Bash, `git`, `gh` (logged in), `curl`, `unzip`, Python 3.

Why this shape: every change we make is either an *anchored patch* (`tools/forever_patches.py`,
`tools/engine_hunks.py`) or a *new file* (`tools/forever_files/`). Upstream fixes stay pullable by
re-running the script, and the build **hard-fails** if upstream moved underneath an anchor —
nothing installs silently broken. `tools/apply_engine_to_installed.py` applies the same hunks to
an already-installed copy without a full rebuild.

## How it works

The Forever client declares, for every API, whether a tainted (third-party) caller gets real
values, secret values, nothing, or an error. Under the *Combat* addon restriction, every aura getter
either throws or returns nothing, so an addon can never learn whether a debuff is on the target.

What it *can* do is configure engine-drawn UI:

- **`Blizzard_AuraContainer`** ships `CustomAuraContainerTemplate` for addons. You give it a unit,
  a filter and a spell-ID list; you hand it your own icon texture, cooldown frame and font strings;
  the engine writes secret values into them and marks them unreadable. Visibility while the aura is
  present is the engine's `SetShown(secret)`. (`tools/forever_files/ForeverEngineAura.lua`)
- **"Missing"** cannot be inverted in Lua, so EverAuras uses an aura *group* whose container width
  the engine sets to a secret 1 px (absent) or W+1 px (present), and hangs a clipping frame off
  that edge: full width while absent, zero width while present. Pure geometry, no reads.
- **Cooldowns** come as `LuaDurationObject`s. Their own methods format text and evaluate curves
  internally, and `Cooldown:SetCooldownFromDurationObject` animates the swipe — all from tainted
  code, verified in combat.
- **Secret booleans** can drive alpha, desaturation and colour through the boolean-aware setters
  the client allows tainted code to use.

What is lost for engine-driven displays: conditions and texts that *read* aura state (stacks,
remaining time, active), show/hide animations and actions on aura gain/loss, dynamic-group layout
that reacts to secret visibility, and progress textures (no duration-object path yet). A sorted
priority list is not possible; a fixed priority row is.

The full research trail — every API flag, probe result and dead end — is in `docs/`.

## Repository layout

```
tools/rebuild_everauras.sh        build + install pipeline
tools/forever_patches.py          anchored Forever fixes (IsRetail routing, secrets, spec IDs, ...)
tools/engine_hunks.py             the engine-aura and text hunks, shared by build and live-apply
tools/forever_files/              our new addon files (engine-driven auras, options UI)
tools/rename_to_everauras.py      branding as a build step
tools/apply_engine_to_installed.py  apply the hunks to an installed copy
tools/sv_bridge.py                workaround for the beta SavedVariables bug
addons/!ForeverCompat             shims for FrameXML globals the engine removed (old AceGUI libs)
addons/ForeverDevInfo             diagnostics: /fdi, /fdsecret, /fdsecret2, /fdsecret3, /fdslot
docs/                             bug reports and notes
logo/                             artwork sources
```

## Credits and licence

EverAuras stands on [WeakAuras 2](https://github.com/WeakAuras/WeakAuras2) and on
[m33shoq's M33kAuras](https://github.com/m33shoq/M33kAuras), whose 12.1 secrets work (duration
objects, boolean-driven properties, secret-aware cooldown triggers) EverAuras builds directly upon.
The CurseForge link inside the addon still points at upstream on purpose.

Community: [EverAuras Discord](https://discord.gg/HdRNYvKbY).

Licensed under the **GNU General Public License v2.0**, like the projects it derives from.
See [LICENSE](LICENSE).

Author: Hackblarvest.
