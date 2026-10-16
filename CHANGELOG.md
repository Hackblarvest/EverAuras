# Changelog

## 0.9.4-beta (2026-10-16)

- **WeakAuras' time format on `%p`.** The *Format: Time Format* options of a `%p` or `%t` text
  (WeakAuras' Built-In, Old or Modern Blizzard, more digits below a threshold) are now drawn by the game
  too, in combat: "4" without the "s", "2.4" below your threshold, "1:05" past a minute. Without a chosen
  time format the game's own format stays ("4 s").
- **The time in other forms on sub-texts.** Sub-texts with the time of a numbered trigger (`%1.p`), the
  total time (`%t`) or the time inside other words ("Left: %p") are now drawn on engine-driven icons and
  bars, in combat too, when no bare `%p` text or text with time and stacks takes the countdown.
- A group sorted by the time left whose time text shows the spell's name or icon (`%n`, `%i`) is no longer
  sorted: every icon of the row would show the first child's.

## 0.9.3-beta (2026-10-14)

- **No more gaps in mixed rows.** A centred Dynamic Group that holds both your buffs and your target's
  DoTs (like the "Effects" rows of the ForeverAuras class packs) now closes up in combat too: the icons
  sit side by side, centred, and the row closes again when you change or lose your target. Children with
  conditions on the time left or the stacks pack too, and so do rows of Progress Bars.
- **"Red below 3 s" on a countdown.** A condition on the time left that only colours the `%p` text is now
  drawn by the countdown itself (the game turns its colour at that time, in combat too, with one aura slot
  instead of four). A `%p` text with a colour of its own now shows that colour instead of white.

## 0.9.2-beta (2026-10-14)

- **Aura strings from ForeverAuras import.** They carry a data version of their own (91, one above
  WeakAuras and M33kAuras), so EverAuras refused them as "made with a newer version". Now they import, and
  the parts that differ are translated to EverAuras' own:
  - their in-combat aura trigger becomes the Aura trigger, which the engine draws in combat (DoTs, buffs,
    procs, any rank of a spell), with its conditions on the time left and on found / missing;
  - their flow groups become Dynamic Groups, and their class load (*Class and Specialization* with
    Forever's specs) becomes *Class*;
  - "hide at 20% mana and above" and similar conditions on a resource become the power gate (below).

  One chat line per import says what was brought over and what EverAuras does not have (their Blizzard
  Cooldown Manager and Ammo triggers, pandemic conditions, highlight effects and spec load option). Tested
  with 130 ForeverAuras strings from wago.io: 488 of the 522 displays that use their aura trigger are drawn
  by the engine in combat. Only the aura data is translated. Thanks to Jax for asking.
- **Hide a display by a resource at a threshold.** *Display tab, Power*: besides *hide while full*, hide a
  display at or above X% (a "LOW MANA" text hidden from 20% up) or below X% of your mana, rage, energy or
  focus (or your target's, focus' or pet's), now also on Texts, Textures and Progress Textures. The amounts
  are secret on Forever, even your mana out of combat; the game compares them for EverAuras.

## 0.9.1-beta (2026-10-13)

- **The first official EverAuras aura: EverAuras Shield** on wago.io, as a
  [curve](https://wago.io/_0najWd4T) or a [ring](https://wago.io/G4WYlUMi5) (option *Style* switches
  between them). It shows how much your absorb shields still take (Power Word: Shield, Sacrifice, Ice
  Barrier, Fire, Frost and Shadow Ward, Templar's Bulwark, protection potions, trinkets ...): a curved
  column of segments with the number below, or a ring with the number inside, in combat too. Mana Shield
  does not show: the game leaves it out of the absorb amount addons can read. The curve's design is
  inspired by nan Shield (Hamersteen) and nanShield - Forever (Billie Jeanne).
- **Absorb rings and bars without code.** A Health trigger with *Fetch Absorb*, and *Progress Source:
  Trigger 1 - Absorb* on a Progress Texture or a Bar, draws your absorb against your max health, in combat
  too (M33kAuras' feature, now checked on Forever).
- **On Wago Addons.** EverAuras is on [Wago Addons](https://addons.wago.io/addons/everauras), and the Wago
  app (like the CurseForge app) recognises an installed EverAuras and keeps it up to date.
- Lines an aura's own code prints to chat are tagged `[EA]` instead of `[WA]`.

## 0.9.0-beta (2026-10-11)

- **Beta.** EverAuras now builds on the newest M33kAuras (`fd03b21`, release 5.20.7-rg4-m99: 73 changes
  since 0.8.17, most of them for Forever), and it meets the bar set for a beta: every display type works
  in combat, conditions on the stacks and on the time left work, icons and bars sort by the time left, no
  bug from Discord is open, and the tests pass. Thanks to Solos for the party test.
- **New from M33kAuras on Forever.** Load options for Talent, Game Mode (PvE, PvP, RP, Hardcore), PvP
  Flagged and On Taxi; Raid Role now works. Triggers: Talent Known, Character Stats, Health, Totem (also
  while totem info is secret) and Threat with partly secret data. An encounter browser for Forever's
  dungeons and raids, boss1-10 units, focus auras that follow a new focus, and better spell-ready and
  global-cooldown detection for Cooldown and Spell Usable triggers. Faster import and export with the
  game's own compression (export strings keep the same format), and a faster aura list in the options with
  the game's own right-click menus. EverAuras is listed in the minimap's addon compartment.
- **The options know every spell** with a classic spell id: names autocomplete and show their icon, and
  *Browse never-secret auras* (Aura trigger) lists what Blizzard keeps readable in combat. The list is
  built in the background the first time you open the options after an update or a game patch; leave
  `/ea` open for a minute, out of combat. Your own spells come from your spellbook, also the new ones you
  learn. (Forever's own spell ids are left out: asking the game about one of them closes the client with a
  fatal error.)
- **What may look different.** `%p` and `%t` on cooldowns, casts and totems read in combat as they do out
  of combat ("1:54", "2.9"). *Instance Difficulty* and *Instance Type* are no longer offered or checked on
  Forever (upstream): auras that used them now load everywhere; *Instance Size Type* tells Forever's raids
  apart (10, 20, 25 or 40 players). Triggers upstream removed on Forever (PvP Talent Selected, Class/Spec,
  Loot Specialization) become empty Condition triggers. *Spell Usable* checks the exact spell (its rank),
  and *Target Required* now means "has a valid target".
- **Kept as before.** New auras and *Add Trigger* start with an Aura trigger, the kind the game's aura
  engine draws (upstream now starts with *Condition*). The engine's status line replaces upstream's
  "This trigger cannot track secret auras" note on displays the engine draws. The footer of the options
  keeps the EverAuras Discord button; *About EverAuras* opens this project's page.
- An *Aura(s) Missing* display that EverAuras hides in combat (because it cannot know whether the aura is
  there) now shows again as soon as combat ends, and one shown before combat is hidden as combat starts;
  a Missing trigger with spell names is never answered while auras are secret.
- An old *Hardcore* load check (from Classic imports, ignored on Forever until now) becomes the *Game Mode*
  option once, and those auras are named in chat.
- Auras written in M33kAuras whose custom code calls `M33kAuras.` work in EverAuras too.
- A Progress Texture whose first trigger is not the Aura trigger (a Power, Health or cooldown trigger with
  secret progress) no longer shows WeakAuras' own fill on top of the engine's in combat.
- A broken or cut-off import string gives "Error decompressing" instead of a Lua error.

## 0.8.17-alpha (2026-10-11)

- **Refresh icons: missing, or too few stacks.** One *Aura(s) Missing* trigger and one *Aura(s) Found*
  trigger with a *Stack Count* (or conditions on its stacks), combined with *Required for Activation: Any
  Triggers*, now work in combat: for example Sunder Armor while it is absent or below 5 stacks, or Demon
  Armor, which does not stack (0 stacks, as in WeakAuras, so its Found trigger takes *Stack Count* < 1): it
  glows while it is missing and shows as the live buff while it is up. While the aura is absent you see your
  icon, texture or animation; while its stacks match, the live aura (on an icon with its countdown, stacks
  and swipe). With conditions on stacks but no *Stack Count*, the live aura shows at any count, in the look
  of its stacks. The game compares the stacks itself, as for *Stack Count* alone. Both triggers must track
  the same aura (the same spells, buff or debuff, and *Own Only* on the Missing trigger needs it on the
  Found trigger too). *Display tab → Glow* chooses where the glow goes: *Both*, *Only on the live aura (its
  stacks match)* or *Only while it is missing*. With a *Stack Count*, an *On Show* sound plays each time the
  aura is lost (also when the display was already showing because its stacks matched); *On Hide* is not
  played, nor *On Show* when the stacks come into the count, as no aura event marks the moment the stacks
  reach or leave it. With conditions on stacks alone, neither sound plays. Icons, Textures and Stop Motions
  so far (the status line says so).
- **Time and stacks in one text.** A text with the time left and the stacks together, such as '%p (%s)' or
  'Corr %s - %p', now works in combat, on a Text display (*Show On: Aura(s) Found*) and as a sub-text of
  engine-driven icons, bars and textures. The game writes one value into each of its texts, so EverAuras
  draws two of them side by side, one hung on the end of the other, and they stay together as the game
  rewrites the time. At 0 stacks (a DoT that does not stack) the number is left out and the words stay, as
  in WeakAuras. A text hung by a left or right point sits exactly (a Text display's *Anchor*, or its
  *Justify* with *Width: Fixed*; a sub-text's anchor on the icon or bar); one hung by its middle, as a new
  Text display is (*Anchor: Bottom*), is placed by an estimate of the stacks' width, so it may sit a pixel
  or two beside WeakAuras' place. On a Text display, *Width: Fixed* only places the text (no word wrap). A
  display has one time text and one stack text of the game, taken by its texts in the order they are listed:
  a '%p (%s)' sub-text takes both, so a %p or %s sub-text below it is hidden, and a '%p (%s)' below a lone
  %p or %s is hidden itself (a new icon starts with a '%s' text and a new bar with a '%p' one: change that
  text into '%p (%s)', or hide it). The status line names a hidden text. Not drawn, with the reason on the
  status line: the time on both sides of the stacks, %s twice, a line break, or { } next to the time.
- **Start and Finish animations, in combat.** WeakAuras plays a display's *Start* animation when it shows
  and its *Finish* when it hides, but the game shows and hides an engine-driven display, so neither played
  when the aura came or went. The game now plays them itself, also in combat: *Start* on a *Show On: Aura(s)
  Found* display when the aura is put on (Corruption on your target slides or grows in), *Finish* on an
  *Aura(s) Missing* display when the aura is put on and the display goes (a "NO DEMON ARMOR" warning fades
  out as you buff). Icons, Textures and plain Texts, with a *Preset* or a custom animation: *Fade In* /
  *Out*, *Slide In* / *Out* (custom slide functions too) and *Zoom In* / *Out*, with its *Ease type*; a fade
  or zoom of another *Type* than *Normal* (*Pulse*, *Hide*, *Spin*, *Flip* or a *Custom Function*) is drawn
  as a straight change from its first to its last value.
- The game redraws its aura buttons when you enter or leave combat and when you loot, which would play the
  animations again, so each is shown only during the first seconds after the aura was put on (the
  animation's length plus up to about a second): later redraws do not replay it, but one within those
  seconds does (pulling right after a re-buff flashes a *Finish* once). For the same reason the game plays
  none when you switch to a target or meet someone who already has the aura, nor, by design, for an aura
  without a duration (not yet tried in game). WeakAuras still plays its own *Start* and *Finish* when it
  shows or hides the display itself, as before (when you pick a target after having none, or clear it).
  While a *Start* plays, and for those seconds after each refresh of the aura, a copy stands in for the
  display (an icon's copy shows its swipe and a lone %s stack text, not its other texts or a static glow).
- Not drawn, with the reason on the status line: *Finish* on Found displays and *Start* on Missing displays
  (the game gives addons no moment when an aura goes), animations on Progress Bars, Progress Textures, Stop
  Motions, Models and texts with the aura's time, stacks or name, on refresh icons and on displays shown
  from 2 stacks or more, *Start* on displays with a time-left part and in groups sorted by the time left,
  *Rotate In* / *Out* and *Color*, and *Time in: Relative* (% of progress, which addons cannot read). *Main*
  animations stay WeakAuras' own and play on engine-driven displays as usual (Pulse on an icon, for
  example); so do all animations on *Show On: Always* displays.
- A display with a *Missing* part (such as a missing-DoT icon on your target) or a Found icon with an
  animated glow that WeakAuras showed anew in combat, for example as you picked a target, could stop with
  "calling 'SetFrameLevel' on bad self (Attempt to access forbidden object ...)" in BugSack and leave
  WeakAuras' own texts showing next to the engine's. Blizzard closes the frames hung on its aura containers
  to addons while an aura is shown in combat; EverAuras now sets their levels only where the game allows it.
- The status line no longer says that an *Active* condition on an Aura trigger never fires: WeakAuras sees
  an engine-driven trigger as always active, so the condition is always true and its changes apply all the
  time, and the status line now says so.

## 0.8.16-alpha (2026-10-10)

- **Auras on party and raid members.** An Aura trigger on a *Specific Unit* from party1 to party4 or raid1
  to raid40 is engine-driven: your Renew, Power Word: Shield or Fortitude on a group member, in combat too,
  with its countdown and conditions on the time left. When the roster changes, the display follows whoever
  is in that slot. Blizzard does not let addons pick debuffs on group members by spell while auras are
  secret; by *Debuff Type* alone (Magic, Poison ..., no spell names, *Show On: Aura(s) Found*) they work.
- **Group triggers: someone has it, someone lacks it.** An Aura trigger on *Unit: Party* or *Smart Group*
  with *Unit Count* '> 0' (or '>= 1', '!= 0') or '< 100%' (or '!= 100%') now works in combat, for example
  "SOMEONE NEEDS FORTITUDE" while one of you lacks it, gone once all have it. EverAuras keeps a copy of the
  display for each of you (you and party1 to party4), all at the display's place: it shows while anyone has
  (or lacks) the aura, and when several have it you see one of them (not necessarily the one with the least
  time left; Auto-Clone shows each). *Ignore Self*, *Ignore Dead* and *Ignore Disconnected* apply. In a
  raid, Party and Smart Group watch only your own party.
- **Auto-Clone per party member.** *Auto-Clone (Show All Matches)* on *Unit: Party* or *Smart Group* draws a
  copy per member who has the aura, or, with *Combine Matches Per Unit* and *Show Matches for: Unaffected*,
  per member who lacks it. In a Dynamic Group with *Group by Frame* set to *Unit Frames*, each copy sits at
  its member's unit frame in the display's own place among the group's children (for example Renew first,
  Shield second, a "no Fortitude" icon third; a place stays empty while its aura is absent), growing Left,
  Right, Up or Down. Your own copy needs a party frame for you: raid-style party frames have one, Blizzard's
  classic party frames do not, so there you get none, as in WeakAuras. In a Dynamic Group that does not
  group by frame, the copies stand in a row from the display's place, one place per member (they do not
  push the group's other children aside, so put such a display last or in a group of its own); outside a
  Dynamic Group, all copies sit at the display's place, as WeakAuras' clones do.
- Not yet for group triggers (the status line says so): *Unit: Raid*, other Unit Counts, *Remaining Time*
  and *Stack Count* on the trigger, a second Aura trigger on the display, the class / role / name / pet /
  Match Count filters, debuffs by spell, *Auto-Clone* for *All* members or for *Unaffected* together with a
  Unit Count, and sounds on aura gain/loss (they are muted rather than played once at login). Conditions on
  stacks or the time left are not drawn, and *Ignore out of checking range* is not applied yet.
- Spell names you track on others are now also learned from party and raid members' auras out of combat.
- When you switch target or focus, the extra looks drawn for conditions on stacks or the time left are
  refreshed along with the display.
- A trigger switched from Party back to a single unit no longer falls back to the classic scanner over its
  leftover Unit Count.

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
