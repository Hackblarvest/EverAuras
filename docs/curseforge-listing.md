# CurseForge listing

Copy-ready texts for the EverAuras project page. Keep in sync with README.md when features change.

## Basics

| Field | Value |
|---|---|
| Name | EverAuras |
| Summary | WeakAuras-style auras for WoW Forever that keep working in combat: buffs, debuffs, DoT timer bars, cooldowns, range and resource checks. |
| Primary category | Combat |
| More categories | Buffs & Debuffs, Class |
| License | GNU General Public License version 2 (GPLv2) |
| Source | https://github.com/Hackblarvest/EverAuras |
| Issues | https://github.com/Hackblarvest/EverAuras/issues |
| Community (Discord) | https://discord.gg/HdRNYvKbY |
| Project | https://authors.curseforge.com/#/projects/1710578 (project id 1710578) |
| Project image | `logo/build/preview_256.png` (dark edges suit CurseForge's dark theme; `curseforge_400.png` has white edges) |
| Distribution | Allow distribution to 3rd party (WowUp and similar clients) |
| Comments | Off: questions and bug reports go to Discord and GitHub Issues |
| Donation | Buy Me a Coffee: https://buymeacoffee.com/hackblarvest (also `.github/FUNDING.yml` and the README) |
| File | `EverAuras-<version>.zip` from the GitHub release (four folders at the zip root) |
| Game version | CurseForge's own "WoW Forever" group, version matching the client (1.60.1 for build 1.60.1.70009). Do not pick Retail or Classic: the addon only targets Forever. |

## Description

EverAuras is a WeakAuras-style addon for **World of Warcraft: Forever** that keeps working **in combat**.

Forever runs on the modern engine with its "secret values" system: the moment you enter combat, anywhere (questing, dungeons or raids), aura and cooldown data become unreadable to addons. A plain port of WeakAuras goes blind exactly when you need it. EverAuras hands those displays to the game engine instead, so they keep working.

### What works in combat

- **Buff and debuff auras** on you, your target, focus and pet, by spell name or spell ID, including **"show when missing"**: an icon for Serpent Sting or Corruption that disappears the moment the debuff lands.
- **Timer bars** for DoTs and buffs, filled by the game itself.
- **Progress Textures** for buff and debuff timers, straight, circular (rings) or part circles (arcs), with your own texture, in combat too.
- **Time left:** an icon that shows only while a DoT or buff has less than X seconds left, or the classic "missing or about to run out" icon for refreshing DoTs, with its countdown and a glow.
- **Textures for procs**: show a texture while your proc or buff is up, or while it is missing.
- **Stop Motion animations and Models** for procs and missing buffs, animating in combat too.
- **Texts**: "NO DEMON SKIN!" while a buff is missing, "Corruption: 12 s" while a DoT runs, in combat too.
- **Stack Count**: show an aura only at 3+ stacks (or at most, or exactly, N), and **conditions on stacks**: change its colour, glow, text or alpha by the stack count, in combat too.
- **Dynamic Groups** that close up in combat: a DoT row without holes, growing left, right, up, down or from the centre, or **sorted by the time left**, with **conditions on the time left** per icon (e.g. red and glowing below 4 s).
- **Animated glows** (Button, Pixel, Autocast, Proc) on these icons, textures and bars, shown only while they are, also in combat, including a glow that starts when an aura has X seconds left.
- **Debuffs on you** such as Weakened Soul or Forbearance, matched by their properties, since Blizzard hides which debuff it is in combat.
- **Auras by dispel type**: "a poison on me", "a Magic debuff on me", "a Magic buff on my target" for Purge, with the aura's own icon and countdown.
- **Sounds that play when the aura comes or goes**, in combat too, from the first time (EverAuras ships the game's own spell lists per dispel type).
- **Range check**: only show an aura while your spell can reach the target (for example Serpent Sting's 8–35 yards).
- **Cooldowns** with swipe and timer text, and **spell usable** triggers, including reactive abilities such as Overpower or Mongoose Bite.
- **Resource bars** (mana, rage, energy) with **hide when full** and **colour below a threshold**.
- A **Five Second Rule** timer for mana users.
- **Spell ranks**: auras set up by name follow your ranks as you level.
- **Imports**: WeakAuras and M33kAuras export strings import as usual; texture paths from WeakAuras and its forks are pointed at EverAuras' own copy, and custom code that uses old API names (GetItemInfo, GetSpellInfo ...) works on Forever too.

Custom-code auras that compare values Blizzard keeps secret (for example your current mana) cannot work in combat on Forever; EverAuras tells you which ones, instead of flooding BugSack.

### Getting started

Type `/ea` in game (also `/everauras` or `/wa`). Questions, bug reports and aura sharing on the [EverAuras Discord](https://discord.gg/HdRNYvKbY).

### Credits

Built on [WeakAuras 2](https://github.com/WeakAuras/WeakAuras2) and [M33kAuras](https://github.com/m33shoq/M33kAuras). Open source under GPL-2.0: [source on GitHub](https://github.com/Hackblarvest/EverAuras).

EverAuras is free and stays free. If you would like to say thanks, you can [buy me a coffee](https://buymeacoffee.com/hackblarvest).

## Release type

CurseForge distinguishes Release, Beta and Alpha files. The CurseForge app installs Release files by default, and Alpha files only for users who opted in. Recommendation: upload as **Beta** while the version carries `-alpha`, or as **Release** if it should reach everyone by default.
