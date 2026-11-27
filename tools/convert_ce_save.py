#!/usr/bin/env python3
"""
convert_ce_save.py - Convert GTA IV Steam Complete Edition (v1.2.0.x) saves to
the v1.0.8.0 layout that macIV's recompiled engine reads.

Why: macIV runs the v1.0.8.0 game code. Before loading, that code computes the
exact size of every save block and rejects the save ("load failed") if any
block differs. Complete Edition saves differ from v1.0.8.0 in three blocks:

  * Radar (block 9):  each of the 150 blip records stores its name as 60 bytes
                      of UTF-16. v1.0.8.0 (non-Japanese) stores 30 bytes of
                      ASCII. -> names converted (they are plain ASCII, e.g.
                      "BLIP_27", so nothing is lost).
  * Stats (block 13): the block starts with per-radio-station listening times;
                      the Complete Edition has 26 stations, v1.0.8.0 has 20.
                      -> the 6 extra timers are dropped (only feeds the
                      "favourite radio station" statistic).
  * Radio (block 16): the radio playback state blob is 3694 bytes vs 3262.
                      -> trimmed to 3262 bytes. macIV's engine is built to
                      skip the saved radio state, so stations simply start
                      fresh after loading.

Everything else (story/mission progress, scripts, stats, garages, weapons...)
is copied byte for byte. The original file is kept as <name>.ce.bak (in a sibling "ce_saves_backup" folder when
converting inside a user_* profile folder, since the game lists every SGTA4* file there).

Usage:
  python3 convert_ce_save.py [save files or folders...]
With no arguments it converts the saves in macIV's save folder.
"""

import argparse
import glob
import os
import shutil
import struct
import sys
import zlib

DEFAULT_SAVE_DIR = os.path.expanduser(
    "~/Library/Application Support/gtaiv/drive_c/Documents and Settings/Player/"
    "Local Settings/Application Data/Rockstar Games/GTA IV/savegames/user_ee000000deadc0de"
)

HEADER_LEN = 16 + 256          # version, size, globals, "SAVE", UTF-16 title
BLOCK_HDR = 9                  # "BLOCK" + uint32 size (size includes these 9 bytes)
NUM_BLOCKS = 32
FOOTER = b"\xCD\xCD\xCD\xCDimag"  # after the 4-byte CRC

RADAR, STATS, RADIO = 9, 13, 16
RADAR_SLOTS = 150
RADAR_HDR = 16
CE_BLIP, OLD_BLIP = 130, 100
BLIP_NAME_OFF, CE_NAME_LEN, OLD_NAME_LEN = 31, 60, 30
CE_STATIONS, OLD_STATIONS = 26, 20
CE_RADIO, OLD_RADIO = 3694, 3262


def parse(data):
    if len(data) < HEADER_LEN or data[12:16] != b"SAVE":
        raise ValueError("not a GTA IV save (no SAVE tag)")
    off = HEADER_LEN
    blocks = []
    for _ in range(NUM_BLOCKS):
        if data[off:off + 5] != b"BLOCK":
            raise ValueError(f"expected BLOCK at offset {off}")
        size = struct.unpack_from("<I", data, off + 5)[0]
        blocks.append(bytearray(data[off + BLOCK_HDR:off + size]))
        off += size
    end = data.find(b"END\x00", off)
    if end < 0:
        raise ValueError("missing END terminator")
    trailer = data[off:end + 4]  # 4-byte value + "END\0"
    return bytearray(data[:HEADER_LEN]), blocks, trailer


def convert_radar(p):
    if len(p) == RADAR_HDR + RADAR_SLOTS * OLD_BLIP:
        return p, False
    if len(p) != RADAR_HDR + RADAR_SLOTS * CE_BLIP:
        raise ValueError(f"unexpected Radar size {len(p)}")
    out = bytearray(p[:RADAR_HDR])
    for i in range(RADAR_SLOTS):
        r = p[RADAR_HDR + i * CE_BLIP:RADAR_HDR + (i + 1) * CE_BLIP]
        wide = r[BLIP_NAME_OFF:BLIP_NAME_OFF + CE_NAME_LEN]
        name = bytearray()
        for j in range(OLD_NAME_LEN):
            lo, hi = wide[2 * j], wide[2 * j + 1]
            name.append(lo if hi == 0 and lo < 0x80 else (0 if (lo, hi) == (0, 0) else ord("?")))
        # keep the string terminated like the engine does when it reads it
        if 0 not in name:
            name[-1] = 0
        out += r[:BLIP_NAME_OFF] + name + r[BLIP_NAME_OFF + CE_NAME_LEN:]
    return out, True


def convert_stats(p):
    extra = (CE_STATIONS - OLD_STATIONS) * 4
    if len(p) - extra < 0:
        return p, False
    # Complete Edition: 26 station timers first; v1.0.8.0: 20.
    # Only convert when the rest matches the known v1.0.8.0 stats layout size.
    if len(p) == 5944:
        return p[:OLD_STATIONS * 4] + p[CE_STATIONS * 4:], True
    return p, False


def convert_radio(p):
    if len(p) == CE_RADIO:
        return p[:OLD_RADIO], True
    return p, False


def build(header, blocks, trailer):
    body = bytearray(header)
    for b in blocks:
        body += b"BLOCK" + struct.pack("<I", len(b) + BLOCK_HDR) + b
    body += trailer
    total = len(body) + 4 + len(FOOTER)
    struct.pack_into("<I", body, 4, total)
    crc = zlib.crc32(bytes(body[16:])) & 0xFFFFFFFF
    return bytes(body) + struct.pack("<I", crc) + FOOTER


def convert_file(path, dry_run=False):
    with open(path, "rb") as f:
        data = f.read()
    header, blocks, trailer = parse(data)
    title = header[16:272].decode("utf-16le", "replace").split("\x00")[0]
    changes = []
    blocks[RADAR], c = convert_radar(blocks[RADAR]);  c and changes.append("radar names")
    blocks[STATS], c = convert_stats(blocks[STATS]);  c and changes.append("stats radio timers")
    blocks[RADIO], c = convert_radio(blocks[RADIO]);  c and changes.append("radio state")
    name = os.path.basename(path)
    if not changes:
        print(f"[=] {name}: '{title}' already in v1.0.8.0 layout")
        return False
    out = build(header, blocks, trailer)
    print(f"[+] {name}: '{title}' converted ({', '.join(changes)}): {len(data)} -> {len(out)} bytes")
    if dry_run:
        return True
    # The game lists every SGTA4* file in the profile folder, backups included,
    # so keep backups out of it (in a sibling folder) when converting there.
    folder = os.path.dirname(os.path.abspath(path))
    if os.path.basename(folder).lower().startswith("user_"):
        bak_dir = os.path.join(os.path.dirname(folder), "ce_saves_backup")
        os.makedirs(bak_dir, exist_ok=True)
        bak = os.path.join(bak_dir, name + ".ce.bak")
    else:
        bak = path + ".ce.bak"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
    with open(path, "wb") as f:
        f.write(out)
    return True


def main():
    ap = argparse.ArgumentParser(description="Convert GTA IV Complete Edition saves for macIV (v1.0.8.0 layout).")
    ap.add_argument("paths", nargs="*", help="save files (SGTA4xx) or folders; default: macIV's save folder")
    ap.add_argument("-n", "--dry-run", action="store_true", help="only report what would change")
    args = ap.parse_args()
    files = []
    for p in (args.paths or [DEFAULT_SAVE_DIR]):
        p = os.path.expanduser(p)
        if os.path.isdir(p):
            files += sorted(f for f in glob.glob(os.path.join(p, "SGTA4*")) if len(os.path.basename(f)) == 7)
        elif os.path.isfile(p):
            files.append(p)
    if not files:
        print("[-] no save files found")
        return 1
    rc = 0
    for f in files:
        try:
            convert_file(f, args.dry_run)
        except ValueError as e:
            print(f"[-] {os.path.basename(f)}: {e}")
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
