# EverAuras

**WeakAuras-lineage auras for World of Warcraft: Forever — working in combat.**

EverAuras is a fork of [M33kAuras](https://github.com/m33shoq/M33kAuras) (itself a fork of
[WeakAuras 2](https://github.com/WeakAuras/WeakAuras2)), rebuilt for the *World of Warcraft: Forever*
client. Forever runs on the mainline (retail) engine and inherits the 12.1 "secret values" system,
which makes ordinary aura and cooldown data unreadable to addons the moment you enter combat,
anywhere: questing, dungeons or raids. Ported-as-is, WeakAuras is blind exactly when you need it.

EverAuras is not blind. It never reads the secret data; it hands the display to the game engine
and lets the client draw it.

> **Status:** alpha, developed against the Forever *beta* client (interface 16001). Things break
> when Blizzard patches. Expect rough edges.

## What works in combat

| Display | How |
|---|---|
| **Your own auras** on player / target / focus / pet, by spell **name** (every rank you know, re-resolved as you level) or exact spell ID — *show when present*, *show when missing*, or both | The engine draws them through Blizzard's `CustomAuraContainerTemplate`. "Missing" is rendered by geometry the engine controls, so the icon genuinely disappears while the aura is up. |
| **Time left** — an icon that shows only while the aura has less (or more) than X seconds left (*Remaining Time* on *Show On: Aura(s) Found*), and the classic **"missing or about to run out"** icon (a *Missing* trigger plus *Found* + *Remaining Time* triggers, *Any Triggered*) | The icon is engine-drawn text whose colour comes from a curve over the remaining time. The game evaluates the curve; the addon never reads the time. |
| **Other triggers next to an aura trigger** — e.g. *in combat*, *target attackable*, *talent known* | The engine draws the aura part; WeakAuras evaluates the other triggers itself, which works for plain data (health and power amounts stay secret). |
| **Animated glow** on engine-driven icons, textures and bars — Button Glow, Pixel Glow, Autocast Shine and Proc Glow, with your colours and settings — shown only while the display is (aura present, missing, or running out; a bar keeps the glow's anchor area) | The glow runs inside a frame whose width the engine controls from the aura, so it is clipped away exactly when the icon is. Everything is created inside that frame, because Blizzard refuses to move frames into it, and everything moves by animation (Path, FlipBook), because the game refuses to let addon code re-position anything anchored to its aura frames while an aura is shown. For the last X seconds of an aura, a clip anchored to the fill edge of a bar the game sizes by the remaining time opens exactly when X seconds are left. A display with a missing and a time-left part chooses where the glow goes. |
| **Cooldown icons** with swipe and countdown, **progress bars**, and `%p` remaining-time text | Duration objects: the engine formats and animates values the addon cannot read. |
| **Texts** for warnings and timers — "NO DEMON SKIN!" while a buff is missing, "Corruption: 12 s" while a DoT runs — plain text, `%p`, `%t`, `%s`, `%n`, also with other words | WeakAuras' text is hidden and drawn again on the engine's aura button (Found) or in the Missing clip, in its font, size, outline, colour and width. Time inside other words is the engine's duration text with a format string ("Corruption: {}"); stacks inside other words a rule formatter. A Missing text's clip is sized by the engine's own measure of the text. |
| **Textures** for procs and missing buffs (*Show On: Aura(s) Found* or *Missing*), with your texture, colour, rotation and mirror | Icons without a timer: a copy of the texture on the engine's aura button (Found) or in the Missing clip. The copy takes WeakAuras' own texture coordinates, so rotation and mirror match. |
| **Progress Textures** for aura timers, straight and circular, with your texture, colours, crop, rotation and background | Straight: a clip anchored to the fill of an invisible bar the engine fills by the aura's duration reveals a copy of the texture with WeakAuras' own texture coordinates. Circular: the game's cooldown swipe drawn with the texture; its edge only turns clockwise, so two of WeakAuras' four direction settings run out the mirror way (the status line says which). |
| **Dynamic Groups** of engine-driven icons, bars, textures or texts (*Show On: Aura(s) Found*): a child whose aura is absent leaves no gap, in combat too — grow left, right, up, down or centred, with your spacing, order and alignment | A chain of invisible aura containers, one per child, each 1 px plus the child and the spacing while its aura is up and 1 px while it is not. Every child hangs on the end of the one before it, so the game itself packs the row; a centred row hangs by the middle of a container that holds every child. While packed, a child shows what the engine draws (icon, bar, texture, `%p`/`%s`/`%n` texts, glow); its border and other texts are hidden. |
| **Show On: Ready / On Cooldown** | Exact, from fields Blizzard left readable. |
| **Conditions on secret state** — e.g. *Is Ready (Secret)* → *Alpha (Boolean)* | The secret boolean goes straight to the engine via `SetAlphaFromBoolean`; the addon never sees it. |
| **Range gate** on engine-driven displays — *only while the spell is in range of the unit* (e.g. Serpent Sting missing **and** target within 8–35 yd) | `C_Spell.IsSpellInRange` answers with a plain boolean on Forever, in combat too, and honours the spell's own min/max range. Sampled 5x per second; the display's own alpha, conditions and animations still apply on top. |
| **Resource bars and text** (mana, rage, energy), plus *hide while full* and *colour below a threshold* | The values are secret, even your mana out of combat. The engine draws them, and `UnitPowerPercent` with a curve lets the game make the comparison and hand back a secret alpha or colour. |
| **Five Second Rule** timer for mana users | Started by your own mana-costing casts (spell id and cost are readable); regen resumes exactly 5 s later. |
| **Debuffs on you** (Weakened Soul, Forbearance, Recently Bandaged ...) | Blizzard does not let addons pick debuffs on friendly units by spell while auras are secret, so a per-spell filter can never match in combat; EverAuras says so. Optionally it learns the debuff's fingerprint (duration, dispel type and the flags Blizzard does allow) the first time it lands on you and matches on that, marked as an approximation. |
| **Auras by dispel type** — *a poison on me*, *a Magic debuff on me*, *a Magic buff on my target* (Purge / Dispel Magic), *stealable*, *boss debuff*, *cast by a player* — without naming a spell | The trigger's *Debuff Type*, *Is Stealable*, *Is Boss Debuff* and *Cast by Player* become the aura container's dispel-type and flag filters, which Blizzard applies to every aura, also to debuffs on you. The engine draws the matching aura with its own icon. |
| **Sounds on show / hide** that play when the aura comes or goes, also in combat | An engine-driven display's WeakAuras state never changes, so its sounds are handed to the game (`C_UnitAuras.AddAuraSound`), which plays them itself when the aura is added or removed. Sounds need spell ids: displays by dispel type use the spell lists taken from the game's own spell tables (`tools/gen_dispel_data.py`, `ForeverDispelData.lua`) plus every typed aura EverAuras could read out of combat. The game keeps these sounds over a `/reload`; EverAuras removes its old ones at start. |
| **Countdown numbers on aura icons** match Blizzard's buff frame | The Cooldown swipe's own numbers round up; aura icons get a countdown formatter that rounds down like the buff frame (minutes over 90 s). Spell cooldown icons keep the action-bar style. |
| **Imports** from WeakAuras and M33kAuras, also auras whose custom code calls old API names (`GetItemInfo`, `GetSpellInfo`, `GetSpellCooldown`, `GetCurrencyInfo` ...) | The Forever client ships no deprecated-API fallbacks. Inside aura code only, a missing old name falls back to its modern `C_Item` / `C_Spell` / `C_CurrencyInfo` home with the old return values; a real global always wins. Auras exported from current M33kAuras (internal version 90) import too. |
| Spell usable (incl. reactive abilities such as Overpower or Mongoose Bite), in range, item cooldowns, casts, swing timers | Plain readable data. |

Together these are the building blocks of a rotation display: a row of icons, each showing when
its spell should be cast, in combat, correctly. See the [design notes](#how-it-works) for what is
*not* possible and why.

## Install

1. Have a working Forever install and the Battle.net app running.
2. Download the latest `EverAuras-<version>.zip` from
   [Releases](https://github.com/Hackblarvest/EverAuras/releases) and unzip it into
   `_classic_beta_\Interface\AddOns`. It holds `EverAuras`, `EverAurasOptions`, `EverAurasArchive` and
   `EverAurasModelPaths` (an `EverAurasTemplates` folder from 0.8.0 or earlier never loaded and can be
   deleted). Textures in auras imported from WeakAuras, M33kAuras
   or ForeverAuras are pointed at EverAuras' own copy of the same media automatically.
   Upgrading from 0.4.0 or earlier: delete the `M33Auras` and `WeakAuras` folders those zips added, if the
   addon list calls them "EverAuras Settings Migration" (other addons use the same folder names).
3. In game: `/ea` (or `/everauras`, `/wa`).

Nothing else is needed on build 1.60.1.70009 or newer. Earlier beta builds wrote SavedVariables on
logout but never read them back; `tools/sv_bridge.py` (with `start_sv_bridge.cmd`) worked around that
and is kept only for anyone stuck on an older build.

Every release is built by `tools/rebuild_everauras.sh` from the upstream commit pinned in
`tools/UPSTREAM` and the upstream release (for the bundled libraries) pinned in `tools/UPSTREAM_RELEASE`,
and packed by `tools/make_release_zip.py`; build from source (below) to get the same thing.

## Build from source

The repository does **not** vendor WeakAuras. The build script downloads the latest upstream
release and `main` branch, applies our patches, renames everything to EverAuras and installs it:

```bash
bash tools/rebuild_everauras.sh
# EVERAURAS_ADDONS="<path to Interface/AddOns>"  overrides the install location
# EVERAURAS_UPSTREAM="<commit|tag|branch>"       pins the upstream source (default: latest main);
#                                                 a tools/UPSTREAM file does the same for everyone
# EVERAURAS_UPSTREAM_RELEASE="<release tag>"      pins the release the libraries come from (default:
#                                                 latest); tools/UPSTREAM_RELEASE does the same
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
- **Dynamic Groups** use the same geometry in a chain: one such container per child, each hung on the
  end of the one before it, and each child's display hung on its own link. The game resizes the links,
  so the children close up without the addon ever knowing which aura is up. Frames hung on an aura
  container must carry its ban on layout scripts (`DisableUntrustedLayoutScriptsTemplate`), so
  WeakAuras' own frames can never join the chain; EverAuras draws a packed child itself.
- **Cooldowns** come as `LuaDurationObject`s. Their own methods format text and evaluate curves
  internally, and `Cooldown:SetCooldownFromDurationObject` animates the swipe — all from tainted
  code, verified in combat.
- **Secret booleans** can drive alpha, desaturation and colour through the boolean-aware setters
  the client allows tainted code to use.

What is lost for engine-driven displays: conditions and texts that *read* aura state (stacks,
remaining time, active), show/hide animations and actions on aura gain/loss other than sounds,
dynamic groups that sort by time left, limit their children, stagger them or grow in a circle or a
grid, and part-circle progress textures. A list sorted by time left is not possible; a packed
priority row is.

The full research trail — every API flag, probe result and dead end — is in `docs/`.

## Repository layout

```
tools/rebuild_everauras.sh        build + install pipeline
tools/forever_patches.py          anchored Forever fixes (IsRetail routing, secrets, spec IDs, ...)
tools/engine_hunks.py             the engine-aura and text hunks, shared by build and live-apply
tools/forever_files/              our new addon files (engine-driven auras, options UI)
tools/rename_to_everauras.py      branding as a build step
tools/apply_engine_to_installed.py  apply the hunks to an installed copy
tools/sv_bridge.py                workaround for the SavedVariables bug of beta builds before 70009
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

EverAuras is free and stays free. If you would like to say thanks, you can
[buy me a coffee](https://buymeacoffee.com/hackblarvest).

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-hackblarvest-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/hackblarvest)

Licensed under the **GNU General Public License v2.0**, like the projects it derives from.
See [LICENSE](LICENSE).

Author: Hackblarvest. Modifications and additions © 2026 Hackblarvest.
