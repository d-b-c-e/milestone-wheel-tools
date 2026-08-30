// wheelprobe - print a DirectInput device's live state, one line per sample.
//
// WHY THIS EXISTS AS A SEPARATE EXE
// The setup tool needs to see which physical button the user just pressed, on
// a base with 128 of them. PowerShell can enumerate DirectInput devices, but
// reading their state needs c_dfDIJoystick2, and dinput8.dll only exports
// GetdfDIJoystick - the 32-button format. Building a 164-entry DIDATAFORMAT by
// hand in PowerShell to reach buttons 33+ is far worse than a small exe that
// links the real thing.
//
// Output is line-based so any language can drive it:
//   DEVICES                      list attached controllers and exit
//   <productkey> [seconds]       stream that device's state; 0/omitted = until killed
//
// Stream format, one line per change (and a heartbeat every second):
//   AX <x> <y> <z> <rx> <ry> <rz> <s0> <s1>        raw, in the device's range
//   BTN <n>                                        button n pressed (1-based)
//   POV <degrees|-1>
//
// Runs until killed, or for [seconds] if given. Deliberately NOT keyed on
// stdin: a parent that redirects stdin from nul would make it exit instantly.

#define DIRECTINPUT_VERSION 0x0800
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dinput.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>

static LPDIRECTINPUT8 g_di = nullptr;
static LPDIRECTINPUTDEVICE8 g_dev = nullptr;
static DWORD g_wantKey = 0;
static GUID g_wantGuid{};
static char g_wantName[256] = "";

static BOOL CALLBACK enumList(LPCDIDEVICEINSTANCE inst, LPVOID)
{
    DWORD key = inst->guidProduct.Data1;
    int t = inst->dwDevType & 0xFF;
    const char *tn = t == 0x14 ? "JOYSTICK" : t == 0x15 ? "GAMEPAD"
                   : t == 0x16 ? "DRIVING"  : t == 0x18 ? "1STPERSON" : "OTHER";
    // key | type | ffb | name
    printf("DEV %08lx %s %d %s\n", (unsigned long)key, tn,
           (inst->dwDevType & DIDEVTYPE_HID) ? 1 : 0, inst->tszProductName);
    return DIENUM_CONTINUE;
}

static BOOL CALLBACK enumFind(LPCDIDEVICEINSTANCE inst, LPVOID)
{
    if (inst->guidProduct.Data1 != g_wantKey)
        return DIENUM_CONTINUE;
    g_wantGuid = inst->guidInstance;
    strncpy(g_wantName, inst->tszProductName, sizeof g_wantName - 1);
    return DIENUM_STOP;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, nullptr, _IOLBF, 0);          // line buffered: the parent reads live
    if (FAILED(DirectInput8Create(GetModuleHandleA(nullptr), DIRECTINPUT_VERSION,
                                  IID_IDirectInput8, (void **)&g_di, nullptr))) {
        printf("ERR cannot create DirectInput\n");
        return 1;
    }

    if (argc < 2 || _stricmp(argv[1], "DEVICES") == 0) {
        g_di->EnumDevices(DI8DEVCLASS_GAMECTRL, enumList, nullptr, DIEDFL_ATTACHEDONLY);
        printf("END\n");
        return 0;
    }

    g_wantKey = (DWORD)strtoul(argv[1], nullptr, 16);
    g_di->EnumDevices(DI8DEVCLASS_GAMECTRL, enumFind, nullptr, DIEDFL_ATTACHEDONLY);
    if (g_wantGuid == GUID{}) { printf("ERR device %08lx not attached\n", (unsigned long)g_wantKey); return 2; }

    if (FAILED(g_di->CreateDevice(g_wantGuid, &g_dev, nullptr))) { printf("ERR CreateDevice\n"); return 3; }
    // c_dfDIJoystick2 is the whole point: 128 buttons, 8 axes.
    if (FAILED(g_dev->SetDataFormat(&c_dfDIJoystick2))) { printf("ERR SetDataFormat\n"); return 4; }
    g_dev->SetCooperativeLevel(GetConsoleWindow(), DISCL_BACKGROUND | DISCL_NONEXCLUSIVE);
    g_dev->Acquire();
    printf("OK %s\n", g_wantName);

    DIJOYSTATE2 prev{}, cur{};
    bool first = true;
    DWORD lastBeat = 0;
    const DWORD limitMs = (argc > 2) ? (DWORD)(atof(argv[2]) * 1000.0) : 0;
    const DWORD started = GetTickCount();
    for (;;) {
        if (limitMs && GetTickCount() - started >= limitMs) break;
        if (FAILED(g_dev->Poll())) { g_dev->Acquire(); Sleep(20); continue; }
        if (FAILED(g_dev->GetDeviceState(sizeof cur, &cur))) { g_dev->Acquire(); Sleep(20); continue; }

        DWORD now = GetTickCount();
        bool beat = now - lastBeat > 1000;
        if (first || beat || memcmp(cur.rglSlider, prev.rglSlider, sizeof cur.rglSlider) ||
            cur.lX != prev.lX || cur.lY != prev.lY || cur.lZ != prev.lZ ||
            cur.lRx != prev.lRx || cur.lRy != prev.lRy || cur.lRz != prev.lRz) {
            printf("AX %ld %ld %ld %ld %ld %ld %ld %ld\n", cur.lX, cur.lY, cur.lZ,
                   cur.lRx, cur.lRy, cur.lRz, cur.rglSlider[0], cur.rglSlider[1]);
            lastBeat = now;
        }
        for (int i = 0; i < 128; ++i) {
            bool down = (cur.rgbButtons[i] & 0x80) != 0;
            bool was = (prev.rgbButtons[i] & 0x80) != 0;
            if (down && !was) printf("BTN %d\n", i + 1);       // 1-based, matches joy.cpl
        }
        if (cur.rgdwPOV[0] != prev.rgdwPOV[0]) {
            DWORD p = cur.rgdwPOV[0];
            printf("POV %d\n", (p == 0xFFFF || LOWORD(p) == 0xFFFF) ? -1 : (int)(p / 100));
        }
        prev = cur;
        first = false;
        Sleep(8);
    }
    if (g_dev) { g_dev->Unacquire(); g_dev->Release(); }
    if (g_di) g_di->Release();
    return 0;
}
