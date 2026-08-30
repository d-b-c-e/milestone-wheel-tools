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

## Caveats

- No telemetry of any kind ships with the game; everything here is from
  the outside.
- The game rewrites `WheelConfig.ini` on exit and Steam's file verification
  restores the stock one.
- Delisted from Steam; the binary will not change again, so offsets found
  here are permanent.
