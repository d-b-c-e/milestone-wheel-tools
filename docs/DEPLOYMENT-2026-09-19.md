# Gravel local deployment — 2026-09-19

Version **0.2.0** was built, packaged, fixture-tested and installed at
**2026-09-19T19:14:58Z**. The installed package comes from source commit
**3545810f4fd33647ff19ab87ab02a9aec0afa47a**; the later documentation commit
records this receipt without changing the deployed code. No public release or
hosted CI was triggered.

## Player entry point

With Gravel closed, open:

`D:\Program Files (x86)\Steam\steamapps\common\Gravel\Wheel settings.bat`

The launcher opens the deployed external setup tool with exact game and INI
paths. A missing presentation preference starts in Simple. Go to Controls to
bind individual inputs, use Preview device input on demand, and Save mappings
and exit when ready. Preview measures the device, not game-final input. Run
Gravel's own calibration for endpoints/deadzones. FFB and cameras remain owned
by the game; this package does not add an F6 panel or camera mounts.

The owner's settings were retained: MOZA R12 profile `0006346e`, existing axis
and button bindings, telemetry On to **127.0.0.1:8000**, format **fh4**. Telemetry
changes made in setup affect the next game launch, not a running sender.

## Exact target and artifact

Only **Gravel**, Steam app **558260**, installed build **3477925**, was a verified
supported target. Other Milestone games remain unverified candidates and are
not accepted by the installer. The target was closed before, during and after
installation. No game process, real input helper or physical force output was
started by this work.

Runtime/setup target:

`D:\Program Files (x86)\Steam\steamapps\common\Gravel\gravel\Binaries\Win64`

Package (local only):

`E:\Source\milestone-wheel-tools-ux-20260916\artifacts\milestone-wheel-tools-0.2.0-3545810f.zip`

Fresh extraction used for both final fixture verification and actual install:

`E:\Source\milestone-wheel-tools-ux-20260916\artifacts\verified-extraction-3545810f`

| Artifact | SHA256 |
|---|---|
| ZIP | `c561eaec8ec1f1cf54af0af78a92e5d8e31a39f6d9f8daf3d2fa24d8c614b055` |
| Extracted package-manifest.json | `7b5aaca361eddc0c19272e7d0a0ae1d8b61ca9a5a1984cf5d4695e672befc87d` |
| Built / packaged / installed dinput8.dll | `4e74d46dcfe100c378de3778f3238d941102689bd9fff348b2cecd335b7e2c30` |
| Built / packaged / installed wheelprobe.exe | `4d9e94cc31f67f9644bfded1847b94810a9f24cbeba9cee01661ebb361c6883a` |
| Previous installed dinput8.dll, backed up | `35c7e87ccd575b2b238d053759141296f0ed35315017904ef7ec5a4a17d09ab5` |
| Installed milestone_install.json | `3ccb46872d28c7d12c907de244a9bbf414dc3a25c2792f60426f5fd77a990a01` |

Every one of the **14 owned installed files** was reread and matched against
its receipt. The package manifest maps all distributed files to exact hashes.
Runtime source, telemetry semantics and the vendored **toolkit v0.8.0** pin
were unchanged; the two binaries were rebuilt from that source.

## Owner state and backups

All hashes below are equal for the original file, backup and post-install file.
No presentation preference existed before deployment and none was created.

| Preserved file | SHA256 before = backup = after |
|---|---|
| milestone_mod.ini | `2057122eb5e9330e11ae4d8d921a7908f4efe8b715e26a36bf0d159ed623bb5a` |
| Complete WheelConfig.ini | `f7eb7f4aa44f164d11bbf333920016b58f79504880ab1528c0e6d6510049a1fe` |
| LocalAppData/Gravel/Saved/SaveGames/settings.sav | `1ad6d8f0dfafbacab887790f5c1109a4d92d5b95a923b584f2261a4755e1d9fb` |

Both backup folders are beneath the runtime target's `DBCE-Wheel-Backups`:

- **20260919-141450-2f6780**: installer transaction copies and manifest.
  Manifest SHA256 `620b71fa7b9054d450ee5bdfc2f865aad3dd8fa58ffd181d37cf4c7a8cf5eded`.
- **owner-state-20260919-141449-e51d8e**: independent pre-install INI,
  WheelConfig, settings.sav and old DLL copies. Owner-state manifest SHA256
  `a81e9abe28d3cef766aae1b09cd0cee01b7777a66d92a3cf45112eb89f0cfb63`.

The installer backup manifest records each original target and copy path.
Restore only while Gravel is closed. Normal uninstall also keeps dated backups,
personal INIs, wheel bindings and game calibration. It checks receipt hashes,
backs up planned removals, and restores earlier removals if a later file is locked.
No owner saves or proprietary game files are in Git or the package.

## Validation and limits

- **140 UX/migration fixtures and 81 install/package fixtures passed** on both
  Windows PowerShell **5.1.26100.9444** and PowerShell **7.6.5**.
- The freshly extracted ZIP passed the **81 installer fixtures** independently;
  missing/modified payloads, wrong manifest identity/path/count, partial install,
  real late-file removal lock, concurrent edit and game-start guard are covered.
- **GCC 16.2.0**, MinGW-w64: both binaries built; x64 PE, six proxy exports and
  absence of unbundled compiler-runtime imports verified. One existing safe
  truncated-display-name warning remains in the helper; no native code changed.
- Independent review closed package-integrity and uninstall-rollback findings
  before the deployment. PowerShell parsing and `git diff --check` passed.
- README, QUICKSTART, existing CLAUDE working notes and the UX placement inventory
  were reconciled. AGENTS.md and CHANGELOG.md were absent; no empty substitutes
  were created. See `UX-OVERNIGHT-2026-09-16.md` for the guidance hash and exact
  endpoint/centre/deadzone adapter limitation.

Logs: `E:\Source\milestone-{ux,install}-20260919-{ps51,ps7}.log`,
`E:\Source\milestone-package-extracted-20260919.log`,
`E:\Source\milestone-build-20260919.log`, and
`E:\Source\milestone-deploy-20260919.log`.
The machine-readable receipt is
`E:\Source\milestone-wheel-tools-ux-20260916\artifacts\deployment-2026-09-19.json`.

Still untested on this build: physical capture and real Esc/console redraw,
720p/4K presentation, hot unplug, combined analog/button handbrake in Gravel,
first drive, actual telemetry delivery and game-owned force/camera behavior.
Installation and offline fixtures are not claims that those runtime checks passed.
