# EverAuras

**WeakAuras-lineage auras for World of Warcraft: Forever — working in combat.**

EverAuras is a fork of [M33kAuras](https://github.com/m33shoq/M33kAuras) (itself a fork of
[WeakAuras 2](https://github.com/WeakAuras/WeakAuras2)), rebuilt for the *World of Warcraft: Forever*
client. Forever runs on the mainline (retail) engine and inherits the 12.1 "secret values" system,
which makes ordinary aura and cooldown data unreadable to addons the moment you enter combat,
anywhere: questing, dungeons or raids. Ported-as-is, WeakAuras is blind exactly when you need it.

EverAuras is not blind. It never reads the secret data; it hands the display to the game engine
and lets the client draw it.

> **Status:** beta (0.9.4), built on M33kAuras `fd03b21` (release 5.20.7-rg4-m99) and developed against
> the Forever *beta* client (interface 16001). Blizzard patches can still break things; please report
> what you find on [Discord](https://discord.gg/HdRNYvKbY) or in the
> [issues](https://github.com/Hackblarvest/EverAuras/issues).

## What works in combat

| Display | How |
|---|---|
| **Your own auras** on player / target / focus / pet, and your buffs on a group member (*Specific Unit* party1–4, raid1–40; debuffs there by *Debuff Type* only), by spell **name** (every rank you know, re-resolved as you level) or exact spell ID — *show when present*, *show when missing*, or both | The engine draws them through Blizzard's `CustomAuraContainerTemplate`. "Missing" is rendered by geometry the engine controls, so the icon genuinely disappears while the aura is up. |
| **Time left** — an icon that shows only while the aura has less (or more) than X seconds left (*Remaining Time* on *Show On: Aura(s) Found*), and the classic **"missing or about to run out"** icon (a *Missing* trigger plus *Found* + *Remaining Time* triggers, *Required for Activation: Any Triggers*) | The icon is engine-drawn text whose colour comes from a curve over the remaining time. The game evaluates the curve; the addon never reads the time. |
| **Other triggers next to an aura trigger** — e.g. *in combat*, *target attackable*, *talent known* | The engine draws the aura part; WeakAuras evaluates the other triggers itself, which works for plain data (health and power amounts stay secret). |
| **Animated glow** on engine-driven icons, textures and bars — Button Glow, Pixel Glow, Autocast Shine and Proc Glow, with your colours and settings — shown only while the display is (aura present, missing, or running out; a bar keeps the glow's anchor area) | The glow runs inside a frame whose width the engine controls from the aura, so it is clipped away exactly when the icon is. Everything is created inside that frame, because Blizzard refuses to move frames into it, and everything moves by animation (Path, FlipBook), because the game refuses to let addon code re-position anything anchored to its aura frames while an aura is shown. For the last X seconds of an aura, a clip anchored to the fill edge of a bar the game sizes by the remaining time opens exactly when X seconds are left. A display with a missing and a time-left part chooses where the glow goes. |
| **Start and Finish animations** on engine-driven Icons, Textures and plain Texts, *Preset* or custom (fade, slide, zoom): *Start* on a *Show On: Aura(s) Found* display when the aura is put on, *Finish* on an *Aura(s) Missing* display when the aura is put on and the display goes; *Main* animations as in WeakAuras | An aura button plays the animation groups handed to it (`AddAuraShownAnimation`) each time it goes from hidden to shown, also in combat: a slot of ours on a Found display's aura shows when the aura comes, and so does a Missing display's group button, which is when that display goes. The game also redraws every aura button at combat start and end and on loot, so each animation plays on a copy of the display in a clip that is open only during the first seconds after the aura was put on: an invisible duration text counts the aura's elapsed time, formatted wide below that and narrow after, and the clip hangs on its end. Later redraws replay out of sight; after a *Start* the display's own drawing takes over. *Main* stays WeakAuras' own: it moves WeakAuras' display, on which the engine's drawing hangs. |
| **Cooldown icons** with swipe and countdown, **progress bars** (with WeakAuras' bar gradient), and `%p` remaining-time text | Duration objects: the engine formats and animates values the addon cannot read. |
| **Texts** for warnings and timers — "NO DEMON SKIN!" while a buff is missing, "Corruption: 12 s" while a DoT runs — plain text, `%p`, `%t`, `%s`, `%n`, also with other words and in WeakAuras' *Time Format* ("4" without the "s", tenths below a threshold, "1:05"), and time and stacks in one text (`%p (%s)`, also as a sub-text of icons, bars and textures) | WeakAuras' text is hidden and drawn again on the engine's aura button (Found) or in the Missing clip, in its font, size, outline, colour and width. Time inside other words is the engine's duration text with a format string ("Corruption: {}"); WeakAuras' *Time Format* becomes a rule formatter the game applies to the time (blank at 0, tenths below the threshold, whole seconds rounded up, minutes and seconds past a minute); stacks inside other words a rule formatter. A Missing text's clip is sized by the engine's own measure of the text. Time and stacks in one text are two of the button's texts side by side: the duration text with the time and the words on its outer side, the stack count with the rest. The piece on the anchored side takes WeakAuras' point and the other hangs by one point on its end, so it follows as the game rewrites the first. Left and right anchored texts sit exactly; a centred one hangs the time by its own point, shifted by half an estimate of the stacks' width (the mean of the stacks' words without a number and with '3', measured on a hidden text of ours, as the game's own text widths are secret). |
| **Textures** for procs and missing buffs (*Show On: Aura(s) Found* or *Missing*), with your texture, colour, rotation and mirror | Icons without a timer: a copy of the texture on the engine's aura button (Found) or in the Missing clip. The copy takes WeakAuras' own texture coordinates, so rotation and mirror match. |
| **Stop Motion** animations for procs and missing buffs (*Found* or *Missing*), Loop or Bounce, with your sheet, frame rate, colours and background | WeakAuras steps through the sheet from a script, and scripts never run inside the engine's aura buttons. The game's own FlipBook animation plays the same sheet (rows, columns, frames as WeakAuras reads them) on the button or in the Missing clip. Once and Progress need a start the game does not give addons. |
| **Models** (*Found* or *Missing*), a model file or display ID with your position or transform, rotation, zoom and animation | WeakAuras' model is hidden and a PlayerModel of ours, set up the same way, lives on the engine's aura button (Found) or in the Missing clip, hung on the clip's edges. A unit's model follows its unit through events, which cannot run there, so it stays with WeakAuras. |
| **Progress Textures** for aura timers, straight, circular and part circles (*Start / End Angle*), in all four directions, with your texture, colours, crop, rotation and background | Straight: a clip anchored to the fill of an invisible bar the engine fills by the aura's duration reveals a copy of the texture with WeakAuras' own texture coordinates. Circular: the game's cooldown swipe drawn with the texture where its clockwise edge matches WeakAuras' direction; otherwise, and for part circles, the arc is cut into small pieces (about 1.5 px of arc each), each in its own clip anchored past the fill edge of the same bar laid out very wide, so the pieces show and hide one by one as the aura runs out. Each piece is WeakAuras' own wedge. |
| **Stack Count and conditions on stacks**: show a display only at N stacks or more, at most N or exactly N (the Aura trigger's *Stack Count*), and change its look by the stacks (*Conditions* on *Stacks*: colours, desaturate, glow, text colour and size, alpha); and the **refresh icon**: an *Aura(s) Missing* trigger plus an *Aura(s) Found* trigger with a *Stack Count* (or conditions on stacks) on the same aura, *Required for Activation: Any Triggers*, shown while the aura is absent or its stacks match (e.g. Sunder Armor missing or below 5 stacks), on Icons, Textures and Stop Motions | The engine fills a status bar of its own by the aura's stacks (`SetApplicationBar`). Two gates around the display hang on the fill edge of such bars, so they open only while the count matches; the threshold lives in the bar's range alone, so nothing that hangs on the aura's frames has to move. Conditions cut the stack axis into stretches, and each stretch is drawn as a look of its own (the display's settings with that stretch's changes) behind its own pair of gates. A refresh icon is the Found display behind its gates plus the Missing clip outside them: your icon, texture or animation while the aura is absent, the live aura (on an icon with its countdown, stacks and swipe) while the count matches (with conditions on stacks alone, at any count, in the look of its stacks); *Display tab → Glow* picks which of the two glows. |
| **Dynamic Groups sorted by the time left** (*Sort: Ascending* or *Descending*), alike icons or horizontal Progress Bars on one unit, with WeakAuras' *Limit* | One aura group of the game over all the children's spells, ordered by expiration by the game itself (`sortMethod = ExpirationOnly`, also in combat), hung where WeakAuras puts the first child; every frame in the first child's look (for bars: the first child's bar and icon, laid out as WeakAuras lays it out, filled by the game). |
| **Conditions on the time left**: a *Remaining Duration* condition (e.g. at 5 s or less: red, glowing) on an engine-driven icon, bar, progress texture, texture, text, stop motion or model | The display is drawn as two looks, from X up and below X (its settings with each side's changes), each behind a time gate: an aura slot of its own whose duration text the game formats wide below X and narrow from X up, drawn invisible, with the look's gate hung on the text's end. The threshold lives in the formatter alone, so nothing that hangs on the aura's frames moves. |
| **Conditions on the time left in a sorted group**: the first child's *Remaining Duration* condition (e.g. at 4 s or less: red and glowing) on every icon of the row, each on its own | Every frame carries a gate inside its aura button: its duration text, formatted by the game wide below X seconds and narrow from X up and drawn invisible, hangs by one point left of the frame, and two clips hang on its end, one open below X and one from X up, each with that side's colour (multiplied over the icon) and animated glow. No total duration is needed, so DoTs of any length share the row. |
| **Dynamic Groups** of engine-driven icons, bars, textures or texts (*Show On: Aura(s) Found*): a child whose aura is absent leaves no gap, in combat too — grow left, right, up, down or centred, with your spacing, order and alignment; your buffs and your target's DoTs may share a row, and children with conditions on the time left or the stacks pack too | A chain of invisible aura containers, one per child, each 1 px plus the child and the spacing while its aura is up and 1 px while it is not. Every child hangs on the end of the one before it, so the game itself packs the row; a centred row hangs from its middle on a half chain, one container per unit with every child at half its length (plus half the spacing), so its far end is where the row starts. The chain hangs on the group's own anchor point, which WeakAuras keeps fixed whichever children it shows. While packed, a child shows what the engine draws (icon, bar, texture, `%p`/`%s`/`%n` texts, glow); its border and other texts are hidden. |
| **Party auras**: an Aura trigger on *Unit: Party* or *Smart Group* with *Unit Count* '> 0' (someone has it, e.g. your Renew) or '< 100%' (someone lacks it, e.g. "SOMEONE NEEDS FORTITUDE"), and **Auto-Clone (Show All Matches)**: a copy per member who has it, or lacks it (*Combine Matches Per Unit*, *Show Matches for: Unaffected*), at that member's unit frame in a Dynamic Group with *Group by Frame: Unit Frames* | The display is drawn once per member (you and party1–4), each copy with an aura container of its own on that member; the game shows or hides each one, and whether a member is there, dead or offline stays readable in combat. With a Unit Count all copies sit at the display's place, so it shows while anyone has (or lacks) the aura; when several do, one of them shows. With Auto-Clone in a Dynamic Group grouped by *Unit Frames*, each copy hangs on its member's frame (found by WeakAuras' own LibGetFrame, which skips your player frame as WeakAuras does) in the display's fixed place among the group's children, growing Left, Right, Up or Down; in another Dynamic Group the copies stand in a row from the display, one place per member; otherwise they sit at the display. In a raid, only your own party is watched. |
| **Show On: Ready / On Cooldown** | Exact, from fields Blizzard left readable. |
| **Conditions on secret state** — e.g. *Is Ready (Secret)* → *Alpha (Boolean)* | The secret boolean goes straight to the engine via `SetAlphaFromBoolean`; the addon never sees it. |
| **Range gate** on engine-driven displays — *only while the spell is in range of the unit* (e.g. Serpent Sting missing **and** target within 8–35 yd) | `C_Spell.IsSpellInRange` answers with a plain boolean on Forever, in combat too, and honours the spell's own min/max range. Sampled 5x per second; the display's own alpha, conditions and animations still apply on top. |
| **Resource bars and text** (mana, rage, energy), plus *hide while full*, *hide at or above / below X%* (a "LOW MANA" text, also on Textures and Progress Textures) and *colour below a threshold* | The values are secret, even your mana out of combat. The engine draws them, and `UnitPowerPercent` with a curve lets the game make the comparison and hand back a secret alpha or colour. |
| **Five Second Rule** timer for mana users | Started by your own mana-costing casts (spell id and cost are readable); regen resumes exactly 5 s later. |
| **Debuffs on you** (Weakened Soul, Forbearance, Recently Bandaged ...) | Blizzard does not let addons pick debuffs on friendly units by spell while auras are secret, so a per-spell filter can never match in combat; EverAuras says so. Optionally it learns the debuff's fingerprint (duration, dispel type and the flags Blizzard does allow) the first time it lands on you and matches on that, marked as an approximation. |
| **Auras by dispel type** — *a poison on me*, *a Magic debuff on me*, *a Magic buff on my target* (Purge / Dispel Magic), *stealable*, *boss debuff*, *cast by a player* — without naming a spell | The trigger's *Debuff Type*, *Is Stealable*, *Is Boss Debuff* and *Cast by Player* become the aura container's dispel-type and flag filters, which Blizzard applies to every aura, also to debuffs on you. The engine draws the matching aura with its own icon. |
| **Sounds on show / hide** that play when the aura comes or goes, also in combat | An engine-driven display's WeakAuras state never changes, so its sounds are handed to the game (`C_UnitAuras.AddAuraSound`), which plays them itself when the aura is added or removed. Sounds need spell ids: displays by dispel type use the spell lists taken from the game's own spell tables (`tools/gen_dispel_data.py`, `ForeverDispelData.lua`) plus every typed aura EverAuras could read out of combat. The game keeps these sounds over a `/reload`; EverAuras removes its old ones at start. |
| **Countdown numbers on aura icons** match Blizzard's buff frame | The Cooldown swipe's own numbers round up; aura icons get a countdown formatter that rounds down like the buff frame (minutes over 90 s). Spell cooldown icons keep the action-bar style. |
| **Imports** from WeakAuras, M33kAuras and **ForeverAuras**, also auras whose custom code calls old API names (`GetItemInfo`, `GetSpellInfo`, `GetSpellCooldown`, `GetCurrencyInfo` ...) | The Forever client ships no deprecated-API fallbacks. Inside aura code only, a missing old name falls back to its modern `C_Item` / `C_Spell` / `C_CurrencyInfo` home with the old return values; a real global always wins. Auras exported from current M33kAuras (internal version 90) import too. ForeverAuras strings (their own data version 91) are brought onto EverAuras' data at import: their aura trigger becomes the Aura trigger (drawn by the engine), their flow groups Dynamic Groups, their class load *Class*, and conditions on a resource percentage the power gate; one chat line names what has no counterpart here. Only the aura data is translated. |
| Spell usable (incl. reactive abilities such as Overpower or Mongoose Bite), in range, item cooldowns, casts, swing timers | Plain readable data. |
| Everything **M33kAuras** brings to Forever: Talent, Game Mode (PvE, PvP, RP, Hardcore), PvP Flagged and On Taxi loads; Talent Known, Character Stats, Health, Totem and Threat triggers; an encounter browser for Forever's dungeons and raids; a list of the auras, cooldowns and casts Blizzard keeps readable in combat (*Browse never-secret auras*) | Upstream's own Forever support. EverAuras is rebuilt on top of it (`tools/UPSTREAM`), and its patches only add what upstream does not do. |



## Official auras

- [EverAuras Shield](https://wago.io/_0najWd4T) (curve) and [EverAuras Shield Ring](https://wago.io/G4WYlUMi5):
  how much your absorb shields still take (Power Word: Shield, Sacrifice, Ice Barrier, Fire, Frost and
  Shadow Ward, Templar's Bulwark, protection potions, trinkets ...), as a curved column of segments with
  the number below or as a ring with the number inside, in combat too. Mana Shield does not show: the
  game leaves it out of the absorb amount addons can read. The curve's design is inspired by nan Shield
  (Hamersteen) and nanShield - Forever (Billie Jeanne).

## Install

1. Have a working Forever install and the Battle.net app running.
2. Install **EverAuras** with the [CurseForge](https://www.curseforge.com/wow/addons/everauras) or
   [Wago](https://addons.wago.io/addons/everauras) app (game version *WoW Forever*), or download the latest `EverAuras-<version>.zip` from
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

What is lost for engine-driven displays: conditions and texts that *read* aura state other than
the stacks and the remaining time (one time per display, not together with the stacks; active),
*Finish* animations on displays shown while the aura is present and *Start* animations on displays
shown while it is missing (nothing marks the moment an aura goes), a *Start* from the game when you switch
to a target that already has the aura (WeakAuras' own still plays as you pick a target after having none),
*Start* / *Finish* on bars, progress textures, stop motions, models and texts with the aura's values, on
refresh icons, on displays shown from 2 stacks up and in sorted groups, their rotation and colour,
durations in % of progress, refresh icons other than icons, textures and stop motions, actions on aura
gain/loss other than
sounds, dynamic groups that stagger their children, grow in a circle or a grid, sort them in a
hybrid or custom way or limit them without sorting, *Once* and *Progress* stop motions, a
unit's model, and for group triggers *Unit: Raid*, Unit Counts other than '> 0' and '< 100%', *Remaining Time*,
*Stack Count* and conditions on stacks or the time left, the class / role / name filters, *Ignore out of checking
range*, *Auto-Clone* for *All* members, and sounds. A group sorted by the time left draws every child in the first one's look.

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
