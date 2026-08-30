# Gravel (Milestone, 2018 — UE 4.17, Steam appid 558260)

## Install

```
<Steam>\steamapps\common\Gravel\gravel\Binaries\Win64\
    gravel-Win64-Shipping.exe     (the game)
    dinput8.dll                   <- from build/
    milestone_mod.ini             <- this folder
```

Then add the wheel to the whitelist (game closed):

```
python tools/wheelconfig.py \
  --ini "<Steam>\steamapps\common\Gravel\gravel\Config\WindowsNoEditor\WheelConfig.ini" \
  --product 0006346e --name "MOZA R12 Wheel Base" \
  --steer Axis1 --throttle Axis3 --brake Axis6 --handbrake Axis7 --polarity low \
  --clear-buttons \
  --set Wheel_FaceButton_Bottom=Button1 --set Wheel_FaceButton_Right=Button2 \
  --set Wheel_FaceButton_Left=Button3   --set Wheel_FaceButton_Top=Button4 \
  --set Wheel_LeftShoulder=Button13     --set Wheel_RightShoulder=Button14 \
  --set Wheel_Special_Left=Button33     --set Wheel_LeftTrigger=Button34
```

Run the in-game wheel calibration once afterwards.

## What the game does

- Loads `dinput8.dll` from the exe's folder (no KnownDLL, so the proxy wins).
- Uses `IDirectInput8W`, creates the wheel device three times, sets
  **DIJOYSTATE2** (272 B) — all 128 buttons reach the game.
- Creates two constant-force effects and one spring at startup; force is
  only commanded while driving.
- Keeps axis ranges at DirectInput's default 0..65535.
- Delay-loads `fmodstudio64.dll` and imports
  `FMOD::Studio::EventInstance::setParameterValue` by name. In the menus the
  only parameter set is `fsm`; engine parameters appear in a race.
- GNames / GObjects are found in ~10 ms; ~123k objects in the front end,
  ~141k once a track is loaded.

## Bindings worth knowing (from `settings.sav`)

| action | slot |
|---|---|
| GearUp / GearDown | `Wheel_RightShoulder` / `Wheel_LeftShoulder` (`Wheel_Gear*` is unread) |
| Handbrake | `Wheel_RightTrigger` (button; the `Wheel_Handbrake` axis is unread) |
| RewindActivate | `Wheel_LeftTrigger` |
| SwitchCamera | `Wheel_Special_Left` |
| Confirm / Back | `Wheel_FaceButton_Bottom` / `Wheel_FaceButton_Right` |
| Pause / Start | `Wheel_Special_Right` |

`python tools/dump_bindings.py "%LOCALAPPDATA%\Gravel\Saved\SaveGames\settings.sav" --wheel`

## Measured reference

All verified on hardware 2026-08-30 (MOZA R12). Recorded so nothing here has
to be rediscovered.

### UE4 reflection

| item | value |
|---|---|
| `UProperty::Offset_Internal` | **`+0x50`** (probed; no published table lists this for 4.17) |
| HUD class | `IgnitionGaugeLogicWidget` |
| `VehicleCurrentRPM` | `+0x300` FloatProperty |
| `VehicleMaxRPM` | `+0x2fc` FloatProperty |
| `VehicleCurrentGear` | `+0x30c` IntProperty |
| speed property | **none exists** — speed comes from FMOD |
| object count | ~123k front end, ~141k in a race |
| discovery time | ~10 ms |

### FMOD parameters

Gravel sets **no RPM parameter**; it drives engine audio from real physics, so
these are the telemetry. Call count reveals the nature: high is a continuous
channel, low is an event.

| parameter | calls/race | range | used as |
|---|---|---|---|
| `VehicleSpeed` | ~175,000 | 0–0.70 | speed (× `speed_scale`) |
| `Wet` | ~161,000 | 0–0 | — (dry track) |
| `LateralSlip` | ~65,000 | 0–0.67 | TireSlipAngle |
| `LongitudinalSlip` | ~65,000 | −1–1 | TireSlipRatio |
| `torque` | ~13,500 | 0–1 | Torque / Power |
| `DamageState` | ~13,500 | 0–0 | — (never left 0) |
| `SuspensionMovement` | ~13,000 | 0–1 | suspension + surface rumble |
| `BrakingForce` | ~900 | 0–1 | — |
| `Intensity` | ~550 | 0–1 | **collision event** |
| `Speed` | ~450 | 0–0.49 | **collision velocity** |
| `GearUpDown` | ~120 | −1–1 | — |

Car-specific extras appear on some vehicles (`TurbineRpm`,
`AntiLagIntervention`, `Throttle`, `RVB_Tunnel`), so the set is not fixed.

### Collisions

Over **368 logged impacts**: `Intensity` is effectively binary — median 1.000,
mean 0.878 — so it reports *that* you hit something, not how hard. The
collision `Speed` (median 0.23, max 0.46) is the real discriminator, and
magnitude is weighted towards it. A wall scrape fires ~15 events in 200 ms,
each re-triggering the spike, which gives sustained rumble rather than one
thump.

### Wheel and input

| item | value |
|---|---|
| MOZA R12 | `dwDevType 0x18` (SIXDOF), 8 axes, 128 buttons |
| product key | `0006346e` = (PID `0006` << 16) \| VID `346E` |
| data format | **DIJOYSTATE2** (272 B) — all 128 buttons reachable |
| axis ranges | DirectInput default 0..65535 |
| pedals | idle **low**, so `&1.0&0.0` |
| steer / throttle / brake / handbrake | `Axis1` / `Axis3` / `Axis6` / `Axis7` |
| FFB effects | 2 constant + 1 spring, created at startup |

## Caveats

- No telemetry of any kind ships with the game; everything here is from
  the outside.
- The game rewrites `WheelConfig.ini` on exit and Steam's file verification
  restores the stock one.
- Delisted from Steam; the binary will not change again, so offsets found
  here are permanent.
