r"""Print the action -> input bindings stored in a Milestone game's settings.sav.

The in-game rebind screen is not the only way in. The save is a UE4 GVAS
file whose `ignitioninput` block holds every binding as a record of

    ActionName (NameProperty)  KeyName (NameProperty)  ...

where KeyName is a keyboard key, a Gamepad_* key, or a Wheel_* logical slot.
Together with WheelConfig.ini (physical button -> Wheel_* slot) this gives
the full chain, so a control can be placed by editing the ini alone: find
which Wheel_* slot the action listens to, then put the button on that slot.

    python dump_bindings.py "%LOCALAPPDATA%\Gravel\Saved\SaveGames\settings.sav"
    python dump_bindings.py settings.sav --wheel      # only Wheel_* bindings
    python dump_bindings.py settings.sav --action Rewind
"""
import io
import re
import struct
import sys

if len(sys.argv) < 2:
    sys.exit(__doc__)
path = sys.argv[1]
only_wheel = "--wheel" in sys.argv
want = None
if "--action" in sys.argv:
    want = sys.argv[sys.argv.index("--action") + 1].lower()

b = open(path, "rb").read()
if b[:4] != b"GVAS":
    sys.exit("not a GVAS save")


def rd_str(o):
    n = struct.unpack_from("<i", b, o)[0]
    o += 4
    if n == 0:
        return "", o
    if n > 0:
        return b[o:o + n - 1].decode("latin-1", "replace"), o + n
    n = -n
    return b[o:o + (n - 1) * 2].decode("utf-16-le", "replace"), o + n * 2


def props(o, limit):
    """Yield (name, type, payload_offset, size) walking UE4 tagged properties."""
    while o < limit:
        try:
            name, p = rd_str(o)
        except Exception:
            return
        if not name or not name.isprintable():
            o += 1
            continue
        if name == "None":
            o = p
            continue
        try:
            typ, p2 = rd_str(p)
        except Exception:
            o += 1
            continue
        if not typ.endswith("Property"):
            o += 1
            continue
        size = struct.unpack_from("<q", b, p2)[0]
        p3 = p2 + 8 + 1  # size + guid flag
        yield name, typ, p3, size
        o = p3 + size


start = b.find(b"ignitioninput")
if start < 0:
    sys.exit("no ignitioninput block")

records, cur = [], None
for name, typ, off, size in props(start, len(b)):
    if name == "ActionName":
        if cur:
            records.append(cur)
        cur = {"action": rd_str(off)[0], "key": ""}
    elif name == "KeyName" and cur:
        cur["key"] = rd_str(off)[0]
if cur:
    records.append(cur)

by_key = {}
for r in records:
    if not r["key"]:
        continue
    if only_wheel and not r["key"].startswith("Wheel_"):
        continue
    if want and want not in r["action"].lower():
        continue
    by_key.setdefault(r["key"], []).append(r["action"])

print(f"{len(records)} binding records\n")
if want:
    for r in records:
        if want in r["action"].lower():
            print(f"  {r['action']:<28} <- {r['key']}")
else:
    for k in sorted(by_key):
        print(f"  {k:<28} {', '.join(by_key[k])}")
