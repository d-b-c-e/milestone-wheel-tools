# Why old games refuse a direct-drive wheel

DirectInput assigns every HID game controller a `dwDevType`. A joystick
(usage page 1, usage 4) with **six or more axes** is classified as
`DI8DEVTYPE_1STPERSON` subtype `SIXDOF` (`0x18`) — the six-degrees-of-freedom
category originally meant for things like the SpaceOrb.

A MOZA R12 exposes 8 axes and 128 buttons:

```
key=0006346e  type=0x18  sub=3  FFB=True  usage=1/4  "MOZA R12 Base"
AXES = 8   BUTTONS = 128   POVs = 1
```

So every game is told it is a 6-DOF controller, not a wheel. A Logitech G29
has 4 axes, types as `JOYSTICK` (`0x14`), and works. Any title that decides
"is this a wheel" from `dwDevType` will offer the R12 as **neither wheel nor
gamepad**, and one that has to pick an input category (Gravel does) will
oscillate between keyboard and controller forever.

This cannot be fixed from the wheel side. Pit House cannot reduce the axis
count; the base always exposes all eight.

## The fix

A `dinput8.dll` proxy that rewrites `dwDevType` to `DI8DEVTYPE_DRIVING` in the
two places a game can read it:

- the `DIDEVICEINSTANCE` handed to the game's `EnumDevices` callback
- the `DIDEVCAPS` returned by `IDirectInputDevice8::GetCapabilities`

Only the type byte and subtype change; axes, buttons and force feedback pass
through untouched. Verified:

```
before:  type=0x18 1STPERSON  sub=3
after:   type=0x16 DRIVING    sub=4   axes=8 buttons=128
```

The same trick is used by `Tathanito/vjoyct3fix` for Crazy Taxi 3.

## Product key

The proxy targets one device by `guidProduct.Data1`, which DirectInput forms
as `(PID << 16) | VID`. MOZA R12 = VID `346E`, PID `0006` → `0006346e`. This
is the same number Milestone games use as the section name in
`WheelConfig.ini`, so one value configures both.

Find yours with `Get-PnpDevice -Class HIDClass | ? InstanceId -match 'VID_'`
or by enumerating DirectInput (`DirectInput8Create` + `EnumDevices(4)`).

## Verifying the type from PowerShell 7

.NET Core refuses to marshal a delegate through a COM interface, so the
enumeration callback must be passed as a raw function pointer via
`Marshal.GetFunctionPointerForDelegate`, and the `HINSTANCE` must be a real
`GetModuleHandleW(IntPtr.Zero)` — an empty string marshals to `E_INVALIDARG`.
