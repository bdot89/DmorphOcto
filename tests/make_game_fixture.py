"""Builds a fake OctoWoW folder (Data/*.MPQ with DBCs, models, textures) to test
tools/build_models.ps1 and tools/build_items.ps1. MPQ v1, files stored plain;
hash and block tables encrypted like Blizzard's, so tools/MpqDbc.cs reads them.

Usage: python3 tests/make_game_fixture.py <out dir> [--mostly-empty] [--no-rider-points]
Then run tools/build_models.ps1, tools/build_items.ps1 and tools/build_options.ps1 with
-GameDir <out dir>, their inputs from <out dir> (Creatures.lua, Items.lua,
item_displays.tsv, turtle_items.tsv, empty.tsv) and every output path pointed outside
Data/ (PowerShell 7 works on Linux).
Expected: HiddenModels "2029,4528,9999,11121", HiddenItems "2,3,11", ModelTags
mounts 90001-90005 (named Riding...), 90010-90011 (Spectral Tiger, by its rider
point) and 90012 (a shop mount, by its mount spell's name), not 90013 (a wolf named
like a mount spell, no rider point); with --mostly-empty the model check turns itself
off, with --no-rider-points the rider point rule does (90001-90005 and 90012 are mounts).
Glows: visuals 25 (enchant 1900, "Crusader; Holy Power"), 26 (803), 28 (20) and 29
(30, no name), not 27 (its effect model is missing). CharOptions: "1:0" skins 0-3
(3 NPC-only; 4 is left out, its texture is missing), faces [0]={0,1} [1]..[3]={0},
hair styles 0-2, hair colours [0]={0,1} [1]={0}, facial hair 0-2; "1:1", "2:0" and "2:1" (hair
styles 0-3 with colours 0-9, all sharing one texture) too; "2:0" hair style 1 has colour 0
(its texture is named with "/").
"""
import os
import struct
import sys
import zlib


def crypt_table():
    seed = 0x00100001
    table = [0] * 0x500
    for i1 in range(0x100):
        i2 = i1
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            t1 = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            t2 = seed & 0xFFFF
            table[i2] = t1 | t2
            i2 += 0x100
    return table


CT = crypt_table()
M32 = 0xFFFFFFFF


def hs(s, ht):
    s1, s2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper():
        c = ord(ch)
        s1 = (CT[(ht << 8) + c] ^ ((s1 + s2) & M32)) & M32
        s2 = (c + s1 + s2 + ((s2 << 5) & M32) + 3) & M32
    return s1


def encrypt(data, key):
    out = bytearray(data)
    s2 = 0xEEEEEEEE
    for i in range(len(data) // 4):
        s2 = (s2 + CT[0x400 + (key & 0xFF)]) & M32
        v = struct.unpack_from("<I", data, i * 4)[0]
        e = v ^ ((key + s2) & M32)
        key = ((((~key) << 0x15) & M32) + 0x11111111 & M32) | (key >> 0x0B)
        s2 = (v + s2 + ((s2 << 5) & M32) + 3) & M32
        struct.pack_into("<I", out, i * 4, e)
    return bytes(out)


def write_mpq(path, files, compress=()):
    """files: {name: bytes}. Names in `compress` are stored zlib-compressed in
    4096-byte sectors (to test ReadStart on compressed files)."""
    names = list(files)
    size = 1
    while size < len(names) * 2 + 4:
        size *= 2
    header = 32
    data = bytearray()
    blocks = []
    for name in names:
        content = files[name]
        pos = header + len(data)
        if name in compress:
            sectors = [content[i:i + 4096] for i in range(0, len(content), 4096)] or [b""]
            packed = []
            for sct in sectors:
                z = b"\x02" + zlib.compress(sct)
                packed.append(z if len(z) < len(sct) else sct)
            table_len = (len(packed) + 1) * 4
            offsets = [table_len]
            for p in packed:
                offsets.append(offsets[-1] + len(p))
            body = struct.pack("<%dI" % len(offsets), *offsets) + b"".join(packed)
            data += body
            blocks.append((pos, len(body), len(content), 0x80000000 | 0x00000200))
        else:
            data += content
            blocks.append((pos, len(content), len(content), 0x80000000))
    hash_entries = [(M32, M32, M32, M32)] * size
    hash_entries = list(hash_entries)
    for index, name in enumerate(names):
        i = hs(name, 0) % size
        while hash_entries[i][3] != M32:
            i = (i + 1) % size
        hash_entries[i] = (hs(name, 1), hs(name, 2), 0, index)
    ht = b"".join(struct.pack("<IIII", *e) for e in hash_entries)
    bt = b"".join(struct.pack("<IIII", *b) for b in blocks)
    hto = header + len(data)
    bto = hto + len(ht)
    archive = len(data) + len(ht) + len(bt) + header
    head = struct.pack("<4sIIHHIIII", b"MPQ\x1a", header, archive, 0, 3, hto, bto, size, len(blocks))
    with open(path, "wb") as f:
        f.write(head + data + encrypt(ht, hs("(hash table)", 3)) + encrypt(bt, hs("(block table)", 3)))


def dbc(rows, fields):
    """rows: lists of ints or str (strings go into the string block)."""
    strings = bytearray(b"\0")
    offsets = {}

    def ref(s):
        if s == "":
            return 0
        if s not in offsets:
            offsets[s] = len(strings)
            strings.extend(s.encode() + b"\0")
        return offsets[s]

    body = bytearray()
    for row in rows:
        row = list(row) + [0] * (fields - len(row))
        for v in row:
            body += struct.pack("<i", ref(v) if isinstance(v, str) else v)
    return struct.pack("<4sIIII", b"WDBC", len(rows), fields, fields * 4, len(strings)) + bytes(body) + bytes(strings)


def m2(version=256, vertices=10, views=1, pad=6000, rider=None):
    """rider: None = no attachments, True / False = attachment 0 present or
    not (the lookup table goes after the padding, past the first sector)."""
    head = bytearray(0x140)
    head[0:4] = b"MD20"
    struct.pack_into("<I", head, 4, version)
    struct.pack_into("<II", head, 0x44, vertices, 0x140)
    struct.pack_into("<II", head, 0x4C, views, 0x140)
    body = bytes(head) + b"\x11" * pad
    if rider is not None:
        struct.pack_into("<II", head, 0x10C, 3, len(body))
        body = bytes(head) + b"\x11" * pad + struct.pack("<hhh", 0 if rider else -1, 1, 2)
    return body


def main():
    out = sys.argv[1]
    mostly_empty = "--mostly-empty" in sys.argv
    no_rider = "--no-rider-points" in sys.argv
    data = os.path.join(out, "Data")
    os.makedirs(data, exist_ok=True)

    base, patch = {}, {}
    # Models: 1 good, 2 empty, 3 missing, 4 WC3 format, 5 human male, 10-39 good.
    model_rows = [
        (1, 0, "Creature\\Good\\Good.mdx"), (2, 0, "Creature\\Empty\\Empty.mdx"),
        (3, 0, "Creature\\Missing\\Missing.mdx"), (4, 0, "Creature\\Old\\Old.mdx"),
        (5, 0, "Character\\Human\\Male\\HumanMale.mdx"),
    ]
    base["Creature\\Good\\Good.m2"] = m2()
    base["Creature\\Good\\GoodSkin.blp"] = b"BLP2"
    base["Creature\\Empty\\Empty.m2"] = m2(vertices=0)
    base["Creature\\Old\\Old.m2"] = b"MDLX" + b"\0" * 200
    base["Character\\Human\\Male\\HumanMale.m2"] = m2()
    for k in range(10, 40):
        model_rows.append((k, 0, "Creature\\Beast%d\\Beast%d.mdx" % (k, k)))
        empty = mostly_empty and k < 30
        base["Creature\\Beast%d\\Beast%d.m2" % (k, k)] = m2(vertices=0 if empty else 50, rider=False if k < 20 else None)
        base["Creature\\Beast%d\\Beast%dSkin.blp" % (k, k)] = b"BLP2"
    # Mounts: five named "Riding..." (known), a Spectral Tiger (only its rider
    # point says so; its lookup table is past the first, compressed, sector).
    for k in range(1, 6):
        model_rows.append((50 + k, 0, "Creature\\RidingBeast%d\\RidingBeast%d.mdx" % (k, k)))
        base["Creature\\RidingBeast%d\\RidingBeast%d.m2" % (k, k)] = m2(rider=None if no_rider else True)
    model_rows.append((60, 0, "Creature\\SpectralTiger\\SpectralTiger.mdx"))
    base["Creature\\SpectralTiger\\SpectralTiger.m2"] = m2(rider=True, pad=9000)
    # A shop mount only its mount spell names, and a wild wolf that shares a
    # mount spell's name but has no rider point.
    model_rows.append((61, 0, "Creature\\ShopCat\\ShopCat.mdx"))
    base["Creature\\ShopCat\\ShopCat.m2"] = m2(rider=True)
    model_rows.append((62, 0, "Creature\\Wolf\\Wolf.mdx"))
    base["Creature\\Wolf\\Wolf.m2"] = m2(rider=False)

    # Displays: 0 ID, 1 model, 3 extra, 6-8 skins.
    display_rows = [
        [4527, 1, 0, 0, 0, 0, "GoodSkin"],    # Thrall: fine
        [11121, 2],                            # Ragnaros: empty model
        [2029, 3],                             # VanCleef: no model file
        [4528, 4],                             # not an M2
        [60000, 1, 0, 0, 0, 0, "NoSuchSkin"],  # unnamed, skin missing
        [49, 5],                               # human male, fine
        [18088, 5, 0, 1],                      # a dressed human (extra 1)
    ]
    for k in range(10, 40):
        display_rows.append([70000 + k, k, 0, 0, 0, 0, "Beast%dSkin" % k])
    for k in range(10, 16):
        display_rows.append([80000 + k, k, 0, 0, 0, 0, "Beast%dSkin" % k])
    for k in range(1, 6):
        display_rows.append([90000 + k, 50 + k])
    display_rows += [[90010, 60], [90011, 60], [90012, 61], [90013, 62]]
    extra = [[1, 1, 1, 3, 2, 4, 5, 0] + [0] * 10 + [0, ""]]
    patch["DBFilesClient\\CreatureModelData.dbc"] = dbc(model_rows, 16)
    patch["DBFilesClient\\CreatureDisplayInfo.dbc"] = dbc(display_rows, 11)
    patch["DBFilesClient\\CreatureDisplayInfoExtra.dbc"] = dbc(extra, 20)

    # Items: 100 sword with model, 101 sword without, 102 chest texture, 103
    # helm (race files), 104 icon only. ItemDisplayInfo: ID, 2 models, 2 model
    # textures, 2 icons, ..., 8 textures.
    idi = [
        [100, "Sword_1H_Good.mdx", "", "", "", "INV_Sword_01"],
        [101, "Sword_1H_Gone.mdx", "", "", "", "INV_Sword_02"],
        [102, "", "", "", "", "INV_Chest_Plate01", "", 0, 0, 0, 0, 0, 0, 0, 0, "Plate_Chest_A"],
        [103, "Helm_Plate_A.mdx", "", "Helm_Plate_A", "", "INV_Helmet_01"],
        [104, "", "", "", "", "INV_Chest_Cloth_01"],
    ]
    patch["DBFilesClient\\ItemDisplayInfo.dbc"] = dbc(idi, 24)
    patch["DBFilesClient\\ItemSet.dbc"] = dbc([[1, "Test Set", 0, 0, 0, 0, 0, 0, 0, 0, 1, 2]], 27)
    base["Item\\ObjectComponents\\Weapon\\Sword_1H_Good.m2"] = m2()
    base["Item\\TextureComponents\\TorsoUpperTexture\\Plate_Chest_A_U.blp"] = b"BLP2"
    base["Item\\ObjectComponents\\Head\\Helm_Plate_A_OrM.m2"] = m2()

    # Spell.dbc (1.12.1): 0 ID, 91-93 auras, 106-108 misc values, 120 name.
    # The 1.12 mount spells the tool checks the layout on, and a shop mount.
    def spell(sid, name, aura):
        row = [0] * 173
        row[0], row[91], row[120] = sid, aura, name
        return row
    mounts = [(458, "Brown Horse"), (470, "Black Stallion"), (472, "Pinto"), (580, "Timber Wolf"),
              (6648, "Chestnut Mare"), (6653, "Dire Wolf"), (6654, "Brown Wolf"), (6777, "Gray Ram"),
              (6898, "White Ram"), (6899, "Brown Ram"), (8394, "Striped Frostsaber"), (90000, "Crimson Spectral Tiger")]
    patch["DBFilesClient\\Spell.dbc"] = dbc([spell(i, n, 78) for i, n in mounts] + [spell(133, "Fireball", 3)], 173)

    # Glows. SpellItemEnchantment (1.12.1): 0 ID, 1-12 effects, 13-20 name, 21
    # locale mask, 22 ItemVisual, 23 flags.
    def enchant(eid, name, visual, flags=0):
        return [eid, 1, 0, 0, 5, 0, 0, 5, 0, 0, 7, 0, 0, name] + [""] * 7 + [0x00FF01FE, visual, flags]
    patch["DBFilesClient\\SpellItemEnchantment.dbc"] = dbc([
        enchant(1900, "Crusader", 25), enchant(1901, "Holy Power", 25), enchant(803, "Fiery Weapon", 26, 1),
        enchant(900, "Ghost Glow", 27), enchant(10, "+1 Agility", 0), enchant(20, "Frost", 28), enchant(30, "", 29),
        enchant(40, "Broken Glow", 999),  # a visual the client doesn't have: skipped, not a reason to give up
    ] + [enchant(100 + k, "+%d Stamina" % k, 0) for k in range(20)], 24)
    patch["DBFilesClient\\ItemVisuals.dbc"] = dbc([[25, 1], [26, 2, 3], [27, 3], [28, 4], [29, 1]], 6)
    patch["DBFilesClient\\ItemVisualEffects.dbc"] = dbc([
        [1, "Spells\\Enchantments\\HolyGlow.mdx"], [2, "Spells\\Enchantments\\FireGlow.mdx"],
        [3, "Spells\\Enchantments\\Gone.mdx"], [4, "Spells\\Enchantments\\FrostGlow.mdx"],
    ], 2)
    for name in ("HolyGlow", "FireGlow", "FrostGlow"):
        base["Spells\\Enchantments\\%s.m2" % name] = m2()

    # Character options. CharSections (1.12.1): 0 ID, 1 race, 2 gender, 3
    # section, 4 variation, 5 colour, 6-8 textures, 9 flags (1 = offered at
    # character creation).
    sections = []

    def section(race, gender, kind, variation, colour, flags=1, texture=True):
        tex = ""
        if texture:
            tex = "Character\\R%d\\G%d\\S%d_%02d_%02d.blp" % (race, gender, kind, variation, colour)
            if texture != "missing":
                base[tex] = b"BLP2"
        sections.append([len(sections) + 1, race, gender, kind, variation, colour, tex, "", "", flags])
    for c in range(3):
        section(1, 0, 0, 0, c)
    section(1, 0, 0, 0, 3, flags=0)
    section(1, 0, 0, 0, 4, texture="missing")
    section(1, 0, 1, 0, 0)
    section(1, 0, 1, 1, 0)
    for c in range(1, 4):
        section(1, 0, 1, 0, c)
    section(1, 0, 3, 0, 0)
    section(1, 0, 3, 0, 1)
    section(1, 0, 3, 1, 0)
    section(1, 0, 3, 2, 0, texture=False)
    section(1, 0, 2, 1, 0)
    section(1, 0, 4, 0, 0)
    section(1, 1, 0, 0, 0)
    section(1, 1, 1, 0, 0)
    section(1, 1, 3, 0, 0)
    section(2, 0, 0, 0, 0)
    section(2, 0, 0, 0, 1)
    section(2, 0, 1, 0, 0)
    section(2, 0, 1, 0, 1)
    section(2, 0, 3, 0, 0)
    # A texture named with forward slashes, which the game reads like "\\".
    sections.append([len(sections) + 1, 2, 0, 3, 1, 0, "Character/Orc/Hair01.blp", "", "", 1])
    base["Character\\Orc\\Hair01.blp"] = b"BLP2"
    # Orc women share one hair texture for every style and colour, as hair
    # often does: few different texture names in the table.
    section(2, 1, 0, 0, 0)
    section(2, 1, 1, 0, 0)
    for style in range(4):
        for colour in range(10):
            sections.append([len(sections) + 1, 2, 1, 3, style, colour, "Character\\Shared\\Hair.blp", "", "", 1])
    base["Character\\Shared\\Hair.blp"] = b"BLP2"
    patch["DBFilesClient\\CharSections.dbc"] = dbc(sections, 10)
    hair = [(1, 0, 0), (1, 0, 1), (1, 0, 2), (1, 1, 0), (2, 0, 0), (2, 0, 1)]
    patch["DBFilesClient\\CharHairGeosets.dbc"] = dbc([[i + 1, r, g, v, v, 0] for i, (r, g, v) in enumerate(hair)], 6)
    facial = [(1, 0, 0), (1, 0, 1), (1, 0, 2), (1, 1, 0), (2, 0, 0)]
    patch["DBFilesClient\\CharacterFacialHairStyles.dbc"] = dbc([[r, g, v, v, 0, 0, 0, 0, 0] for r, g, v in facial], 9)

    write_mpq(os.path.join(data, "model.MPQ"), base, compress={"Creature\\Empty\\Empty.m2", "Creature\\Good\\Good.m2",
                                                                 "Creature\\SpectralTiger\\SpectralTiger.m2"})
    write_mpq(os.path.join(data, "patch.MPQ"), patch, compress={"DBFilesClient\\CreatureDisplayInfo.dbc"})

    # Inputs that normally come from the repository.
    named = [(4527, "Thrall"), (11121, "Ragnaros"), (2029, "Edwin VanCleef"), (4528, "Old Thing"), (9999, "Not In Client"),
             (90012, "Crimson Spectral Tiger"), (90013, "Timber Wolf")]
    named += [(70000 + k, "Beast %d" % k) for k in range(10, 40)]
    with open(os.path.join(out, "Creatures.lua"), "w") as f:
        f.write("DmorphOcto_CreatureData = [[\n")
        for i, n in sorted(named, key=lambda x: x[1].lower()):
            f.write("%d\t%s\n" % (i, n))
        f.write("]]\n")
    with open(os.path.join(out, "Items.lua"), "w") as f:
        f.write("DmorphOcto_ItemData = {}\nDmorphOcto_ItemData[1] = [[\n20\t4\tHelm\n]]\n")
        f.write("DmorphOcto_ItemData[5] = [[\n10\t4\tGood Chest\n11\t1\tNothing Chest\n")
        for k in range(30, 40):
            f.write("%d\t2\tChest %d\n" % (k, k))
        f.write("]]\nDmorphOcto_ItemData[16] = [[\n1\t3\tGood Sword\n2\t3\tGone Sword\n3\t3\tUnknown Display\n")
        for k in range(40, 52):
            f.write("%d\t2\tSword %d\n" % (k, k))
        f.write("]]\n")
    with open(os.path.join(out, "item_displays.tsv"), "w") as f:
        rows = [(1, 100), (2, 101), (3, 999), (10, 102), (11, 104), (20, 103)]
        rows += [(k, 102) for k in range(30, 40)] + [(k, 100) for k in range(40, 52)]
        for i, d in rows:
            f.write("%d\t%d\n" % (i, d))
    with open(os.path.join(out, "turtle_items.tsv"), "w") as f:
        f.write("# test\n5000\t13\t3\tTurtle Sword\n")
    with open(os.path.join(out, "empty.tsv"), "w") as f:
        f.write("# empty\n")


main()
