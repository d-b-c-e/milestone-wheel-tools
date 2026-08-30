# Forza "Data Out" packet, as emitted here

Nothing about this mod is Forza-specific; the packet is used because it is
the most widely parsed telemetry layout there is (SimHub, ShakeIt,
SimRacingStudio, most dashboards and motion software). Three variants are
selectable with `format=` in `milestone_mod.ini`.

## Sled — 232 bytes, offset 0

| off | type   | field                                  |
|-----|--------|----------------------------------------|
| 0   | s32    | IsRaceOn                               |
| 4   | u32    | TimestampMS                            |
| 8   | f32×3  | EngineMaxRpm, EngineIdleRpm, CurrentEngineRpm |
| 20  | f32×3  | AccelerationX, Y, Z                    |
| 32  | f32×3  | VelocityX, Y, Z                        |
| 44  | f32×3  | AngularVelocityX, Y, Z                 |
| 56  | f32×3  | Yaw, Pitch, Roll                       |
| 68  | f32×4  | NormalizedSuspensionTravel FL FR RL RR |
| 84  | f32×4  | TireSlipRatio                          |
| 100 | f32×4  | WheelRotationSpeed                     |
| 116 | s32×4  | WheelOnRumbleStrip                     |
| 132 | f32×4  | WheelInPuddleDepth                     |
| 148 | f32×4  | SurfaceRumble                          |
| 164 | f32×4  | TireSlipAngle                          |
| 180 | f32×4  | TireCombinedSlip                       |
| 196 | f32×4  | SuspensionTravelMeters                 |
| 212 | s32×5  | CarOrdinal, CarClass, CarPI, DrivetrainType, NumCylinders |

## Dash — 79 bytes

`fm7` (311 B): dash at offset 232. `fh4` (324 B): 12 zero bytes at 232, dash
at 244.

| off | type  | field                                       |
|-----|-------|---------------------------------------------|
| 0   | f32×3 | PositionX, Y, Z                             |
| 12  | f32   | Speed (m/s)                                 |
| 16  | f32×2 | Power, Torque                               |
| 24  | f32×4 | TireTemp FL FR RL RR                        |
| 40  | f32   | Boost                                       |
| 44  | f32   | Fuel                                        |
| 48  | f32   | DistanceTraveled                            |
| 52  | f32×4 | BestLap, LastLap, CurrentLap, CurrentRaceTime |
| 68  | u16   | LapNumber                                   |
| 70  | u8    | RacePosition                                |
| 71  | u8×5  | Accel, Brake, Clutch, HandBrake (0-255), Gear |
| 76  | s8    | Steer (-127..127)                           |
| 77  | s8×2  | NormalizedDrivingLine, NormalizedAIBrakeDifference |

## What this mod fills

| field                    | source                                   | real? |
|--------------------------|------------------------------------------|-------|
| Accel/Brake/Clutch/HandBrake/Steer | the game's own `GetDeviceState` reads | yes |
| CurrentEngineRpm, EngineMaxRpm | UE4 HUD properties (fallback: FMOD RPM param) | yes |
| Speed, VelocityZ, Gear   | UE4 HUD properties                       | yes |
| AccelerationZ            | d(speed)/dt                              | derived |
| AccelerationX            | −(constant force), scaled to ±1 g        | derived — steering torque as a lateral-load proxy |
| SurfaceRumble ×4         | periodic FFB magnitude, else jerk of the constant force | derived |
| WheelOnRumbleStrip ×4    | periodic force > 0.5                     | derived |
| WheelRotationSpeed ×4    | speed / 0.33 m                           | derived |
| IsRaceOn                 | 1 while a live HUD instance is being read (`race_on=always` forces 1) | — |
| EngineIdleRpm            | 12 % of max                              | placeholder |
| everything else          | 0                                        | — |

Derived fields exist so effect engines have something to key on; the log
line every 5 s and `tools/forza_listen.py` show the raw channels so the
scaling can be calibrated against reality.

## Receiving

SimHub: *Games → Forza Motorsport 7* (for `fm7`) or *Forza Horizon 4/5* (for
`fh4`), UDP port matching `port=`. SimHub binds the port exclusively, so run
`forza_listen.py` on `mirror_port=` when both are wanted.
