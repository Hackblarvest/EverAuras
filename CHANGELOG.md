# Changelog

## 0.8.15-alpha (2026-10-09)

- **Timer bars sorted by the time left.** A Dynamic Group of alike horizontal Progress Bars set to sort
  *Ascending* or *Descending* now stays sorted in combat, like icons: the DoT with the least (or most) time
  left on top, and a refreshed one moves to its new place. Every bar takes the first child's bar, icon,
  colours, gradient, texture and %p/%s/%n texts, and its glow is animated. Not yet: vertical bars, icons and
  bars mixed in one group, and conditions on the time left in a row of bars (the status line says so).
- Logging in while already in combat no longer reports "calling 'SetFrameLevel' on bad self (Attempt to
  access forbidden object ...)": Blizzard's aura containers are closed to addons while auras are secret, so
  their levels now wait for the next layout.
- The status line of a sorted group of bars names %n among the texts it keeps.

## 0.8.14-alpha (2026-10-09)

- **Conditions on the time left on every engine-driven display.** A condition on an Aura trigger's
  *Remaining Duration* (for example: at 5 s or less, red and glowing) now works in combat on icons, bars,
  progress textures, textures, texts, stop motions and models, not only in sorted groups. The display is
  drawn as two looks, from the chosen time up and below it, each behind a gate of its own: an aura slot
  whose duration text the game formats wide below the time and narrow above it, drawn invisible, with the
  gate hung on the text's end. What can change is what conditions on stacks can change: colours, desaturate,
  the glow and its settings, a text's colour, size and visibility, and alpha. One time per display, and not
  together with *Stack Count* or conditions on stacks (the status line says so).

## 0.8.13-alpha (2026-10-09)

- **Conditions on the time left in sorted groups.** In a Dynamic Group sorted by the time left, a condition
  on the first child's *Remaining Duration* (for example: at 4 s or less, red and glowing) now applies to
  every icon of the row on its own, in combat too: the DoT about to run out turns red and glows, the others
  stay as they are, and a refresh puts it back. The time left is secret in combat, so the game does the
  comparing: each icon's duration text is formatted wide below the chosen time and narrow above it, drawn
  invisible, and two clips inside the icon hang on its end, one open below the time and one above, each
  holding that side's colour and glow. No total duration is needed, so DoTs of any length share the row.
  One time per row; colour and glow can change. A %p text in the first child leaves no room for it (the
  countdown numbers show the time instead).
- **Glows in sorted groups are animated** (they were drawn still).
- **No gaps when a sorted group cannot be sorted.** When the children of a group sorted by the time left
  were not alike (one DoT with a glow of its own, another size, another unit ...), the group fell back to
  WeakAuras' own layout, with a gap for every absent aura and an order WeakAuras cannot keep in combat. It
  is now packed by the game in the children's order, and the children's status line says why it is not
  sorted.
- Dispel lists regenerated for client 1.60.1.70291 (a few new Magic and Poison spells).

## 0.8.12-alpha (2026-10-07)

- **Stack Count works in combat.** An Aura trigger's *Stack Count* (show at 3 stacks or more, at most 2,
  exactly 5 ...) kept a display from being engine-driven, as the stacks are secret in combat. The game now
  compares them itself: it fills a status bar of its own by the aura's stacks, and two invisible gates around
  the display hang on the edge of that fill, so they open only while the count matches. Everything the display
  draws, its glow included, is behind them. *Missing* triggers ignore the count, as in WeakAuras. Not drawn by
  the engine: `!=` and displays with several Aura triggers.
- **Conditions on stacks work in combat.** A condition on the trigger's *Stacks* (for example: at 3 stacks or
  more, red and glowing) never fired on an engine-driven display. EverAuras now cuts the stack count into
  stretches wherever a condition changes, and draws each stretch as a look of its own, with that stretch's
  changes applied in WeakAuras' order (the last active condition wins, *Else If* chains included). The game
  shows the look that matches. What can change: colours, desaturate, inverse and cooldown settings, the glow
  and its settings, a text's colour, size and visibility, and alpha. Other changes are named on the status line.
- **Dynamic Groups sorted by the time left.** A group set to *Sort: Ascending* or *Descending* was left to
  WeakAuras, which cannot read the time left in combat. When its children are alike Found icons on one unit,
  the game now draws the group as one row of their auras and orders it by the time left itself, in combat too,
  with WeakAuras' *Limit*. Every icon takes the first child's look.
- The status line no longer calls a spell name that has not been seen as an aura yet "not one of your spells"
  as if it were misspelt; it says the name cannot be looked up before the aura has been seen once.

## 0.8.11-alpha (2026-10-06)

- **Part-circle Progress Textures that work in combat.** A circular Progress Texture with a *Start / End
  Angle* (a half ring, a quarter ring, an arc) is now drawn with the game's aura engine. The game's cooldown
  swipe always draws a whole circle, so the arc is cut into small pieces, about 1.5 px of arc each. Each
  piece sits in its own frame that hangs on the edge of the invisible timer bar the engine already fills
  for Progress Textures, so the pieces show and hide one by one as the aura runs out, without the time left
  ever being read. Each piece is WeakAuras' own wedge, so the arc looks the same, and the background shows
  the arc only.
- **Rings run out the right way round.** The swipe's edge only turns clockwise, so *Clockwise* rings
  (without *Inverse*) and *Anticlockwise* rings with *Inverse* used to run out the mirror way of
  WeakAuras' own. They now use the same pieces and match WeakAuras exactly, with desaturate, blend mode
  and legacy rotation kept. The other two settings keep the smooth swipe.

## 0.8.10-alpha (2026-10-06)

- **Stop Motion animations that work in combat.** A Stop Motion display with an aura trigger (*Show On:
  Aura(s) Found* or *Missing*) is now drawn with the game's aura engine. WeakAuras steps through the
  animation's sheet from a script, and scripts never run inside the engine's aura frames, so the game's own
  FlipBook animation plays the same sheet: WeakAuras' built-in ones, sheets named like `.x8y8f64`, and
  custom ones with rows, columns and frames set. Frame rate, *Loop* or *Bounce*, *Inverse*, *Animation
  End*, colours, desaturate, blend mode and the background frame are kept. Not engine-driven yet, with the
  reason in the status line: *Once* and *Progress* animations, an *Animation Start* above 0%, and textures
  made of numbered files.
- **Models that work in combat.** A Model display with an aura trigger (*Found* or *Missing*) shows its
  model only while the aura is up or gone, in combat too: model file or display ID, position or transform,
  rotation, portrait zoom, animation and alpha as in WeakAuras. A unit's model (target, player) stays with
  WeakAuras: it follows its unit through events, which cannot run inside the engine's frames.
- **Progress Bars keep their gradient.** *Enable Gradient* (the bar colour fading into the second colour)
  was ignored on engine-driven bars. Reported by Soul. Thanks!
- The Model Picker's list no longer raises an error each time the mouse moves over a model (its tooltip
  passed the wrap flag where the game expects alpha).

## 0.8.9-alpha (2026-10-05)

- **Dynamic Groups follow a new target.** After switching between dotted targets, a packed group could
  put a DoT one place too far, or leave a gap, until combat ended: the game's aura containers do not
  notice that "target" now means another unit, and EverAuras refreshed the icons but not the hidden
  chain that places them. Both are refreshed now (target, focus and pet). A group set up again while
  nothing is targeted also keeps its packing instead of falling back to fixed places.
- **Old API names work in imported auras.** The Forever client has no fallbacks for API functions that
  moved, so custom code written for other clients stopped at the first one (`GetItemInfo` in a currency
  tracker from wago). Inside aura code only, `GetItemInfo`, `GetItemCount`, `GetItemInfoInstant`,
  `GetItemQualityColor`, `GetItemIcon`, `GetItemSpell`, `GetDetailedItemLevelInfo`, `IsEquippedItem`,
  `GetSpellInfo`, `GetSpellCooldown`, `GetSpellCharges`, `GetSpellTexture`, `GetSpellLink`,
  `GetSpellDescription`, `IsUsableSpell`, `GetCurrencyInfo`, `IsAddOnLoaded` and `GetAddOnMetadata` now
  fall back to their modern homes, with the old return values. A real global of that name always wins.
- **Auras made in current M33kAuras import.** M33kAuras moved to a newer internal data version, and
  EverAuras refused its export strings as "made with a newer version". They import now. EverAuras does not
  have M33kAuras' new *Ruleset* load option yet: an aura limited to Hardcore or PvP realms loads
  everywhere. Reported by Metz. Thanks!

## 0.8.8-alpha (2026-10-02)

- **Dynamic Groups that close up in combat.** When every child of a Dynamic Group is an engine-driven
  display (Icon, Progress Bar, Progress Texture, Texture or Text with *Show On: Aura(s) Found*), the game
  packs them: a child whose aura is absent leaves no gap, also in combat. Grow left, right, up, down or
  centred (horizontal or vertical), with your spacing, order and alignment; children may watch different
  units (a centred group needs one). Before, engine-driven children kept their place, so a DoT row had
  holes. While packed, a child shows its icon, bar or texture, its `%p` / `%s` / `%n` texts and its glow;
  its border and other texts are hidden. Not packed, with the reason in the children's status line: groups
  that sort by time left (secret in combat), limit or stagger their children, grow in a circle, a grid or
  by custom code, anchor per unit, or have a child that is not engine-driven, not *Found*, or carries a
  model, texture or tick.

## 0.8.7-alpha (2026-10-02)

- **Texts that work in combat.** A Text display with an aura trigger is now drawn by the game's aura
  engine: a "NO DEMON SKIN!" warning (*Show On: Aura(s) Missing*) shows while your buff is gone, a
  "Corruption: %p" timer (*Found*) counts down, also in combat. Plain text, `%p` (time left), `%t` (total),
  `%s` (stacks) and `%n` (name) work, also with other words around them ("Corruption: 12 s"); `%n` and
  `%i` of the one spell a display tracks are filled in ("%n is missing!" reads "Demon Skin is missing!").
  Font, size, outline, colour, shadow, justify, width and animations are kept. The game formats the time
  itself ("12 s"), so WeakAuras' `%p` format options do not apply; with other words, 0 stacks read 0; a
  SLUG outline is drawn as a normal outline. Not engine-driven yet, with the reason in the status line:
  two kinds of values in one text (time and stacks), `%c`, and *Show On: Always*.
- **Texts on engine-driven icons, bars and textures sit where you put them.** The `%p` / `%s` / `%n`
  text of an engine-driven display ignored its X/Y offset and anchored *Automatic* the icon way on every
  display, so it could show elsewhere in combat than in the options. Reported by JakeD. Thanks!
- Dispel spell lists regenerated for client 1.60.1.70170 (three entries changed).

## 0.8.6-alpha (2026-10-01)

- **Textures for procs, in combat.** A Texture display with an aura trigger is now drawn by the game's aura
  engine: *Show On: Aura(s) Found* shows it while your proc or buff is up, *Aura(s) Missing* while it is
  gone (your Demon Skin dropped off), in combat too. Your texture, colour, rotation, mirror, desaturate and
  blend mode look exactly as in WeakAuras. *Show On: Always* needs no engine for a texture and stays with
  WeakAuras. JakeD's other wish. Thanks again, JakeD!
- **Glow on Progress Textures and Progress Bars** shows and hides with the aura, animated like WeakAuras'
  own (Button, Pixel, Autocast, Proc), in combat too. Bars keep the glow's *Anchor Area* (the whole bar,
  its icon or its bar). Before, the glow was hidden on textures and shown all the time on bars.
- While a texture is engine-driven its border is hidden: WeakAuras keeps the display in place even when
  the aura is gone, so the border would frame an empty spot.

## 0.8.5-alpha (2026-10-01)

- **Progress Textures that work in combat.** A Progress Texture display with an aura trigger (*Show On:
  Aura(s) Found*) is now drawn by the game's aura engine, like Icons and Progress Bars, so it keeps
  counting down in combat while auras are secret. Straight ones (vertical, horizontal, either way) empty
  as the aura runs out with your texture, colours, crop, rotation, mirror, *Compress* and background;
  circular ones are the game's cooldown swipe drawn with your texture. `%p`, `%s` and `%n` texts count
  along. Asked for by JakeD, who times his buffs and debuffs with them. Thanks, JakeD!
- The game's swipe only turns clockwise: circular textures set to *Anticlockwise* (or *Clockwise* with
  *Inverse*) look exactly as in WeakAuras; the other two run out the mirror way, and the status line says
  so. Not engine-driven yet, with the reason in the status line: part circles (*Start* / *End Angle*),
  atlas textures on circles, adjusted minimum / maximum progress and other progress sources. While a
  texture is engine-driven its glow and border are hidden, and slanted ends are drawn straight.

## 0.8.1-alpha (2026-09-30)

- **Packaging fix, nothing changes in game.** CurseForge rejected 0.8.0-alpha: the EverAurasTemplates folder
  carried upstream's `M33AurasTemplates.toc`, a name that does not match the folder, so the game never
  loaded that folder in any release (the options said "Templates could not be loaded"). The release no
  longer contains it; its templates are retail class setups that were never checked on Forever. 0.8.1 is
  0.8.0 otherwise.

## 0.8.0-alpha (2026-09-30)

- **Sounds that play at the right moment, in combat too.** An engine-driven display's *On Show* / *On Hide*
  sound used to play only when you logged in or closed the options, never when the aura came or went:
  the game draws these displays, so WeakAuras never sees the aura change. EverAuras now hands those sounds
  to the game, which plays them itself: on a *Missing* display *On Show* plays when the aura drops off (your
  Demon Skin ran out), on a *Found* display when it lands; *On Hide* the other way round. Works in combat and
  for debuffs on you. A *Sound Kit ID* cannot be handed over; pick a sound file (the Trigger tab says so).
  *Show On: Always* keeps WeakAuras' own sounds.
- **Auras by dispel type, in combat.** *Debuff Type* (Magic, Curse, Disease, Poison, Enrage, None), *Is
  Stealable*, *Is Boss Debuff* and *Cast by Player* now work on engine-driven displays, also for debuffs on
  you, where Blizzard does not let addons pick auras by spell. Leave *Name(s)* and *Exact Spell ID(s)* off
  and the display shows any matching aura with its own icon and countdown: "a poison on me", "a Magic
  debuff on me", "a Magic buff on my target" for Purge / Dispel Magic.
- **Their sounds work from the first time.** The game plays aura sounds by spell only, so EverAuras ships
  the spell lists per dispel type, taken from the game's own spell tables (about 1,600 debuffs), and also
  remembers every typed aura it can read out of combat on you, your pet, target, focus, group and nearby
  enemies. A murloc's Frostbolt honks the first time. Registering the sounds takes a few milliseconds when
  you log in or change a display; nothing runs while you play. The game keeps aura sounds over a `/reload`;
  EverAuras removes its old ones when it starts, so a sound never plays twice.
- New developer tool: `tools/gen_dispel_data.py` regenerates the spell lists from an installed client (a
  small WDC5 reader, `tools/wdc5.py`, reads the client's own spell tables).

## 0.7.2-alpha (2026-09-28)

- **Animated glow in the last X seconds.** A display with *Remaining Time* < X on an aura trigger now shows its
  WeakAuras glow *animated* while the aura runs out, in combat too: Button Glow's ants crawl, Pixel Glow's lines
  circle, Autocast Shine sparkles, Proc Glow loops, all with your settings, for the last X seconds only. Two
  recipes: one trigger with *Remaining Time* < 3 gives an icon with an animated glow for the last 3 seconds;
  add a second trigger on the same aura with *Aura(s) Found* and no Remaining Time, set *Required for
  Activation: Any Triggers*, and the one icon shows the whole time with its countdown, glowing for the last
  3 seconds. The engine sizes a bar by the aura's remaining time, which the
  game fills, and a clip anchored to the bar's fill edge opens exactly when X seconds are left; the glow lives in
  it. The aura's total duration comes from what EverAuras learned of it out of combat or from the spell's
  description ("... over 18 sec"). Asked for by Carl. Thanks, Carl!
- **Glows are moved by the game, not by scripts.** While an aura is shown, the game refuses to let addon code
  re-position anything anchored to its aura frames, which is where these glows live, so Pixel Glow and Autocast
  Shine, which moved their lines and sparkles every frame, stood still or filled BugSack ("Attempt to access
  forbidden object"). All four glow types are now driven by animations (Path, FlipBook): nothing runs per frame
  and nothing is re-positioned. Pixel Glow's lines are drawn as squares turned 45 degrees riding the border ring
  under a mask, which bends them round the corners the way LibCustomGlow's do.
- Fixed an error ("engine (layout) ... GetFrameLevel") when frame levels were re-applied while an aura was shown.

## 0.7.1-alpha (2026-09-28)

- **Debuffs on you (Weakened Soul, Forbearance, Recently Bandaged ...):** Blizzard's aura containers refuse to pick
  debuffs on friendly units (you, your pet, a friendly target) and buffs on hostile units by spell while auras are
  secret, so such a display could never match in combat, and the status line wrongly said "Engine-driven". It now
  says why. New option, *Display tab -> Match debuffs on you by their properties (approximation)*: EverAuras learns the
  debuff's fingerprint the first time it lands on you out of combat (duration, dispel type and the flags Blizzard does
  let addons filter on) and the engine shows a debuff on you that matches all of it, e.g. Weakened Soul for a priest.
  *Own Only* decides whether only debuffs you put on yourself count. Reported by Carl, a priest levelling on the beta. Thanks, Carl!
- **Countdown numbers on aura icons match Blizzard's buff frame.** The Cooldown swipe's numbers round up (36.4 s left
  showed "37") while the buff frame rounds down ("36 s"). Icons whose triggers are all Aura triggers now count like the
  buff frame, in and out of combat; over 90 s they show minutes the way Blizzard does. Spell cooldown icons keep the
  default, which counts like the action bar.
- Target and focus displays note when their spell is not yours and the filter cannot apply on a friendly target
  (debuffs) or an enemy target (buffs).
- Learned aura durations are stored to a tenth of a second; the max-duration filter gets half a second of headroom.

## 0.7.0-alpha (2026-09-27)

- **Animated glow on engine-driven icons:** WeakAuras' Button Glow, Pixel Glow, Autocast Shine and Proc Glow, with
  your colour, lines, frequency, length, thickness, scale and offsets, now animate on engine-driven icons, in
  combat too, and show only while the icon does: while the aura is present (*Aura(s) Found*) or missing
  (*Aura(s) Missing*). The glow runs inside a frame whose width the game sets from the aura, so it is clipped away
  exactly when the icon is. Blizzard refuses to move frames into such a frame, so EverAuras draws the four glow
  types itself (`ForeverGlow.lua`) with everything created in place; looks and motion follow LibCustomGlow.
- Time-left icons keep the static glow; on displays with both a missing and a time-left part, *Display tab →
  Glow* still chooses where it goes. *Show On: Always* keeps WeakAuras' own glow as before. The Proc Glow's
  one-off start burst is left out.
- **Safer engine:** an error inside the engine can no longer stop EverAuras from loading. It is reported to
  BugSack once and the displays load as usual.

## 0.6.1-alpha (2026-09-27)

- **Weapon Enchant trigger sees Shaman imbues:** on Forever, Rockbiter, Windfury and the other imbues are
  their own enchant type (*Imbue*), which the old function WeakAuras asked never reported, so a "Rockbiter
  missing" icon stayed on even with Rockbiter up. The trigger now reads the newer API, which reports imbues as
  well as stones, oils and poisons, in and out of combat. Found and diagnosed together with Johnny on our
  Discord. Thanks, Johnny!
- Tip: the Weapon Enchant name is the one on the weapon's tooltip (*Rockbiter 3 (60 min)* → `Rockbiter`,
  *Sharpened +2 (30 min)* → `Sharpened`), not the spell or item name. Leave it empty for "any enchant".

## 0.6.0-alpha (2026-09-27)

- **Time left, in combat:** *Remaining Time* on an Aura trigger (*Show On: Aura(s) Found*; `<`, `<=`, `>`, `>=`)
  is engine-driven for icons. The icon, and its `%p` countdown, show only while the aura has that much time
  left. The game evaluates a colour curve over the remaining time itself; the addon never reads it (tested in
  combat with Serpent Sting under 5 s).
- **Missing or about to run out:** one *Aura(s) Missing* trigger plus *Aura(s) Found* + *Remaining Time*
  triggers, combined with *Any Triggered* or with a custom combination of the form *(other triggers) and (any
  Aura trigger)*: the classic "refresh your DoT" icon. Imported packs built this way become engine-driven, e.g.
  9 of the 10 DoT icons of a TBC Affliction tracker (the tenth mixes units between its triggers).
- **Other triggers next to an Aura trigger** (*in combat*, *target attackable or hostile*, *talent known*, *item
  count* …): the engine draws the aura part and WeakAuras evaluates the other triggers itself, which works in
  combat for plain data. Health and power amounts stay secret on Forever.
- **Glow on engine-driven icons:** WeakAuras' glow sits on the region, which stays visible while the engine
  decides what is drawn, so it framed an empty spot. Engine-driven icons now draw a static glow (the Button
  Glow texture with WeakAuras' colour, scale and offsets) that follows the icon: while the aura is present,
  missing or running out. A display with both a missing and a time-left part chooses where it goes
  (*Display tab → Static glow*). *Show On: Always* keeps WeakAuras' own animated glow.
- Limits of time-left icons: no cooldown swipe, stack count, desaturation or border, and the glow does not
  animate. The status line on the Trigger tab says what applies to each display, and names the reason when a
  combination cannot be engine-driven.
- `tools/classify_imports.py` now loads the engine itself, so its verdicts cannot drift from the addon: 68 of
  116 displays in seven Classic packs are engine-driven (was 49), 4 stay blind.
- GitHub issue forms for bug reports and feature requests.

## 0.5.0-alpha (2026-09-25)

- **Engine-driven Progress Bars** (*Show On: Aura(s) Found*): Blizzard's aura button fills a real status bar with
  the aura's own duration, so DoT and buff timer bars work in combat. Icon, name (`%n`), timer (`%p`) and stacks
  (`%s`) come along; texture, colours, orientation and *Inverse* are taken from the WeakAuras bar. The range gate
  and the power options work on bars too.
- **Own Only now means "cast by you"** for engine-driven icons and bars (Blizzard's `PLAYER` filter). Before, any
  player's copy of the aura counted, e.g. another hunter's Serpent Sting on your target.
- **SavedVariables work on client build 1.60.1.70009.** The bridge watcher is no longer part of the install; the
  README says so and `tools/sv_bridge.py` stays only for older builds.

## 0.4.1-alpha (2026-09-24)

- **Leaner install:** the zip holds only the five EverAuras folders. The `M33Auras` / `WeakAuras`
  settings-migration stubs are gone: there is nothing to migrate from on Forever, the folder names belong to
  other addons, and on an empty database (every login, while SavedVariables are not read back) the migration
  code loaded and disabled whatever addon had those names. It is switched off on Forever. When upgrading,
  delete those two folders if the addon list calls them "EverAuras Settings Migration".
- **Imported media:** texture, sound and font paths pointing into WeakAuras, M33kAuras or ForeverAuras folders
  are rewritten to EverAuras' own copy of the same media on import and load (8.8 MB less to ship).
- `!ForeverCompat` (a shim for idTip's old AceGUI checkbox) is no longer shipped; EverAuras does not need it.
  It stays in the repository for development.
- The build script no longer deletes folders of other addons (M33kAuras, ForeverAuras); only its own stubs.

## 0.4.0-alpha (2026-09-24)

- **Power options** for Icons and Progress Bars (Display tab, *Power (WoW: Forever)*): *Hide while full* and
  *Colour below a threshold*, for player / target / focus / pet and mana / rage / energy / focus. Resource values
  are secret to addons on Forever (the player's mana even out of combat), so upstream's *Power (%)* conditions
  never fire; here Blizzard evaluates the percentage (`UnitPowerPercent` with a curve) and the secret result goes
  straight into the display's alpha or colour.
- **Five Second Rule (mana)** trigger (Player/Unit Info): a 5 s timer on your own mana-costing casts, in combat
  too. Measured on build 69977: regen resumes exactly 5.00 s after the cast and is continuous (no ticks).
- **Custom code that reads a secret value** (an aura's own custom trigger, text, check or action) now gets one
  clear message per aura instead of the generic "install BugSack" error, and reaches BugSack once per aura and
  place instead of on every event.
- **Imported auras:** globals the Forever client no longer has are replaced (`IsCurrentSpell` for the Queued
  Action trigger and the queued-spell watcher, `IsSpellKnown` for Spell Known checks, the missing loss-of-control
  cooldown API).
- The *Aura(s) Missing cannot be answered* notice says why the display is not engine-driven (e.g. the engine
  toggle is off).
- `tools/classify_imports.py` decodes WeakAuras export strings offline and predicts, per display, whether it
  works in combat on Forever. `!ForeverSVCanary` tells after each client patch whether SavedVariables are read
  back yet; `/fdmana` measures mana regeneration.

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

- Renamed from the working name ForeverAuras to EverAuras, to avoid a clash with an unrelated project of the
  same name (new logo, `/ea` and `/everauras`, project links).
- Engine-driven aura displays (found / missing / always) confirmed working in combat; cooldown displays and
  `%p` remaining-time text through duration objects; *Is Ready (Secret)* → *Alpha (Boolean)* conditions.
- SavedVariables bridge: never-shrink guard against an empty aura database overwriting a good seed.
