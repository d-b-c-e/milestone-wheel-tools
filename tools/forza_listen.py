"""Listen for Forza "Data Out" packets and print the fields that matter.

Validates the mod end to end without SimHub in the loop: run it, launch the
game, move the wheel and pedals, and watch the columns change. Decodes all
three variants (sled 232 B, fm7 311 B, fh4 324 B) by packet length.

    python forza_listen.py            # port 5300
    python forza_listen.py 5300 --raw # dump every field of each packet
    python forza_listen.py 5301 --lines > capture.txt   # one line per sample
"""
import socket
import struct
import sys
import time

port = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 5300
raw = "--raw" in sys.argv
# a \r-refreshed line is right for a terminal; a file wants real lines
EOL = "\r" if sys.stdout.isatty() else "\n"

SLED = "<iIfff fff fff fff fff 4f4f4f 4i 4f4f4f4f4f iiiii"
DASH = "<fff fff 4f fff ffff H B BBBBB b bb"
SLED_N = struct.calcsize(SLED)   # 232
DASH_N = struct.calcsize(DASH)   # 79
assert SLED_N == 232 and DASH_N == 79

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", port))
s.settimeout(1.0)
print(f"listening on udp/{port}  (Ctrl-C to stop)\n")
print(f"{'fmt':<4} {'race':<4} {'rpm':>6}/{'max':<6} {'spd m/s':>7} {'gear':>4} {'steer':>6} "
      f"{'thr':>4} {'brk':>4} {'hb':>4} {'accX':>6} {'accZ':>6} {'rumble':>6} {'pps':>4}")

n = 0; last = time.time(); pps = 0
try:
    while True:
        try:
            data, _ = s.recvfrom(2048)
        except socket.timeout:
            continue
        n += 1
        now = time.time()
        if now - last >= 1.0:
            pps = n; n = 0; last = now
        L = len(data)
        fmt = {232: "sled", 311: "fm7", 324: "fh4"}.get(L, f"?{L}")
        sl = struct.unpack_from(SLED, data, 0)
        race, ts, maxrpm, idle, rpm = sl[:5]
        accX, accY, accZ = sl[5:8]
        rumble = sl[35 + 8]   # surfaceRumble[0]: after 3*4 vec + 12 scalars... computed below
        # index bookkeeping: 5 head + 12 (acc,vel,ang,ypr) = 17 -> normSusp[17:21] slip[21:25] rot[25:29]
        # onRumble[29:33] puddle[33:37] surface[37:41]
        rumble = sl[37]
        d = None
        if L == 311:
            d = struct.unpack_from(DASH, data, 232)
        elif L == 324:
            d = struct.unpack_from(DASH, data, 244)
        if d:
            # dash tuple: 0-2 pos, 3 speed, 4 power, 5 torque, 6-9 tyre temps, 10 boost,
            # 11 fuel, 12 dist, 13-16 laps/race time, 17 lap#, 18 position,
            # 19 accel, 20 brake, 21 clutch, 22 handbrake, 23 gear, 24 steer
            speed, gear = d[3], d[23]
            accel, brake, clutch, hb, steer = d[19], d[20], d[21], d[22], d[24]
        else:
            speed = gear = accel = brake = clutch = hb = steer = 0
        if n % 6 == 0 or raw:
            print(f"{fmt:<4} {race:<4} {rpm:6.0f}/{maxrpm:<6.0f} {speed:7.2f} {gear:>4} {steer:>6} "
                  f"{accel:>4} {brake:>4} {hb:>4} {accX:6.2f} {accZ:6.2f} {rumble:6.2f} {pps:>4}", end="\r")
        if raw:
            print()
            names = ("isRaceOn timestampMs maxRpm idleRpm rpm accX accY accZ velX velY velZ angX angY angZ "
                     "yaw pitch roll").split()
            for k, v in zip(names, sl[:17]):
                print(f"   {k:<12} {v}")
            if d:
                dn = "posX posY posZ speed power torque tt0 tt1 tt2 tt3 boost fuel dist best last cur race lap pos accel brake clutch hb gear steer line aibrk".split()
                for k, v in zip(dn, d):
                    print(f"   {k:<12} {v}")
except KeyboardInterrupt:
    print("\nstopped")
