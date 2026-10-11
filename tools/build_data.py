#!/usr/bin/env python3
"""Build the addon's model and item catalogue from a 1.12 world database.

Reads a MySQL dump of a 1.12.1 world database (tested with cmangos
classic-db, Full_DB/ClassicDB_1_12_1_*.sql.gz) and writes:

  Data/Creatures.lua    creature names and their display IDs (for .morph)
  Data/Items.lua        visible weapons and armour per inventory slot (for .item)
  Data/ClassicTags.lua  bosses, rare creatures and mounts, for the model filters
  tools/data/classic_item_displays.tsv  each item's display ID, for
                        tools/build_items.ps1's check against the game's files

Usage: python3 tools/build_data.py <dump.sql[.gz]> [output dir]
"""

import gzip
import os
import re
import sys

# InventoryType -> the DMorph inventory slots the item can be shown in.
ITEM_SLOTS = {
    1: [1],          # head
    3: [3],          # shoulders
    4: [4],          # shirt
    5: [5],          # chest
    20: [5],         # robe
    6: [6],          # waist
    7: [7],          # legs
    8: [8],          # feet
    9: [9],          # wrists
    10: [10],        # hands
    16: [15],        # back
    19: [19],        # tabard
    13: [16, 17],    # one-hand
    17: [16],        # two-hand
    21: [16],        # main hand
    14: [17],        # shield
    22: [17],        # off hand
    23: [17],        # held in off hand
    15: [18],        # bow
    25: [18],        # thrown
    26: [18],        # gun, crossbow, wand
}
SLOT_ORDER = [1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19]

# Developer-only creatures that are invisible or meaningless as a morph.
SKIP_CREATURE = re.compile(r"trigger|\[dnd\]|\(dnd\)|\bdnd\b|unused|\[ph\]|^zz|invisible", re.I)
SKIP_ITEM = re.compile(r"^deprecated|\[ph\]|^zz|^test |^qa ", re.I)


def read_dump(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as f:
        return f.read()


def table_columns(sql, table):
    match = re.search(r"CREATE TABLE `%s` \((.*?)\n\)" % table, sql, re.S)
    if not match:
        sys.exit("table %s not found" % table)
    return re.findall(r"^\s*`(\w+)`", match.group(1), re.M)


def parse_values(text, pos):
    """Parse '(a,b,...),(...);' starting at pos; yield tuples of str/None."""
    n = len(text)
    while pos < n:
        while text[pos] in " \n\r\t,":
            pos += 1
        if text[pos] == ";":
            return
        assert text[pos] == "(", text[pos:pos + 40]
        pos += 1
        row = []
        while True:
            c = text[pos]
            if c == "'":
                pos += 1
                out = []
                while True:
                    c = text[pos]
                    if c == "\\":
                        nxt = text[pos + 1]
                        out.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(nxt, nxt))
                        pos += 2
                    elif c == "'":
                        if text[pos + 1] == "'":
                            out.append("'")
                            pos += 2
                        else:
                            pos += 1
                            break
                    else:
                        out.append(c)
                        pos += 1
                row.append("".join(out))
            else:
                end = pos
                while text[end] not in ",)":
                    end += 1
                value = text[pos:end].strip()
                row.append(None if value == "NULL" else value)
                pos = end
            if text[pos] == ",":
                pos += 1
            elif text[pos] == ")":
                pos += 1
                break
        yield row


def table_rows(sql, table):
    columns = table_columns(sql, table)
    for match in re.finditer(r"INSERT INTO `%s` (?:\([^)]*\) )?VALUES" % table, sql):
        for row in parse_values(sql, match.end()):
            yield dict(zip(columns, row))


def clean(name):
    name = " ".join(name.split())
    if "[[" in name or "]]" in name or "\t" in name:
        sys.exit("name can't be stored in a Lua long string: %r" % name)
    return name


def build_creatures(sql):
    seen = set()
    entries = []
    for row in table_rows(sql, "creature_template"):
        name = clean(row["Name"] or "")
        if not name or SKIP_CREATURE.search(name):
            continue
        for key in ("ModelId1", "ModelId2", "ModelId3", "ModelId4"):
            display = int(row[key] or 0)
            if display and (name, display) not in seen:
                seen.add((name, display))
                entries.append((name.lower(), display, name))
    entries.sort()
    return [(display, name) for _, display, name in entries]


def build_items(sql):
    slots = {slot: [] for slot in SLOT_ORDER}
    for row in table_rows(sql, "item_template"):
        if row["class"] not in ("2", "4"):
            continue
        name = clean(row["name"] or "")
        if not name or SKIP_ITEM.search(name):
            continue
        for slot in ITEM_SLOTS.get(int(row["InventoryType"]), []):
            slots[slot].append((name.lower(), int(row["entry"]), int(row["Quality"]), name))
    for slot in slots:
        slots[slot].sort()
    return slots


# Dungeon bosses are mostly plain elites in the database. What sets them apart:
# this mechanic immunity (bit 24) or a big health multiplier, and being spawned
# once or twice (or only by a script).
BOSS_IMMUNITY = 0x800000


def build_tags(sql):
    """Rows of (displayID, tag, name): boss and rare for that display and
    creature name, mount for the display."""
    creatures = {row["Entry"]: row for row in table_rows(sql, "creature_template")}
    instances = {row["map"] for row in table_rows(sql, "instance_template")}
    spawns = {}
    for row in table_rows(sql, "creature"):
        spawns.setdefault(row["id"], []).append(row["map"])

    def tag_of(entry, row):
        rank = int(row["Rank"] or 0)
        script = row.get("ScriptName") or ""
        if rank == 3 or script.startswith("boss_"):
            return "boss"
        if rank >= 1:
            health = float(row.get("HealthMultiplier") or 1)
            immune = int(row.get("MechanicImmuneMask") or 0)
            maps = spawns.get(entry, [])
            in_instance = bool(maps) and all(m in instances for m in maps)
            if len(maps) <= 2 and health >= 4 and (immune & BOSS_IMMUNITY or (in_instance and health >= 5)):
                return "boss"
        if rank in (2, 4):
            return "rare"
        return None

    def displays(row):
        for key in ("ModelId1", "ModelId2", "ModelId3", "ModelId4"):
            display = int(row[key] or 0)
            if display:
                yield display

    rows = set()
    for entry, row in creatures.items():
        name = clean(row["Name"] or "")
        if not name or SKIP_CREATURE.search(name):
            continue
        tag = tag_of(entry, row)
        if tag:
            for display in displays(row):
                rows.add((display, tag, name))

    # Mounts: what every mount spell (aura 78, its value the creature you
    # ride) puts you on, and what NPCs ride.
    mounts = set()
    for spell in table_rows(sql, "spell_template"):
        for i in (1, 2, 3):
            if spell.get("Effect%d" % i) == "6" and spell.get("EffectApplyAuraName%d" % i) == "78":
                row = creatures.get(spell.get("EffectMiscValue%d" % i))
                if row:
                    mounts.update(displays(row))
    for row in table_rows(sql, "creature_template_addon"):
        if row.get("mount") and row["mount"] != "0":
            mounts.add(int(row["mount"]))
    rows.update((display, "mount", "") for display in mounts)
    return sorted(rows)


def build_item_displays(sql):
    displays = []
    for row in table_rows(sql, "item_template"):
        if row["class"] in ("2", "4") and int(row["InventoryType"]) in ITEM_SLOTS:
            displays.append((int(row["entry"]), int(row["displayid"] or 0)))
    return sorted(displays)


HEADER = "-- Generated by tools/build_data.py from a 1.12.1 world database. Do not edit.\n"


def write_creatures(path, creatures):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER)
        f.write("-- One creature per line: displayID<TAB>name, sorted by name.\n")
        f.write("DmorphOcto_CreatureData = [[\n")
        for display, name in creatures:
            f.write("%d\t%s\n" % (display, name))
        f.write("]]\n")


def write_items(path, slots):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER)
        f.write("-- Per inventory slot, one item per line: itemID<TAB>quality<TAB>name, sorted by name.\n")
        f.write("DmorphOcto_ItemData = {}\n")
        for slot in SLOT_ORDER:
            f.write("DmorphOcto_ItemData[%d] = [[\n" % slot)
            for _, entry, quality, name in slots[slot]:
                f.write("%d\t%d\t%s\n" % (entry, quality, name))
            f.write("]]\n")


def write_tags(path, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER)
        f.write("-- Model filter tags, like Data/ModelTags.lua: displayID<TAB>tag<TAB>name. boss and rare apply\n")
        f.write("-- to the catalogue entry with that display and creature name, mount to the display.\n")
        f.write("DmorphOcto_ClassicTagData = [[\n")
        for display, tag, name in rows:
            f.write("%d\t%s\t%s\n" % (display, tag, name))
        f.write("]]\n")


def write_item_displays(path, displays):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Generated by tools/build_data.py from a 1.12.1 world database: itemID<TAB>displayID for the\n")
        f.write("# weapons and armour in Data/Items.lua, for tools/build_items.ps1's check against the game files.\n")
        for entry, display in displays:
            f.write("%d\t%d\n" % (entry, display))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "Data")
    os.makedirs(out_dir, exist_ok=True)
    sql = read_dump(sys.argv[1])
    creatures = build_creatures(sql)
    slots = build_items(sql)
    tags = build_tags(sql)
    write_creatures(os.path.join(out_dir, "Creatures.lua"), creatures)
    write_items(os.path.join(out_dir, "Items.lua"), slots)
    write_tags(os.path.join(out_dir, "ClassicTags.lua"), tags)
    tools_data = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
    write_item_displays(os.path.join(tools_data, "classic_item_displays.tsv"), build_item_displays(sql))
    counts = {}
    for _, tag, _ in tags:
        counts[tag] = counts.get(tag, 0) + 1
    print("%d creature models, %d slot items, tags: %s" % (len(creatures), sum(len(v) for v in slots.values()),
                                                           ", ".join("%d %s" % (counts[t], t) for t in sorted(counts))))


if __name__ == "__main__":
    main()
