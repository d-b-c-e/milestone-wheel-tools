r"""Add or update a wheel profile in a Milestone game's WheelConfig.ini.

Milestone's UE4 racers (Gravel, MXGP, MotoGP, Ride, Supercross) only accept
wheels listed in

    <game>\<game>\Config\WindowsNoEditor\WheelConfig.ini

keyed by a section name of <PID><VID> in lowercase hex - the Logitech G920
(VID_046D, PID_C262) is [/Wheel.Config/c262046d]. Anything not listed gets no
wheel option at all. The lists were frozen at release, so no direct-drive base
of any brand is in them.

This clones a shipped block (so every field the parser expects is present, in
order) and substitutes the device-specific values.

AXIS NUMBERING (derived from the shipped data, cross-checked on the G29, the
Fanatec ClubSport base and the ClubSport V3 pedals):

    Axis1=X  Axis2=Y  Axis3=Z  Axis4=Rx  Axis5=Ry  Axis6=Rz
    Axis7=Slider0  Axis8=Slider1

The trailing "&scale&offset" maps the axis's 0..1 travel onto the pedal:
released must give 0.0 and pressed 1.0. A pedal that idles LOW needs
"&1.0&0.0"; one that idles HIGH needs "&-1.0&1.0". Logitech and Fanatec
idle high, MOZA idles low - copying a Logitech block onto a MOZA leaves the
game convinced a pedal is permanently held. Measure with
Measure-WheelAxes.ps1 rather than guessing.

    python wheelconfig.py --ini <path> --product 0006346e --name "MOZA R12" \
        --steer Axis1 --throttle Axis3 --brake Axis6 --handbrake Axis7 \
        --set Wheel_LeftShoulder=Button13 --set Wheel_RightShoulder=Button14

The file is CRLF and the game rewrites it on exit: edit only while the game
is closed. Steam's "verify integrity" restores the stock file.
"""
import argparse
import io
import re
import shutil
import sys

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--ini", required=True, help="path to WheelConfig.ini")
ap.add_argument("--product", required=True, help="<PID><VID> hex, e.g. 0006346e (= DirectInput guidProduct.Data1)")
ap.add_argument("--name", required=True, help="ProductName shown in the game")
ap.add_argument("--template", default="c262046d", help="section to clone (default: Logitech G920)")
ap.add_argument("--polarity", default="low", choices=["low", "high"], help="pedals idle low (MOZA) or high (Logitech/Fanatec)")
ap.add_argument("--steer", default="Axis1")
ap.add_argument("--throttle", default="")
ap.add_argument("--brake", default="")
ap.add_argument("--clutch", default="")
ap.add_argument("--handbrake", default="")
ap.add_argument("--rotation", type=float, default=900.0)
ap.add_argument("--ffb", type=float, default=0.5)
ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE", help="any other field, e.g. Wheel_LeftTrigger=Button34")
ap.add_argument("--clear-buttons", action="store_true", help="empty every Button field inherited from the template")
a = ap.parse_args()

sec = a.product.lower()
s = io.open(a.ini, encoding="utf-8", errors="replace", newline="").read()
if "\r\n" not in s:
    sys.exit("expected a CRLF file - refusing to guess line endings")

m = re.search(rf"\[/Wheel\.Config/{a.template}\].*?(?=\r\n\[/Wheel\.Config/|\Z)", s, re.S)
if not m:
    sys.exit(f"template section {a.template} not found")
block = m.group(0)

existing = re.search(rf"(\[/Wheel\.Config/{sec}\].*?)(?=\r\n\[/Wheel\.Config/|\Z)", s, re.S)
if existing:
    block = existing.group(1)
    print(f"updating existing [{sec}]")
else:
    block = block.replace(f"[/Wheel.Config/{a.template}]", f"[/Wheel.Config/{sec}]", 1)
    print(f"cloning {a.template} -> [{sec}]")


def setf(b, key, val):
    # [^\r\n]* stops before the CR so the CRLF survives
    pat = rf"(?m)^{re.escape(key)}=[^\r\n]*"
    if not re.search(pat, b):
        sys.exit(f"field {key} is not in the template")
    return re.sub(pat, lambda _: f"{key}={val}", b, count=1)


pol = "1.0&0.0" if a.polarity == "low" else "-1.0&1.0"
block = setf(block, "ProductName", a.name)
block = setf(block, "Layout", "Generic")
block = setf(block, "ForceFeedback", f"{a.ffb:.6f}")
block = setf(block, "MaxRotationAngle", f"{a.rotation:.6f}")
block = setf(block, "Wheel_Steer", f"{a.steer}&1.0&0.0")
for key, axis in (("Wheel_Accelerator", a.throttle), ("Wheel_Brake", a.brake),
                  ("Wheel_Clutch", a.clutch), ("Wheel_Handbrake", a.handbrake)):
    block = setf(block, key, f"{axis}&{pol}" if axis else "")
if a.clear_buttons:
    block = re.sub(r"(?m)^(Wheel_\w+)=Button\d+", r"\1=", block)
for kv in a.set:
    k, _, v = kv.partition("=")
    block = setf(block, k.strip(), v.strip())

if existing:
    s = s[:existing.start(1)] + block + s[existing.end(1):]
else:
    shutil.copy2(a.ini, a.ini + ".bak")
    s = s.rstrip("\r\n") + "\r\n\r\n" + block.rstrip("\r\n") + "\r\n"
io.open(a.ini, "w", encoding="utf-8", newline="").write(s)

chk = io.open(a.ini, encoding="utf-8", errors="replace", newline="").read()
bare = chk.count("\n") - chk.count("\r\n")
print(f"written; sections={len(re.findall(r'\[/Wheel.Config/', chk))} bareLF={bare}")
for line in block.split("\r\n"):
    if "=" in line and line.split("=", 1)[1].strip():
        print("   ", line)
