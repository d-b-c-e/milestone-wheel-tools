# Milestone UX adoption — 2026-09-16

Guidance: dbce-wheel-mod-toolkit **a84bebab5ec2abdcd5140b9c63c139ccff86a7d3**,
UX-1 / UX-01-S and its controls/cameras and installation companion documents.
Source baseline: **411f351**, toolkit runtime pin **v0.8.0**, unchanged.
Initial implementation: **4ac0f117265ddf4d846f0d699e5d4bf3d7add3db**.
The follow-up closes the saved-telemetry editor and malformed-view recovery gaps.
Also compared with the toolkit's `docs/reference/wheel-settings.html` on
2026-09-17 (SHA256
`cd64239d2a4f092a69d74d05fe8a85e915509fd8686d19a7df2cf18ac8323996`).
Its page order, labels, Simple/Advanced placement and Apply/Cancel behavior
guide this surface; terminal rendering and next-launch-only status are explicit
exceptions to the browser illustration, not claims of in-game UI compliance.

## Scope and status

The supported player interface is `WheelSetup.ps1`, an external terminal tool,
plus `Install.ps1` / `Uninstall.ps1`. There is no in-game UI renderer, F6 hook,
mod FFB output controller, or added camera layer in this repository. This pass
improves that actual surface. It does **not** certify full shared UX compliance.
No game was launched, deployed to, or physically tested during this pass.

| Product | Current evidence | Scope of this change |
|---|---|---|
| Gravel | Existing hardware verification: MOZA R12, 2026-08-30; one checked-in game preset | External setup and installer changes; new UI interaction covered by fixtures, physical revalidation pending |
| MXGP3, MXGP PRO | Installer discovery entries; no checked-in game preset or hardware verification | Same external tool available; do not claim a tested drive or reuse Gravel action defaults |
| MotoGP 18, MotoGP 19 | Installer discovery entries; no checked-in game preset or hardware verification | Same external tool; actual action list requires this game's save; runtime unverified |
| Monster Energy Supercross | Installer discovery entry; no checked-in game preset or hardware verification | Same external tool; runtime unverified |
| Ride / other Milestone UE4 titles | Mentioned as engine-family candidates, absent from discovery table | Manual-path development candidates only; no adoption or compatibility claim |

There is one interface implementation shared by the entries above, not a
separate UI per game. Unknown games no longer inherit Gravel button actions
silently. Save discovery is limited to the selected game; an ambiguous/missing
save leaves buttons unavailable unless using the verified Gravel defaults.
`-SettingsSave` selects an exact save for advanced troubleshooting.

## Implemented experience

- Double-click Install.bat → WheelSetup.bat → Simple Setup. Steering, Throttle
  and Brake are the required assignments; handbrake/clutch/buttons are optional.
- The six familiar page names are retained. View choice appears in each page
  header, starts Simple when absent/unknown, and persists only when explicitly
  selected. Advanced exposes raw mappings, device identities and file details.
- Each axis can be bound independently. Separate rest and movement samples
  determine polarity; the old formula always classified a moving pedal as
  low-rest. Multiple moving axes now reject capture rather than choosing one.
- Esc cancels active input capture; every proposal has a cancel path. No
  binding changes until accepted. Axis and button handbrake fields stay
  independent, including cancellation. Button conflicts/shared game slots are
  reported before acceptance.
- Working mappings are staged until Save mappings and exit, then saved atomically with
  a dated backup. Failed writes and concurrent file changes keep the old file.
- The input-reader helper is found in the shipped `dist/` folder as well as
  the development path. Duplicate product identities block ambiguous capture.
- View state is separate LocalAppData JSON. No view action acquires/reopens a
  device, modifies runtime settings, enables FFB or starts telemetry.
- If the presentation JSON is malformed, startup warns and falls back to Simple
  without changing the file. Explicitly choosing a view repairs only this
  presentation file, preserving its exact original bytes in a reported dated
  backup. Failed repair leaves the invalid file intact for recovery.
- Simple Telemetry shows saved Off/On, actual receiver/destination and explicit
  **next game launch; runtime delivery unverified** status. Off/On writes only
  its saved preference; it is not a live sender stop. The native proxy reads
  configuration once, guarded by `g_inited` in `src/proxy.cpp:413-424`.
- Connection settings (Advanced) opens a draft for receiver IPv4 address,
  port and format. Apply writes all three together with a backup; Cancel writes
  none. Invalid destination/format, write failure and concurrent edits preserve
  the old saved configuration. On validates the saved connection first; Off
  can be saved without replacing an unrecognized destination.
- IPv4-only validation follows the existing `inet_pton(AF_INET)` sender in
  `src/telemetry.cpp:137-140`; no DNS or IPv6 support is implied. Saved connection
  matches name their actual reference (fresh installer or shipped Gravel
  preset). Other connections are explicitly custom or need review.
- Ordinary updates retain the saved wheel, telemetry Off, custom destinations,
  format and tuning. Explicit installer overrides change only their own field.
  Uninstall retains personal settings and backups by default.

## Placement inventory

All rows apply to the external tool. Advanced includes the same ordinary
actions in the same order. Fields unavailable in this tool are classified and
recorded as gaps; their existence in a text file does not mean UI adoption.

| Setting/action or saved key | Page | Placement | Default/unit and reason | Source/evidence |
|---|---|---|---|---|
| View (`View` in LocalAppData settings-view.json) | Header, all pages | Simple and Advanced | Simple when missing/invalid; explicit choice remembered; malformed-file repair backs up original bytes | Get/Save-SettingsView; migration, recovery, failed repair and round-trip fixtures |
| Game and input device selection (`-GamePath`, `-Product`) | Before Setup | Simple | Discover, then directly select from numbered friendly list; no Next-only picker | Startup discovery; synthetic one-device integration |
| Setup readiness | Setup | Simple | Next missing Steering/Throttle/Brake only; does not claim a drive was verified | First screen integration |
| Steering (`Wheel_Steer`) | Controls / Setup next step | Simple | Preserve existing; new profile starts unbound | Individual rest/travel flow; calibration fixtures |
| Throttle (`Wheel_Accelerator`), Brake (`Wheel_Brake`) | Controls / Setup next step | Simple | Preserve existing; no inherited unverified bindings | High/low-rest and ambiguous/no-movement fixtures |
| Handbrake axis (`Wheel_Handbrake`) | Controls | Simple | Optional; independent of game button slot | Accept/cancel integration; button-preservation checks |
| Clutch (`Wheel_Clutch`) | Controls | Simple on demand | Optional, individually selected | Same axis workflow; physical behavior not tested |
| Axis direction/inversion, Bind / Clear / Save calibration / Cancel | Controls | Simple on demand | Measured direction; retains previous assignment on cancel | Capture and file fixtures; live Esc key not physically exercised |
| Gear up/down, Handbrake button, Rewind, Pause, Confirm, Back, Respawn, Photo mode (resolved Wheel_* slots) | Controls | Simple on demand | Existing game actions; friendly labels and 1-based button numbers | Action resolution source; shared-slot warning; real button capture not tested |
| Change camera (`SwitchCamera` resolved slot) | Cameras and Controls | Simple on demand | Same shared binding operation | Menu fixture; stock game camera cycle unchanged |
| Raw mapping block, product key/type, config and preference paths | Controls / Help | Advanced only | Inspection; no extra binding store | Advanced navigation fixture |
| Profile FFB (`ForceFeedback`) / rotation (`MaxRotationAngle`) | FFB | Advanced only, read-only here | Preserve existing; game owns setup and output | Source; unchanged file checks |
| Actual FFB enable/strength/device/recovery | FFB | Gap: game-owned controls | Plain capability explanation, no ineffective mod toggle | `src/proxy.cpp` passes effects through; native source unchanged |
| Bonnet/Bumper and adjustment shortcuts | Cameras | Gap: no implementation | Plain unsupported message, no fake toggle | No mount/input/camera hook; no runtime change |
| Telemetry `enabled`, receiver/destination/status | Telemetry | Simple | Saved Off/On with actual destination; applies next launch only; no runtime-delivery claim | Interactive On/Off, field-isolation and view fixtures |
| Telemetry `host`, `port`, `format` | Telemetry | Advanced only, draft editor linked from Simple | Apply connection/Cancel; IPv4 and port 1–65535; explicit known receiver list; saved Off retained | Draft cancel, invalid Apply, unknown fields, backup, failed atomic replacement and update fixtures |
| Telemetry `rate`, `mirror_port`, `race_on` | Telemetry | Advanced only, existing INI surface | Existing values kept; not required for a normal receiver | Config source; connection field-isolation fixtures |
| Input telemetry axes: steer, throttle, brake, handbrake, clutch | Telemetry | Advanced only, existing INI surface | Existing configured telemetry mapping; setup does not silently rewrite telemetry semantics | Existing config and runtime unchanged |
| Proxy product/retype/log; FFB gain | Help / FFB | Advanced only, existing INI surface | Preserve existing settings; product override explicit | Installer fixture preserves gain and selected product |
| FMOD discover, rpm/load/speed/slip/suspension/braking/impact channel names, impact_gain/impact_decay_ms/speed_scale | Telemetry | Advanced only, existing INI surface | Game-adapter diagnostics/scaling, not first-drive choices | Existing Gravel preset; all unchanged |
| UE4 enabled, rpm/maxrpm/speed/gear property names, speed_scale, gear_offset | Telemetry | Advanced only, existing INI surface | Game-specific adapter settings, not first-drive choices | Existing Gravel preset; all unchanged |
| Save/exit, exit without saving, save/capture failures | All pages | Simple and Advanced | Save mappings and exit writes once; view preference is independent | Write-lock, concurrent edit, cancel, round-trip fixtures |
| Symptom help / terminal text size | Help | Simple | Uses terminal's native text sizing | Source; DPI readability pending |
| Support export / broad reset tools | Help | Gap | Existing logs/docs only, no support bundle or bulk reset UI | Not implemented or claimed |

No hidden tuning is edited by this pass. FFB remains game-owned. Telemetry
shows a quiet custom-connection summary or an identified preset match, while
preserving unknown keys, channel mappings and rates. A broader comparison of
all hidden force/adapter tuning is still a gap; the tool never calls that
uninspected configuration “defaults.”

## Evidence and remaining acceptance

`tools/tests/Test-SetupUx.ps1` runs disposable file fixtures and a synthetic
console input-reader executable; it never calls DirectInput or loads the
inert fixture DLL. It covers missing/invalid preferences, persistence, locked
writes, setting isolation, raw/friendly labels, pedal polarity, ambiguity,
save backups, concurrent file changes, six-page navigation, view round trips,
handbrake cancel/save and ordinary/explicit installer updates and uninstall.
The telemetry extension exercises address/port/format validation, draft
cancellation, unknown field preservation, connection Apply with saved Off,
Simple On/Off isolation, case-preserving INI edits and atomic replacement failure
after the editor has opened. No socket is created by the fixture or setup tool.
Preference recovery is exercised from malformed JSON through Simple fallback,
explicit Advanced selection and reload, including a denied replacement that
preserves the original bytes and a successful byte-for-byte backup.

Validation completed **2026-09-17**, before any game deployment:

| Check | Result |
|---|---|
| Windows PowerShell 5.1.26100.9444: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/Test-SetupUx.ps1` | **106 passed** |
| PowerShell 7.6.5: `pwsh -NoProfile -File tools/tests/Test-SetupUx.ps1` | **106 passed** |
| `git diff --check` and PowerShell parsing | Passed |
| Runtime / vendored / prebuilt DLL diff | No changes |

Local transcripts: `E:\Source\milestone-wheel-tools-ux-20260916-ps51-test.log`
and `E:\Source\milestone-wheel-tools-ux-20260916-ps7-test.log`. Final fixture
directories end in `milestone-ux-0af2639d0ebc4e25883b9ddef11daee3` (5.1) and
`milestone-ux-52624220f854485e964f2f4a62dfe046` (7.6.5) under the user's Temp.
They contain only generated settings, test code and inert/synthetic binaries.

The native proxy and vendored toolkit were unchanged, so no force smoke or
native DLL build was required for this script/UI change.

Full UX-1 adoption is still blocked by real product work:

1. No F6 in-game renderer. This is an intentional bounded surface exception for
   this pass, not completion of the shared runtime UI requirement.
2. No live calibrated preview, endpoint/deadzone UI, independent per-action
   device identities, physical duplicate-instance selection, or real-time
   game input verification. Finish endpoints/deadzones in the game's setup.
3. Game-owned FFB lacks the mod-level saved Off/On, Stop FFB/F8, steering-derived
   dropdown and lifecycle status required by the shared mod contract.
4. No added Bonnet/Bumper mounts, camera ownership hooks or numpad/rebinding
   implementation. Only the existing game camera button can be bound.
5. Telemetry's ordinary saved controls and connection editor are implemented;
   runtime delivery and receiver acknowledgment remain unavailable to this
   external tool. Rate, mirrors and channel diagnostics remain advanced INI
   settings. No live sender-control or receiver test is claimed.
6. Installer still has older gaps: Python dependency for automatic whitelist
   creation, broad engine-family fallback preset, no full transactional DLL +
   config + whitelist rollback, and no fully bundled release artifact tested
   here. No package or public release was published.

Not tested: attended physical capture (including Esc), live combined analog /
button handbrake, hot unplug, game first drive, FFB feel, 720p/4K terminal
readability, real Steam discovery with several installed games, or each
unverified game's wheel/action semantics. The fixture checks do not establish
those outcomes. Continue from this audit before calling the product reconciled.
