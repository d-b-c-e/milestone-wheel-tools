# Working on this codebase

Orientation for anyone — human or agent — picking this up cold. The README
explains what the project *does*; this explains how it works, what has actually
been verified, and which traps cost real debugging time.

## The one-line summary

Milestone's UE4 racing games refuse direct-drive wheels, cannot rebind controls
with one attached, and ship no telemetry. A `dinput8.dll` proxy beside the game
exe fixes the wheel and manufactures telemetry from three sources, emitting it
as Forza "Data Out" UDP; `WheelSetup.ps1` handles control mapping from outside
the game entirely.

The repo is `milestone-wheel-tools` - renamed from `milestone-telemetry`, since
the wheel fix is the more widely useful half. The config and log files are
still `milestone_mod.ini` / `milestone_mod.log`; renaming those would break
every existing install.

## Architecture

Four modules in one DLL. They are independent and can be worked on separately.

| file | job | how it gets its data |
|---|---|---|
| `src/proxy.cpp` | re-type the wheel; tap inputs and FFB | patches DirectInput vtables |
| `src/fmod_tap.cpp` | engine-audio parameters | hooks the delay-load IAT |
| `src/ue4.cpp` | RPM / gear from the HUD | UE4 reflection, no signatures |
| `src/telemetry.cpp` | assemble and send packets | 60 Hz thread, reads shared atomics |
| `WheelSetup.ps1` | map controls, calibrate pedals | drives `tools/wheelprobe`, parses `settings.sav` |
| `tools/wheelprobe/` | live 128-button / 8-axis reader | `c_dfDIJoystick2`, which PowerShell cannot reach |

All taps are **observe-only**. The single thing altered in the game's view of
the world is `dwDevType`. Hooks run on the game's threads and publish into
plain atomics; the sender thread reads them.

## Build, deploy, test

```bash
./build.sh                    # -> build/dinput8.dll (x64, MSYS2 MinGW-w64 GCC 16)
```

`build.sh` hardcodes `/e/msys64` — that is the development machine, adjust it.
A 32-bit game needs a 32-bit build.

The test loop that worked:

```powershell
# 1. close the game FIRST - it locks the DLL and rewrites its own configs on exit
# 2. deploy
Copy-Item build\dinput8.dll "<game>\Binaries\Win64\dinput8.dll" -Force
# 3. launch, drive, then read the log next to the game exe
```

`milestone_mod.log` (with `log=1`) has a status line every 5 s showing every
channel at once. Read it left to right; the first thing not `live` is the
problem. `mirror_port=` sends a copy to a second port so
`tools/forza_listen.py <port> --lines` can decode packets while SimHub holds
the real one.

**Never hard-kill a game while a wheel is attached.** A running DirectInput
constant-force effect is not released when the process dies, so the base keeps
applying the last torque and the next launch reads as "no FFB". Close it
gracefully.

## Verified facts (Gravel, UE 4.17, Steam 558260)

Measured on hardware 2026-08-30 with a MOZA R12. Do not re-derive these.

**UE4 reflection**
- `GNames` and `GObjects` are found in ~10 ms by scanning `.data` for a
  structure that *validates* — not by code signature, so it survives rebuilds.
- `UProperty::Offset_Internal` is at **`+0x50`** here. No published table lists
  that; 4.19+ is `+0x44`, older SDK dumps say `+0x4C`. It is probed at runtime
  using a sibling property that must read a *different* in-range offset — a
  lone plausible value passes by accident.
- The HUD class is **`IgnitionGaugeLogicWidget`**:
  `VehicleCurrentRPM +0x300`, `VehicleMaxRPM +0x2fc`, `VehicleCurrentGear +0x30c`.
  It has **no speed property** — that is why speed comes from FMOD.
- ~123k objects in the front end, ~141k with a track loaded.

**FMOD parameters** — the key insight: these games set **no RPM parameter**,
but they drive engine audio from real physics, so the parameters *are* the
telemetry. A parameter's **call count** tells you its nature.

| parameter | calls/race | range | use |
|---|---|---|---|
| `VehicleSpeed` | ~175,000 | 0–0.70 | speed, normalised to top speed |
| `Wet` | ~161,000 | 0–0 | unused (dry track) |
| `LateralSlip` | ~65,000 | 0–0.67 | slide angle |
| `LongitudinalSlip` | ~65,000 | −1–1 | wheelspin / lockup |
| `torque`, `DamageState` | ~13,500 | 0–1, 0–0 | engine torque |
| `SuspensionMovement` | ~13,000 | 0–1 | suspension travel |
| `BrakingForce` | ~900 | 0–1 | brake load |
| **`Intensity`** | ~550 | 0–1 | **collision** — see below |
| **`Speed`** | ~450 | 0–0.49 | **collision velocity** |
| `GearUpDown` | ~120 | −1–1 | shift event |

Car-specific extras appear too (`TurbineRpm`, `AntiLagIntervention`,
`Throttle`), so the set is not fixed across vehicles.

**Collisions** — over 368 logged impacts, `Intensity` is effectively binary
(median 1.000, mean 0.878): it says *that* you hit something, not how hard.
The collision `Speed` parameter (median 0.23, max 0.46) is the real
discriminator, so magnitude is weighted towards it. Current scaling gives a
mean of ~4 g across a 0.7–77.7 m/s² range.

**DirectInput**
- The MOZA R12 reports `dwDevType 0x18` (1STPERSON/SIXDOF), 8 axes, 128
  buttons. Six or more axes is what triggers the misclassification.
- Gravel reads **DIJOYSTATE2** (272 bytes), so all 128 buttons are reachable.
- Axis ranges stay at DirectInput's default 0..65535.
- Pedals idle **low** on MOZA, **high** on Logitech/Fanatec.

**Packet** — Horizon is exactly **324 bytes** (`232 + 12 pad + 79 dash + 1
trailing`). 323 is rejected silently. Confirmed by probing every candidate size
against SimHub's `ForzaReader`.

## Traps

Each of these cost real time and none produces an error message.

1. **The delay-load thunk self-unhooks.** `fmodstudio64.dll` is a delay-load
   import. Calling the original slot value resolves the import *and* overwrites
   our hook. Resolve the real function with `GetProcAddress` once the DLL is
   loaded; only fall back to the thunk if it is not, then re-install.

2. **Vtable indices are load-bearing.** `IDirectInput8`: 3 CreateDevice,
   4 EnumDevices. `IDirectInputDevice8`: 3 GetCapabilities, 5 GetProperty,
   6 SetProperty, 9 GetDeviceState, 11 SetDataFormat, 15 GetDeviceInfo,
   18 CreateEffect. `IDirectInputEffect`: 6 SetParameters. Vtables are shared
   per class, so every hook must re-check the object.

3. **Blank device twins.** Gravel creates three device objects for the same
   wheel; only one is acquired. The others return all-zero state at poll rate
   and will overwrite good input. Once an object has produced a non-blank
   state, ignore the ones that never have.

4. **Two constant-force effects run at once.** A single shared magnitude takes
   whichever updated last — usually the smaller. Track per effect, strongest
   wins.

5. **`WheelConfig.ini` is CRLF**, and the game **rewrites it on exit**. A
   `.*?$` regex eats the `\r` and silently converts edited lines to bare LF;
   match `[^\r\n]*`. Steam's file verification restores the stock file.

6. **PowerShell 7 cannot marshal a delegate through a COM interface.** For the
   DirectInput tools, pass the enumeration callback as a raw function pointer
   via `Marshal.GetFunctionPointerForDelegate`, and give `DirectInput8Create` a
   real `GetModuleHandleW(IntPtr.Zero)` — a null string marshals to
   `E_INVALIDARG`.

7. **Steam is often not under Program Files.** Read `SteamPath` /
   `InstallPath` from the registry; it was on `D:` on the development machine
   and a Program-Files-only scan found nothing.

8. **FMOD stops updating between races.** Without clearing them, the last
   in-race values persist through the menus and a shaker sits on a constant
   output.

## What is assumed rather than measured

- `speed_scale = 55.0` converts normalised `VehicleSpeed` to m/s. Eyeballed
  against the in-game speedo; close but not calibrated.
- `Dash.torque` is scaled to a nominal 400 Nm — the *shape* is real, the units
  are invented.
- `EngineIdleRpm` is 12 % of max, a placeholder.
- `WheelRotationSpeed` assumes a 0.33 m wheel radius.
- Only Gravel has been tested. MXGP / MotoGP / Ride / Supercross are untried.

## Adding a game

1. Set `discover=1` under both `[fmod]` and `[ue4]`, drive a lap, read the log.
   It lists every FMOD parameter with its range and every property of the class
   holding RPM.
2. Put the right names in a new `games/<name>/milestone_mod.ini`.
3. Add it to `$KNOWN` in `Install.ps1` (Steam appid, folder, exe prefix).
4. Record verified values in `games/<name>/README.md`.

Expect the FMOD names to differ per title but the *approach* to hold: high call
counts are continuous channels, low counts are events.

## Conventions

- Comments explain **why**, not what. The traps above are why the code looks
  the way it does.
- Prefer measuring over reasoning. Every wrong turn in this project came from
  inferring a value that could have been read from a log.
- Config is read at game start, so tuning needs no rebuild.
- Keep `dist/dinput8.dll` in step with `src/` when committing — the installer
  and the release both use it.
