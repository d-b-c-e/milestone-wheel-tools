# milestone-telemetry

Wheel support and live telemetry for Milestone's UE4 racing games — Gravel
first, with MXGP / MotoGP / Ride / Supercross sharing the same engine and the
same problems.

One `dinput8.dll` dropped beside the game's executable does three things:

1. **Makes a direct-drive wheel selectable.** DirectInput types any joystick
   with six or more axes as a 6-DOF controller, not a wheel, so games from
   before direct-drive existed refuse it. The proxy re-types it as
   `DI8DEVTYPE_DRIVING`; force feedback passes through untouched.
   → [docs/directinput-sixdof.md](docs/directinput-sixdof.md)
2. **Taps what the game already knows.** It reads steering and pedals from
   the same `GetDeviceState` calls the game makes, and force-feedback
   magnitudes from the effects the game sends to the wheel. No reverse
   engineering; this is the game's own data in flight.
3. **Reads live vehicle state.** RPM, max RPM, speed and gear are read from
   the game's HUD widget through UE4's reflection system — found by property
   *name*, so no version-specific offsets — with the FMOD engine-audio
   parameters as a second source.

All of it is emitted as **Forza "Data Out"** UDP packets, the most widely
parsed telemetry format there is, so SimHub, ShakeIt, dashboards and motion
rigs pick it up with zero integration work.
→ [docs/forza-format.md](docs/forza-format.md)

Milestone's games ship no telemetry and never documented their input model;
this fills both gaps from the outside.

## Status

| game   | engine  | wheel fix | input tap | FFB tap | FMOD physics | UE4 values | SimHub |
|--------|---------|-----------|-----------|---------|--------------|------------|--------|
| Gravel | UE 4.17 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ dash live |

Verified on hardware 2026-08-30: working speedometer and tachometer in SimHub,
with speed, RPM, gear, pedals, wheel slip and suspension travel all live.

Legend: ✅ verified on hardware · 🔧 wired, being validated · ▫ not yet tried

## Install

1. Build (below) or take `dinput8.dll` from a release.
2. Copy `dinput8.dll` and the game's `milestone_mod.ini` from `games/<game>/`
   **beside the shipping executable** — for UE4 that is
   `<game>\<game>\Binaries\Win64\`, *not* the game's root folder.
3. Set `product=` in the ini to your wheel's DirectInput product key
   (`(PID << 16) | VID`; MOZA R12 = `0006346e`).
4. For Milestone games, also add the wheel to `WheelConfig.ini` with
   `tools/wheelconfig.py` — the proxy makes the game *consider* the device,
   the whitelist entry tells it how to *map* it. Both are needed.
   → [docs/wheelconfig.md](docs/wheelconfig.md)
5. Launch. `milestone_mod.log` appears beside the exe while `log=1`.

⚠️ Only one `dinput8.dll` can live in a folder. FFB Arcade Plugin, DevReorder
and similar tools use the same name; do not install over them.

⚠️ Do not use in any title with kernel anti-cheat.

## Receiving the data

SimHub → *Games* → **Forza Motorsport 7** (for `format=fm7`) or **Forza
Horizon 4** (`fh4`), UDP port `5300`. SimHub binds the port exclusively;
set `mirror_port=` to feed a second listener such as `tools/forza_listen.py`.

## Build

MSYS2 MinGW-w64 (GCC 16, `E:\msys64` in `build.sh` — adjust the path):

```
./build.sh          # -> build/dinput8.dll (x64)
```

A 32-bit game needs a 32-bit build.

## Tools

| tool | purpose |
|------|---------|
| `tools/forza_listen.py` | decode and print packets; validation without SimHub |
| `tools/Measure-WheelAxes.ps1` | walk through each pedal, report which axis moves and which way, print `WheelConfig.ini` lines |
| `tools/wheelconfig.py` | add/update a device profile in `WheelConfig.ini` (CRLF-safe, clones a shipped block) |
| `tools/dump_bindings.py` | print action → key/slot bindings from `settings.sav`, so controls can be placed without the in-game rebind screen |

## Adapting to another game

Set `log=1` and `discover=1` under `[fmod]` and `[ue4]`, launch, drive one
lap, and read the log: every FMOD parameter name with its range, and every
UE4 property whose name mentions speed/rpm/gear/throttle/brake/steer, with
its owning class and offset. Put the right names in the ini. The UE4
scanner keys on data shapes, not code signatures, so it survives across
builds; the property-offset layout is probed at runtime for 4.11–4.24.

## Layout

```
src/            proxy.cpp fmod_tap.cpp ue4.cpp telemetry.cpp common.h
games/<game>/   per-game ini and notes
tools/          listener, axis measurer, WheelConfig and settings.sav tools
docs/           the techniques, written down
```

MIT licensed.
