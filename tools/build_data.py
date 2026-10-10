#!/usr/bin/env python3
"""Build the addon's model and item catalogue from a 1.12 world database.

Reads a MySQL dump of a 1.12.1 world database (tested with cmangos
classic-db, Full_DB/ClassicDB_1_12_1_*.sql.gz) and writes:

  Data/Creatures.lua  creature names and their display IDs (for .morph)
  Data/Items.lua      visible weapons and armour per inventory slot (for .item)

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


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "Data")
    os.makedirs(out_dir, exist_ok=True)
    sql = read_dump(sys.argv[1])
    creatures = build_creatures(sql)
    slots = build_items(sql)
    write_creatures(os.path.join(out_dir, "Creatures.lua"), creatures)
    write_items(os.path.join(out_dir, "Items.lua"), slots)
    print("%d creature models, %d slot items" % (len(creatures), sum(len(v) for v in slots.values())))


if __name__ == "__main__":
    main()
