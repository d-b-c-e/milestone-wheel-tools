# milestone-wheel-tools

**Make direct-drive wheels work with Milestone's UE4 racing games — and add the
telemetry they never shipped.**

Gravel, MXGP, MotoGP, Ride and Supercross all refuse modern direct-drive
wheels, have a rebind screen that cannot be used with one, and expose **no
telemetry at all**. This fixes all three from the outside.

| you want | run |
|---|---|
| the game to see your wheel, and telemetry in SimHub | `.\Install.ps1` |
| to map controls without fighting the in-game menu | `.\WheelSetup.ps1` |

Both detect your wheel and find the game themselves. There is nothing to
configure by hand.

> **Wheel not detected in Gravel?** That is the first thing this fixes — see
> [what it actually does](#what-it-actually-does) below, or jump to
> [troubleshooting](docs/troubleshooting.md).

---

## What it actually does

**1. Makes a direct-drive wheel selectable.**
DirectInput classifies any joystick with six or more axes as a
*six-degrees-of-freedom controller*, not a wheel. A MOZA R12 exposes eight, so
games written before direct-drive existed are told it is a SpaceOrb and offer
it as neither wheel nor gamepad — in Gravel the controls menu flickers
endlessly between keyboard and controller. The proxy re-types it as
`DI8DEVTYPE_DRIVING`. Force feedback passes through untouched, which routing
the wheel through XInput would cost you.
→ [docs/directinput-sixdof.md](docs/directinput-sixdof.md)

**2. Reads what the game already knows.**
Steering and pedal positions come from the same `GetDeviceState` calls the game
itself makes; force magnitudes come from the effects it sends to your wheel.
That is the game's own data in flight, not anything reconstructed.

**3. Finds the vehicle state.**
RPM, gear and max RPM are read from the game's own dashboard widget through
UE4's reflection system — located by property *name*, so there are no
version-specific offsets to break.

**4. Uses the engine audio as a physics feed.**
The real find: these games have no telemetry, but they drive their engine
*sound* from live physics. So the FMOD parameters **are** telemetry — wheel
slip, suspension travel, engine torque, brake load and collisions, all per
frame. That is far better material for a bass shaker than anything inferred
from force feedback.

All of it goes out as **Forza "Data Out"** UDP — the most widely parsed
telemetry format there is — so SimHub, ShakeIt, dashboards and motion rigs pick
it up with no integration work.
→ [docs/forza-format.md](docs/forza-format.md)

## Status

| game | engine | wheel fix | inputs | FFB | physics | dash | impacts |
|---|---|---|---|---|---|---|---|
| **Gravel** | UE 4.17 | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 |

✅ verified on hardware · 🔧 implemented, being validated · ▫ untested

Verified with a MOZA R12: working speedometer and tachometer in SimHub, with
speed, RPM, gear, pedals, wheel slip and suspension travel all live.

MXGP, MotoGP, Ride and Supercross share the engine and should need only new
parameter names in the ini — see *Adapting to another game* below.

## Install

**Recommended.** Download `dinput8.dll` from [Releases](../../releases) into
`dist\`, then:

```powershell
.\Install.ps1
```

It finds your game in any Steam library (reading the registry, so it works
wherever Steam actually lives), detects your wheel and derives its product key,
installs the DLL and a matching config, adds the wheel to the game's device
whitelist, and prints exactly what to select in SimHub. Close the game first —
it locks the files.

Useful switches:

```powershell
.\Install.ps1 -Port 8000 -Format fh4              # match your SimHub setup
.\Install.ps1 -Game Gravel                        # skip the menu
.\Install.ps1 -GamePath "D:\...\Binaries\Win64"   # a game it doesn't know
.\Install.ps1 -Product 0006346e                   # if it picks the wrong device
```

**Manually**, if you prefer: copy `dinput8.dll` and a
`games\<game>\milestone_mod.ini` next to the game's shipping executable — for
UE4 that is `<game>\<game>\Binaries\Win64\`, **not** the game's root folder —
and set `product=` to your wheel's DirectInput key.

⚠️ Only one `dinput8.dll` can live in a folder. FFB Arcade Plugin, DevReorder
and similar tools use the same name; the installer refuses to overwrite a
different one rather than break it.

⚠️ Never use this in a game with kernel anti-cheat.

## Mapping your controls

Milestone's rebind screen is unusable with many direct-drive wheels — an axis
resting at an extreme reads as permanently deflected, so the "press a control"
listener latches onto it and never sees the button you press. Do it from
outside the game instead:

```powershell
.\WheelSetup.ps1
```

It finds the game, reads the game's own action list out of its save file,
detects your wheel, and then:

- **Calibrate pedals** — work each pedal through its travel and it identifies
  which axis moved and which way, deriving the polarity. Copying another
  wheel's block is what leaves a game convinced a pedal is held down.
- **Bind a control** — pick *"Rewind"* or *"Change camera"*, press the button
  you want, done.

That second one hides an indirection you would otherwise have to work out
yourself. These games bind in two layers — physical button → logical slot
(`WheelConfig.ini`), then logical slot → game action (`settings.sav`) — so
putting rewind on a button really means finding which `Wheel_*` slot
`RewindActivate` listens to and pointing *that* at your button. The defaults
hold surprises: in Gravel `GearUp` listens to `Wheel_RightShoulder`, and
nothing at all reads `Wheel_GearUp`.

Reading all 128 buttons needs `c_dfDIJoystick2`, which is why
`tools/wheelprobe` is a small native helper rather than pure PowerShell.

Run the game's wheel calibration once afterwards.

## Setting up SimHub

Pick a Forza game in SimHub, note the UDP port it shows, and match both in
`milestone_mod.ini`:

| SimHub game | `format=` | bytes |
|---|---|---|
| Forza Horizon 4 / **Horizon 5** | `fh4` | 324 |
| Forza Motorsport 7 | `fm7` | 311 |

**The length must match the game you picked.** A mismatch fails silently — no
error, the dash simply stays dead. SimHub's own log (`SimHub\Logs\SimHub.txt`)
is the one place that says which happened: `started receiving valid data` and
`Game connected`, or `started receiving unprocessed data` at packet rate.

For the shaker, the channels worth binding in ShakeIt are **wheel slip**
(wheelspin and lockup), **suspension travel** (surface texture and landings)
and **acceleration** (impacts). Those are real physics, not derived.

## Something not working?

→ **[docs/troubleshooting.md](docs/troubleshooting.md)**

Nearly every failure in this chain is silent, so that page is organised by
symptom and, for each, names the log that actually tells you the answer. Set
`log=1` in the ini and `milestone_mod.log` appears next to the game exe with a
status line covering every channel at once.

## Uninstall

```powershell
.\Uninstall.ps1
```

Or delete `dinput8.dll` and `milestone_mod.ini` from the game folder. The
`WheelConfig.ini` entry is harmless if left, and Steam's *Verify integrity of
game files* removes it anyway.

## Build

Only needed if you would rather not use the release binary. MSYS2 MinGW-w64
(GCC 16); adjust the toolchain path at the top of `build.sh`:

```bash
./build.sh          # -> build/dinput8.dll (x64)
```

A 32-bit game needs a 32-bit build. The Forza encoder and the installer's
Steam/DirectInput helpers are vendored from
[dbce-wheel-mod-toolkit](https://github.com/d-b-c-e/dbce-wheel-mod-toolkit)
under `lib/toolkit` (pinned in `lib/toolkit/VERSION`); bump with
`tools\Sync-Toolkit.ps1 -Version vX.Y.Z -Parts include,powershell`.

## Tools

| tool | purpose |
|---|---|
| `WheelSetup.ps1` | map controls and calibrate pedals without the in-game menu |
| `Install.ps1` / `Uninstall.ps1` | install or remove the mod, detecting game and wheel |
| `tools/Sync-Toolkit.ps1` | re-vendor the toolkit pieces under `lib/toolkit` |
| `tools/wheelprobe/` | native helper that reads all 128 buttons and 8 axes live |
| `tools/forza_listen.py` | decode and print the packets — validate without SimHub |
| `tools/Measure-WheelAxes.ps1` | walks you through each pedal, works out which axis moves and which way, prints the config lines |
| `tools/wheelconfig.py` | add or update a device in `WheelConfig.ini` (CRLF-safe, clones a shipped block) |
| `tools/dump_bindings.py` | print the real action → button bindings from `settings.sav` |

## Adapting to another game

Set `discover=1` under both `[fmod]` and `[ue4]`, drive one lap, and read
`milestone_mod.log`. It lists every FMOD parameter with its observed range and
every property of the class holding RPM; put the right names in the ini.

Two things learned from Gravel that should generalise: these games set **no RPM
parameter** through FMOD (RPM comes from the HUD widget instead), and a
parameter's **call count** tells you its nature — hundreds of thousands means a
continuous channel, a few hundred means an event such as a collision or gear
change.

The UE4 scanner keys on data *shapes* rather than code signatures, so it
survives across builds, and the property-offset layout is probed at runtime
(Gravel's 4.17 sits at `+0x50`, which no published table lists).

## How it is put together

```
src/proxy.cpp        DirectInput proxy: re-type, input tap, FFB tap
src/fmod_tap.cpp     FMOD Studio parameter hook (delay-load IAT)
src/ue4.cpp          UE4 reflection: GNames/GObjects, property lookup
src/telemetry.cpp    60 Hz sender, Forza packet assembly
games/<game>/        per-game config and notes
tools/               listener, axis measurer, config editors
docs/                the techniques, written down properly
```

MIT licensed. Not affiliated with Milestone, Microsoft or SimHub.
