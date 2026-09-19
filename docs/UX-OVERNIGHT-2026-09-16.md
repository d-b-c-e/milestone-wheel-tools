# Milestone UX adoption — 2026-09-16

Guidance: dbce-wheel-mod-toolkit **a84bebab5ec2abdcd5140b9c63c139ccff86a7d3**,
UX-1 / UX-01-S and its controls/cameras and installation companion documents.
Source baseline: **411f351**, toolkit runtime pin **v0.8.0**, unchanged.
Initial implementation: **4ac0f117265ddf4d846f0d699e5d4bf3d7add3db**.
The follow-up closes the saved-telemetry editor and malformed-view recovery gaps.
Published candidate before preview: **05fd6dc2f79508df2125106cca080e3e9d7ab5e5**.
The next bounded change adds read-only device preview, without native changes.
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
- Controls → Preview device input is available on demand in Simple. It uses
  staged assignments and shows Steering Left/Centre/Right and pedal/handbrake
  Released/Full percentages. Only known normal/inverted Axis1-8 transforms are
  interpreted; custom mappings say Preview unavailable. Advanced adds raw
  values. Device normalization is explicitly distinguished from the game's
  final calibration, deadzones and effective input.
- One input-only helper process owns each preview, capped at 10 seconds.
  Esc, native exit, device error, lost sample heartbeat and a supervised timeout all clean up the
  process and return; no mappings, telemetry or presentation state are saved.
  The same process owner handles calibration captures. Preview checks the
  selected game is still closed before reading input.
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
| Preview device input | Controls | Simple on demand; raw values Advanced only | Read-only, 10 seconds/Esc, staged mappings; fixed device-range normalization, not game-final input | Centre/left/right, inverted released/full, clamping, custom-unavailable, staged polarity, disconnect/cancel/timeout cleanup and no-write fixtures |
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
Preview tests cover mapped values, inversion, neutral/full and out-of-range
clamping. Interactive fixture navigation confirms staged polarity is used;
saved mapping, telemetry and preference bytes remain identical afterwards.
Injected cancellation, stalled-reader and lost-heartbeat tests verify prompt return and actual
child-process termination. These use the synthetic reader, not real hardware.

Validation completed **2026-09-17**, before any game deployment:

| Check | Result |
|---|---|
| Windows PowerShell 5.1.26100.9444: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/Test-SetupUx.ps1` | **140 passed** |
| PowerShell 7.6.5: `pwsh -NoProfile -File tools/tests/Test-SetupUx.ps1` | **140 passed** |
| `git diff --check` and PowerShell parsing | Passed |
| Runtime / vendored / prebuilt DLL diff | No changes |

Local transcripts: `E:\Source\milestone-wheel-tools-ux-20260916-ps51-test.log`
and `E:\Source\milestone-wheel-tools-ux-20260916-ps7-test.log`. Final fixture
directories end in `milestone-ux-2d670635aed9482d9ee9a911c2dd0782` (5.1) and
`milestone-ux-98a30ab466d4422ca037242854f4c2c6` (7.6.5) under the user's Temp.
They contain only generated settings, test code and inert/synthetic binaries.

The native proxy and vendored toolkit were unchanged, so no force smoke or
native DLL build was required for this script/UI change.

Full UX-1 adoption is still blocked by real product work:

1. No F6 in-game renderer. This is an intentional bounded surface exception for
   this pass, not completion of the shared runtime UI requirement.
2. Device-range preview is implemented, but verified game-final input and
   endpoint/deadzone UI, independent per-action device identities and physical
   duplicate-instance selection are still missing. Finish endpoints/deadzones
   in the game's setup; device percentages do not establish game calibration.
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

Not tested: attended physical capture/preview (including the real Esc key and
console cursor redraw), live combined analog /
button handbrake, hot unplug, game first drive, FFB feel, 720p/4K terminal
readability, real Steam discovery with several installed games, or each
unverified game's wheel/action semantics. The fixture checks do not establish
those outcomes. Continue from this audit before calling the product reconciled.

## Delivery follow-up — 2026-09-19

The 0.2.0 follow-up closes the packaging/installer gaps listed in item 6 above.
It builds and distributes the complete external setup tool, its input helper,
required PowerShell modules and player help. Install.bat creates Wheel settings.bat
in Gravel's main folder. Fresh whitelist creation no longer needs Python; new
profiles keep bindings empty until the user binds them. Existing profile and
INI bytes survive ordinary updates exactly. Dated backup manifests precede
transactional replacements, and partial failure rolls back completed writes.
A running-game guard also protects rollback; if the game starts midway, the
error identifies backups and stops writes until the game is closed. Receipt
hashes let uninstall retain files subsequently edited by the owner. The complete
package manifest is mandatory and its identity, exact path set and hashes are
validated before discovery or changes. Uninstall backs up all planned removals
and rolls back completed deletions if a later file is locked. External replacements
remain untouched during rollback. These close two independently reviewed
delivery findings before the real installation.

The package supports **Gravel only**. Earlier discovery entries for MXGP3,
MXGP PRO, MotoGP18/19 and Supercross were not evidence of support and are no
longer accepted by Install.ps1. The existing external tool remains useful for
explicit development paths, but other games require a verified adapter and
preset before installer support. This machine has only Gravel among the
previously listed installer targets.

### Placement inventory additions

| Option / action | Placement | Scope |
|---|---|---|
| Install / Update | Install.bat, ordinary player entry | Discovers Gravel, preserves existing settings and creates backups |
| Wheel settings launcher | Game root | Opens the exact deployed configuration in the external Simple view |
| Binding axis + polarity | Simple Controls | Bind / Save binding / Cancel; no full-calibration claim |
| Endpoint / centre / deadzone calibration | Gravel's own controls | Adapter constraint below; not editable or verified by preview |
| Port / format / wheel identity install override | Advanced PowerShell arguments | Only explicitly supplied fields change |
| Install receipt / backup manifest / package hashes | Advanced diagnostics | Recovery and exact artifact provenance |
| Uninstall | Installed or packaged Uninstall.bat | Removes matching owned files, retains owner settings and edited files |

### Calibration adapter constraint

Read-only inspection of the installed Gravel build 3477925 profile on
2026-09-19 found `AxisN&scale&offset`, `MaxRotationAngle` and
`MinRotationAngle`, but no raw endpoint, centre or deadzone fields. The existing
MOZA profile is already present. Stock axis transforms are normal (1, 0) or
inverted (-1, 1). An arbitrary affine transform could rescale one interval;
it cannot represent independent left/centre/right endpoints or deadzones.
`src/proxy.cpp` observes GetDeviceState and retypes the device; it does not
transform game input. `settings.sav` is read for action names only, with no
verified calibration writer. Consequently this pass keeps game calibration in
Gravel, changes the misleading Save calibration label to Save binding, and
does not invent an unverified native transform or binary-save editor.

The native source and toolkit v0.8.0 pin remain unchanged. Both native artifacts
were rebuilt with GCC 16.2.0; build.ps1 checks x64 PE format, all six proxy
exports and no unbundled compiler-runtime imports. One existing benign helper
strncpy truncation warning remains (a static zero-initialized 256-byte name
buffer receives at most 255 bytes). No native helper or game was executed.
README and existing CLAUDE working notes were reconciled. This repository has
no AGENTS.md or CHANGELOG.md to update; the dated audit records this change.

Local delivery evidence and exact source/package/backup hashes are recorded in
`docs/DEPLOYMENT-2026-09-19.md` after installation. The historical evidence above
remains scoped to its original date. Physical input, actual Esc/console redraw,
first drive, telemetry delivery and game-owned FFB/cameras still require an
attended check; rebuilding/deploying does not establish those outcomes.

2026-09-19 pre-deployment validation: **140 UX/migration checks and 81
install/package checks passed on both Windows PowerShell 5.1.26100.9444 and
PowerShell 7.6.5**. Install checks include empty-file preservation, injected
partial-write rollback, game-start write/rollback guard, concurrent edit
preservation, Python-free profile creation, unknown-proxy/support gates,
byte-identical UTF-16 owner INI update, exact installed receipt hashes, incomplete
or modified package rejection, exact manifest identity/path/count validation,
and a real locked late uninstall file with full hash-verified restoration.
Transcripts are `E:\Source\milestone-{ux,install}-20260919-{ps51,ps7}.log`;
`E:\Source\milestone-build-20260919.log` records the native build. These tests
execute synthetic readers only; installer/package fixtures never load the real
DLL or execute the real input helper.

Local deployment completed on 2026-09-19 from package/source **3545810f**.
See [the deployment receipt](DEPLOYMENT-2026-09-19.md) for exact artifact,
backup and owner-state hashes, player entry point and untested runtime checks.
