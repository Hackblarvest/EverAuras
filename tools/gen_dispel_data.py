"""Generate tools/forever_files/ForeverDispelData.lua: spell ids per dispel type from the client's own
spell tables, split into debuffs and buffs.

Why: the game plays aura sounds by spell id only (C_UnitAuras.AddAuraSound), so a display that matches
"a Poison debuff on you" needs the ids of every poison. Learning them in game works only for auras that
are still on out of combat; a murloc's 5-second Frostbolt never is. The client ships the answer:

  SpellCategories.db2   DispelType per spell (1 Magic, 2 Curse, 3 Disease, 4 Poison, 9 Enrage)
  SpellEffect.db2       what the spell's aura effects do: their implicit targets (an enemy = a debuff,
                        yourself / an ally = a buff) and harmful aura types (damage over time, slows,
                        stuns, roots, fears, silences, ...)
  SpellName.db2         names, for the report only

Spells neither rule can place ("unknown": mostly projectiles and procs whose aura sits on a triggered
spell) go into both lists: they add registrations, but a sound only plays when an aura is really applied.
Checked against 50 auras seen in game on 1.60.1 (September 2026): 50 of 50 agree.

Usage:
  python tools/gen_dispel_data.py --db2 <folder with spellcategories.db2, spelleffect.db2, spellname.db2>
  python tools/gen_dispel_data.py --install "<WoW folder>" --tacttool <path to TACTTool.exe>
      extracts the three tables from the installed client first (TACTTool: github.com/wowdev/TACTSharp)
Options: --product (default wow_classic_beta), --out (default tools/forever_files/ForeverDispelData.lua)
"""
import argparse, collections, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import wdc5

TABLES = ("spellcategories", "spelleffect", "spellname")
DISPEL = {1: "Magic", 2: "Curse", 3: "Disease", 4: "Poison", 9: "Enrage"}

# SpellCategories layout 679EF94C inline fields: DifficultyID, Category, DefenseType, DiminishType,
# DispelType, Mechanic, PreventionType, StartRecoveryCategory, ChargeCategory (+ relation SpellID)
CAT_DIFFICULTY, CAT_DISPEL = 0, 4
# SpellEffect layout 5362E3D4 inline fields: EffectAura 0, DifficultyID 1, EffectIndex 2, Effect 3, ...,
# ImplicitTarget[2] 28 (+ relation SpellID)
EFF_AURA, EFF_DIFFICULTY, EFF_EFFECT, EFF_TARGETS = 0, 1, 3, 28
KNOWN_LAYOUTS = {"spellcategories": 0x679EF94C, "spelleffect": 0x5362E3D4, "spellname": 0x782EE721}

# SpellEffect.Effect values that apply an aura, and the ones that are area auras on allies / enemies
AURA_EFFECTS = {6, 27, 35, 65, 119, 128, 129, 143, 174, 202}
ALLY_AREA_EFFECTS = {35, 65, 128}
ENEMY_AREA_EFFECTS = {129}
# Implicit targets (Targets enum) that point at an enemy, or at yourself / an ally
ENEMY_TARGETS = {6, 15, 16, 24, 28, 54, 77, 104, 108, 110, 111, 112, 113, 114, 115, 116, 117, 122, 128}
ALLY_TARGETS = {1, 5, 20, 21, 27, 30, 31, 33, 35, 37, 45, 56, 57, 61, 64, 94}
# Aura types that only ever hurt: periodic damage, confuse, charm, fear, stun, root, silence, slow,
# leech, pacify, mana leech, percent damage, ...
HARMFUL_AURAS = {3, 5, 6, 7, 12, 26, 27, 33, 53, 60, 64, 89, 95, 162}


def extract(install, tacttool, product):
    info = open(os.path.join(install, ".build.info"), encoding="utf-8").read().splitlines()
    head = info[0].split("|")
    col = {h.split("!")[0]: i for i, h in enumerate(head)}
    row = next(l.split("|") for l in info[1:] if l.split("|")[col["Product"]] == product)
    build, cdn, version = row[col["Build Key"]], row[col["CDN Key"]], row[col["Version"]]
    out = tempfile.mkdtemp(prefix="db2_")
    for t in TABLES:
        subprocess.run([tacttool, "-p", product, "-r", "us", "-b", build, "-c", cdn, "-d", install,
                        "-m", "name", "-i", "dbfilesclient/%s.db2" % t], cwd=out, check=True,
                       stdout=subprocess.DEVNULL)
    return os.path.join(out, "dbfilesclient"), version


def targets(v):
    t = v[EFF_TARGETS]
    if isinstance(t, list):
        return [x & 0xFFFF for x in t]
    return [t & 0xFFFF, (t >> 16) & 0xFFFF]


def classify(effects):
    enemy = ally = harmful = False
    for v in effects:
        eff = v[EFF_EFFECT]
        if eff not in AURA_EFFECTS:
            continue
        a, b = targets(v)
        if eff in ENEMY_AREA_EFFECTS or a in ENEMY_TARGETS or b in ENEMY_TARGETS:
            enemy = True
        if eff in ALLY_AREA_EFFECTS or a in ALLY_TARGETS or b in ALLY_TARGETS:
            ally = True
        if v[EFF_AURA] in HARMFUL_AURAS:
            harmful = True
    if enemy and not ally:
        return "debuff"
    if ally and not enemy:
        return "debuff" if harmful else "buff"
    if harmful:
        return "debuff"
    return "unknown"


def lua_list(ids, indent="      "):
    lines, line = [], []
    for x in ids:
        line.append(str(x))
        if len(line) == 16:
            lines.append(indent + ", ".join(line) + ",")
            line = []
    if line:
        lines.append(indent + ", ".join(line) + ",")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db2")
    ap.add_argument("--install")
    ap.add_argument("--tacttool")
    ap.add_argument("--product", default="wow_classic_beta")
    ap.add_argument("--version", help="client version to record when --db2 is used")
    ap.add_argument("--out", default=os.path.join(HERE, "forever_files", "ForeverDispelData.lua"))
    args = ap.parse_args()
    version = args.version or "unknown"
    if args.install:
        if not args.tacttool:
            sys.exit("--install needs --tacttool")
        folder, version = extract(args.install, args.tacttool, args.product)
    elif args.db2:
        folder = args.db2
    else:
        sys.exit("give --db2 or --install + --tacttool")

    tables = {}
    for t in TABLES:
        tables[t] = wdc5.read(os.path.join(folder, t + ".db2"))
        if tables[t]["layout_hash"] != KNOWN_LAYOUTS[t]:
            sys.exit("%s.db2 has layout %08X, not %08X: check its columns in WoWDBDefs and update this script"
                     % (t, tables[t]["layout_hash"], KNOWN_LAYOUTS[t]))
    if args.install:
        shutil.rmtree(os.path.dirname(folder), ignore_errors=True)   # the temporary extraction
    cats, effs, names = tables["spellcategories"], tables["spelleffect"], tables["spellname"]

    dispel_of = {}
    for rid, v in cats["rows"].items():
        sid = cats["parents"].get(rid)
        if sid is not None and v[CAT_DIFFICULTY] == 0 and v[CAT_DISPEL] in DISPEL:
            dispel_of[sid] = DISPEL[v[CAT_DISPEL]]
    effects_of = collections.defaultdict(list)
    for rid, v in effs["rows"].items():
        sid = effs["parents"].get(rid)
        if sid is not None and v[EFF_DIFFICULTY] == 0:
            effects_of[sid].append(v)

    lists = {"HARMFUL": collections.defaultdict(list), "HELPFUL": collections.defaultdict(list)}
    counts = collections.defaultdict(collections.Counter)
    for sid, t in sorted(dispel_of.items()):
        c = classify(effects_of.get(sid, []))
        counts[t][c] += 1
        if c in ("debuff", "unknown"):
            lists["HARMFUL"][t].append(sid)
        if c in ("buff", "unknown"):
            lists["HELPFUL"][t].append(sid)

    out = ["-- ForeverDispelData.lua - WoW: Forever. GENERATED by tools/gen_dispel_data.py - do not edit.",
           "--",
           "-- Spell ids per dispel type from the client's own spell tables (client %s): SpellCategories.db2" % version,
           "-- DispelType, split into debuffs (HARMFUL) and buffs (HELPFUL) by what SpellEffect.db2 says their aura",
           "-- effects do. The engine hands the game aura SOUNDS for these ids when a display matches auras by their",
           "-- dispel type: the game plays aura sounds by spell id only, and learning ids in game misses every",
           "-- debuff that is gone before combat ends. Spells neither rule could place are in both lists.",
           "---@type string",
           "local AddonName = ...",
           "---@class Private",
           "local Private = select(2, ...)",
           "",
           "Private.ForeverDispelData = {",
           '  build = "%s",' % version]
    for kind in ("HARMFUL", "HELPFUL"):
        out.append("  %s = {" % kind)
        for t in ("Magic", "Curse", "Disease", "Poison", "Enrage"):
            ids = lists[kind].get(t, [])
            out.append("    %s = { -- %d" % (t, len(ids)))
            if ids:
                out.append(lua_list(ids))
            out.append("    },")
        out.append("  },")
    out.append("}")
    open(args.out, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("wrote %s (client %s)" % (args.out, version))
    for t in ("Magic", "Curse", "Disease", "Poison", "Enrage"):
        print("  %-8s debuffs %4d  buffs %4d  unknown %3d   -> HARMFUL %4d  HELPFUL %4d" % (
            t, counts[t]["debuff"], counts[t]["buff"], counts[t]["unknown"],
            len(lists["HARMFUL"].get(t, [])), len(lists["HELPFUL"].get(t, []))))


if __name__ == "__main__":
    main()
