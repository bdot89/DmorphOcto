// DmorphHelper: a small companion to VanillaHelpers for DMorph (OctoWoW, WoW
// 1.12.1 build 5875). It lets the addon change two things VanillaHelpers
// can't, only on your own screen:
//
//   - the enchant glow on a weapon (the enchant IDs in a visible item slot)
//   - a player's skin colour, face, hair style, hair colour and facial hair
//     (PLAYER_BYTES and PLAYER_BYTES_2)
//   - a player's size (OBJECT_FIELD_SCALE_X, a float: what Enlarge spells change)
//
// Lua functions (registered when the game loads its own):
//   DmorphHelper_Version()                                   -> version
//   DmorphHelper_GetItemEnchants(unit, slot)                 -> permanent, temporary
//   DmorphHelper_SetItemEnchants(unit, slot, permanent, temporary)
//   DmorphHelper_GetLook(unit)                               -> skin, face, hairStyle, hairColour, facialHair
//   DmorphHelper_SetLook(unit, skin, face, hairStyle, hairColour, facialHair)
//   DmorphHelper_GetScale(unit)                              -> scale (1 = normal size)
//   DmorphHelper_SetScale(unit, scale)                       (0.1 to 10)
// unit is a unit token for a player you could help ("player", "target", ...);
// slot is an inventory slot, 1-19. The functions only write the values: the
// addon keeps what it wants and puts it back after the server resends them.
//
// Loaded by VanillaFixes from dlls.txt. It needs VanillaHelpers: the game only
// calls Lua functions outside WoW.exe because VanillaHelpers switches that
// check off. The addresses below are VanillaHelpers' own, so the helper only
// starts once it sees VanillaHelpers' hooks at two of them (the proof that
// this exe and VanillaHelpers agree with it); otherwise, or if VanillaHelpers
// isn't loaded within a minute of the game starting, it does nothing.

#include <windows.h>
#include <stdint.h>
#include <string.h>

#include "MinHook.h"

#define GAME_FASTCALL __attribute__((fastcall))
#define GAME_THISCALL __attribute__((thiscall))

#define HELPER_VERSION 2

// Game functions, build 5875 (from VanillaHelpers' Offsets.h).
#define FUN_INVALID_FUNCTION_PTR_CHECK 0x42A320
#define FUN_LOAD_SCRIPT_FUNCTIONS 0x490250
#define FUN_REGISTER_LUA_FUNCTION 0x704120
#define FUN_GET_GUID_FROM_NAME 0x515970
#define FUN_CLNT_OBJ_MGR_OBJECT_PTR 0x468460
#define FUN_CLNT_OBJ_MGR_GET_ACTIVE_PLAYER 0x468550
#define FUN_CGUNIT_C_CAN_ASSIST 0x6066F0
#define FUN_CGUNIT_C_UPDATE_DISPLAY_INFO 0x60ABE0
#define LUA_IS_NUMBER 0x6F34D0
#define LUA_TO_NUMBER 0x6F3620
#define LUA_PUSH_NUMBER 0x6F3810
#define LUA_IS_STRING 0x6F3510
#define LUA_TO_STRING 0x6F3690
#define LUA_ERROR 0x6F4940
#define HIGHEST_ADDRESS 0x704CD0

// Descriptor fields, as indexes into a unit's uint32 field array.
#define OBJECT_FIELD_SCALE_X 0x4 // a float
#define UNIT_FIELD_DISPLAYID 0x83
#define PLAYER_BYTES 0xC1
#define PLAYER_BYTES_2 0xC2
#define PLAYER_VISIBLE_ITEM_1_0 0x104 // item ID, then 7 enchant IDs (permanent, temporary, ...)
#define VISIBLE_ITEM_STRIDE 0xC

#define TYPEMASK_PLAYER 0x10
// Any other display: switching to it and back makes the game rebuild the
// model, which is how VanillaHelpers redraws a unit too.
#define RELOAD_DISPLAY 15435

typedef void(GAME_FASTCALL *LoadScriptFunctions_t)(void);
typedef void(GAME_FASTCALL *RegisterFunction_t)(const char *name, uintptr_t func);
typedef uint64_t(GAME_FASTCALL *GetGUIDFromName_t)(const char *name);
typedef void *(GAME_FASTCALL *ObjectPtr_t)(uint32_t typeMask, const char *debug, uint64_t guid, int debugCode);
typedef uint64_t(GAME_FASTCALL *GetActivePlayer_t)(void);
typedef uint8_t(GAME_THISCALL *CanAssist_t)(void *unit, void *other);
typedef void(GAME_THISCALL *UpdateDisplayInfo_t)(void *unit);
typedef uint8_t(GAME_FASTCALL *LuaIsNumber_t)(void *L, int index);
typedef double(GAME_FASTCALL *LuaToNumber_t)(void *L, int index);
typedef void(GAME_FASTCALL *LuaPushNumber_t)(void *L, double value);
typedef uint8_t(GAME_FASTCALL *LuaIsString_t)(void *L, int index);
typedef const char *(GAME_FASTCALL *LuaToString_t)(void *L, int index);
typedef void(__cdecl *LuaError_t)(void *L, const char *message);

#define RegisterFunction ((RegisterFunction_t)FUN_REGISTER_LUA_FUNCTION)
#define GetGUIDFromName ((GetGUIDFromName_t)FUN_GET_GUID_FROM_NAME)
#define ObjectPtr ((ObjectPtr_t)FUN_CLNT_OBJ_MGR_OBJECT_PTR)
#define GetActivePlayer ((GetActivePlayer_t)FUN_CLNT_OBJ_MGR_GET_ACTIVE_PLAYER)
#define CanAssist ((CanAssist_t)FUN_CGUNIT_C_CAN_ASSIST)
#define UpdateDisplayInfo ((UpdateDisplayInfo_t)FUN_CGUNIT_C_UPDATE_DISPLAY_INFO)
#define LuaIsNumber ((LuaIsNumber_t)LUA_IS_NUMBER)
#define LuaToNumber ((LuaToNumber_t)LUA_TO_NUMBER)
#define LuaPushNumber ((LuaPushNumber_t)LUA_PUSH_NUMBER)
#define LuaIsString ((LuaIsString_t)LUA_IS_STRING)
#define LuaToString ((LuaToString_t)LUA_TO_STRING)
#define LuaError ((LuaError_t)LUA_ERROR)

static LoadScriptFunctions_t LoadScriptFunctions_o = NULL;

static uint32_t *Fields(void *unit) {
    return *(uint32_t **)((char *)unit + 0x8);
}

// The player a unit token names, if it's you or someone you could help.
// Raises a Lua error (which doesn't return) otherwise.
static void *PlayerArg(void *L, int index, const char *usage) {
    if (!LuaIsString(L, index)) {
        LuaError(L, usage);
        return NULL;
    }
    uint64_t guid = GetGUIDFromName(LuaToString(L, index));
    void *unit = guid ? ObjectPtr(TYPEMASK_PLAYER, NULL, guid, 0) : NULL;
    if (!unit) {
        LuaError(L, "Unit not found.");
        return NULL;
    }
    void *me = ObjectPtr(TYPEMASK_PLAYER, NULL, GetActivePlayer(), 0);
    if (unit != me && !(me && CanAssist(me, unit))) {
        LuaError(L, "Unit is not friendly.");
        return NULL;
    }
    return unit;
}

// A whole number from min to max at index; raises a Lua error otherwise.
static uint32_t NumberArg(void *L, int index, double min, double max, const char *usage) {
    if (!LuaIsNumber(L, index)) {
        LuaError(L, usage);
        return 0;
    }
    double v = LuaToNumber(L, index);
    if (v < min || v > max || v != (double)(uint32_t)v) {
        LuaError(L, usage);
        return 0;
    }
    return (uint32_t)v;
}

static void Reload(void *unit) {
    uint32_t *f = Fields(unit);
    uint32_t display = f[UNIT_FIELD_DISPLAYID];
    f[UNIT_FIELD_DISPLAYID] = RELOAD_DISPLAY;
    UpdateDisplayInfo(unit);
    f[UNIT_FIELD_DISPLAYID] = display;
    UpdateDisplayInfo(unit);
}

static int GAME_FASTCALL Script_Version(void *L) {
    LuaPushNumber(L, HELPER_VERSION);
    return 1;
}

static const char *ENCHANTS_USAGE = "Usage: DmorphHelper_GetItemEnchants(unit, slot 1-19)";
static const char *SET_ENCHANTS_USAGE = "Usage: DmorphHelper_SetItemEnchants(unit, slot 1-19, permanent, temporary)";

static int GAME_FASTCALL Script_GetItemEnchants(void *L) {
    void *unit = PlayerArg(L, 1, ENCHANTS_USAGE);
    uint32_t slot = NumberArg(L, 2, 1, 19, ENCHANTS_USAGE);
    uint32_t *f = Fields(unit) + PLAYER_VISIBLE_ITEM_1_0 + (slot - 1) * VISIBLE_ITEM_STRIDE;
    LuaPushNumber(L, f[1]);
    LuaPushNumber(L, f[2]);
    return 2;
}

static int GAME_FASTCALL Script_SetItemEnchants(void *L) {
    void *unit = PlayerArg(L, 1, SET_ENCHANTS_USAGE);
    uint32_t slot = NumberArg(L, 2, 1, 19, SET_ENCHANTS_USAGE);
    uint32_t permanent = NumberArg(L, 3, 0, 1000000, SET_ENCHANTS_USAGE);
    uint32_t temporary = NumberArg(L, 4, 0, 1000000, SET_ENCHANTS_USAGE);
    uint32_t *f = Fields(unit) + PLAYER_VISIBLE_ITEM_1_0 + (slot - 1) * VISIBLE_ITEM_STRIDE;
    if (f[1] != permanent || f[2] != temporary) {
        f[1] = permanent;
        f[2] = temporary;
        Reload(unit);
    }
    return 0;
}

static const char *LOOK_USAGE = "Usage: DmorphHelper_GetLook(unit)";
static const char *SET_LOOK_USAGE = "Usage: DmorphHelper_SetLook(unit, skin, face, hairStyle, hairColour, facialHair)";

static int GAME_FASTCALL Script_GetLook(void *L) {
    void *unit = PlayerArg(L, 1, LOOK_USAGE);
    uint32_t *f = Fields(unit);
    uint32_t bytes = f[PLAYER_BYTES];
    LuaPushNumber(L, bytes & 0xFF);
    LuaPushNumber(L, (bytes >> 8) & 0xFF);
    LuaPushNumber(L, (bytes >> 16) & 0xFF);
    LuaPushNumber(L, (bytes >> 24) & 0xFF);
    LuaPushNumber(L, f[PLAYER_BYTES_2] & 0xFF);
    return 5;
}

static int GAME_FASTCALL Script_SetLook(void *L) {
    void *unit = PlayerArg(L, 1, SET_LOOK_USAGE);
    uint32_t skin = NumberArg(L, 2, 0, 255, SET_LOOK_USAGE);
    uint32_t face = NumberArg(L, 3, 0, 255, SET_LOOK_USAGE);
    uint32_t hairStyle = NumberArg(L, 4, 0, 255, SET_LOOK_USAGE);
    uint32_t hairColour = NumberArg(L, 5, 0, 255, SET_LOOK_USAGE);
    uint32_t facialHair = NumberArg(L, 6, 0, 255, SET_LOOK_USAGE);
    uint32_t *f = Fields(unit);
    uint32_t bytes = skin | (face << 8) | (hairStyle << 16) | (hairColour << 24);
    uint32_t bytes2 = (f[PLAYER_BYTES_2] & 0xFFFFFF00u) | facialHair;
    if (f[PLAYER_BYTES] != bytes || f[PLAYER_BYTES_2] != bytes2) {
        f[PLAYER_BYTES] = bytes;
        f[PLAYER_BYTES_2] = bytes2;
        Reload(unit);
    }
    return 0;
}

static const char *SCALE_USAGE = "Usage: DmorphHelper_GetScale(unit)";
static const char *SET_SCALE_USAGE = "Usage: DmorphHelper_SetScale(unit, scale 0.1-10)";

static int GAME_FASTCALL Script_GetScale(void *L) {
    void *unit = PlayerArg(L, 1, SCALE_USAGE);
    float scale;
    memcpy(&scale, Fields(unit) + OBJECT_FIELD_SCALE_X, sizeof scale);
    LuaPushNumber(L, scale);
    return 1;
}

static int GAME_FASTCALL Script_SetScale(void *L) {
    void *unit = PlayerArg(L, 1, SET_SCALE_USAGE);
    if (!LuaIsNumber(L, 2)) {
        LuaError(L, SET_SCALE_USAGE);
        return 0;
    }
    double v = LuaToNumber(L, 2);
    if (!(v >= 0.1 && v <= 10)) {
        LuaError(L, SET_SCALE_USAGE);
        return 0;
    }
    float scale = (float)v, current;
    uint32_t *f = Fields(unit);
    memcpy(&current, f + OBJECT_FIELD_SCALE_X, sizeof current);
    if (current != scale) {
        memcpy(f + OBJECT_FIELD_SCALE_X, &scale, sizeof scale);
        Reload(unit);
    }
    return 0;
}

static void GAME_FASTCALL LoadScriptFunctions_h(void) {
    LoadScriptFunctions_o();
    RegisterFunction("DmorphHelper_Version", (uintptr_t)&Script_Version);
    RegisterFunction("DmorphHelper_GetItemEnchants", (uintptr_t)&Script_GetItemEnchants);
    RegisterFunction("DmorphHelper_SetItemEnchants", (uintptr_t)&Script_SetItemEnchants);
    RegisterFunction("DmorphHelper_GetLook", (uintptr_t)&Script_GetLook);
    RegisterFunction("DmorphHelper_SetLook", (uintptr_t)&Script_SetLook);
    RegisterFunction("DmorphHelper_GetScale", (uintptr_t)&Script_GetScale);
    RegisterFunction("DmorphHelper_SetScale", (uintptr_t)&Script_SetScale);
}

// The game's own image must reach every address used here (a 1.12.1 exe).
static BOOL GameLooksRight(void) {
    HMODULE exe = GetModuleHandleA(NULL);
    if ((uintptr_t)exe != 0x400000) {
        return FALSE;
    }
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)exe;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((char *)exe + dos->e_lfanew);
    return 0x400000 + nt->OptionalHeader.SizeOfImage > HIGHEST_ADDRESS;
}

// Whether VanillaHelpers has hooked the game's check on Lua function
// addresses and its Lua function loader: a MinHook detour starts with a jump.
static BOOL IsJump(uintptr_t address) {
    uint8_t first = *(volatile uint8_t *)address;
    return first == 0xE9 || first == 0xEB;
}

static BOOL VanillaHelpersHooked(void) {
    return IsJump(FUN_INVALID_FUNCTION_PTR_CHECK) && IsJump(FUN_LOAD_SCRIPT_FUNCTIONS);
}

static void InstallHook(void) {
    if (MH_Initialize() != MH_OK) {
        return;
    }
    if (MH_CreateHook((LPVOID)FUN_LOAD_SCRIPT_FUNCTIONS, (LPVOID)&LoadScriptFunctions_h,
                      (LPVOID *)&LoadScriptFunctions_o) == MH_OK) {
        MH_EnableHook((LPVOID)FUN_LOAD_SCRIPT_FUNCTIONS);
    }
}

static BOOL Ready(void) {
    return GetModuleHandleA("VanillaHelpers.dll") && VanillaHelpersHooked();
}

// VanillaFixes loads the DLLs in dlls.txt one after another before the game
// runs. If VanillaHelpers comes later in the list, wait for it and its hooks
// (the game only loads its UI's functions well after starting).
static DWORD WINAPI WaitForVanillaHelpers(LPVOID unused) {
    (void)unused;
    for (int i = 0; i < 600; i++) {
        if (Ready()) {
            InstallHook();
            return 0;
        }
        Sleep(100);
    }
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        if (!GameLooksRight()) {
            return TRUE;
        }
        if (Ready()) {
            InstallHook();
        } else {
            HANDLE thread = CreateThread(NULL, 0, WaitForVanillaHelpers, NULL, 0, NULL);
            if (thread) {
                CloseHandle(thread);
            }
        }
    }
    // Never stop the game from starting: without the hook, DMorph just says
    // the helper isn't loaded.
    return TRUE;
}
