// DmorphHelper: a small companion to VanillaHelpers for DMorph (OctoWoW, WoW
// 1.12.1 build 5875). It lets the addon change two things VanillaHelpers
// can't, only on your own screen:
//
//   - the enchant glow on a weapon (the enchant IDs in a visible item slot)
//   - a player's skin colour, face, hair style, hair colour and facial hair
//     (PLAYER_BYTES and PLAYER_BYTES_2)
//   - a player's size (OBJECT_FIELD_SCALE_X, a float: what Enlarge spells change)
//   - a player's race byte (UNIT_FIELD_BYTES_0): your own race while chat is
//     read during a race morph, so the game understands your languages
//
// Lua functions (registered when the game loads its own):
//   DmorphHelper_Version()                                   -> version
//   DmorphHelper_GetItemEnchants(unit, slot)                 -> permanent, temporary
//   DmorphHelper_SetItemEnchants(unit, slot, permanent, temporary)
//   DmorphHelper_GetLook(unit)                               -> skin, face, hairStyle, hairColour, facialHair
//   DmorphHelper_SetLook(unit, skin, face, hairStyle, hairColour, facialHair)
//   DmorphHelper_GetScale(unit)                              -> scale (1 = normal size)
//   DmorphHelper_SetScale(unit, scale)                       (0.1 to 10)
//   DmorphHelper_GetRace(unit)                               -> race
//   DmorphHelper_SetRace(unit, race)                         (no rebuild)
//   DmorphHelper_SetOwnRace(race)                            (0 = off; see Race morphs)
//   DmorphHelper_Rebuild(unit)
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

#define HELPER_VERSION 6

// Game functions, build 5875 (from VanillaHelpers' Offsets.h).
#define FUN_INVALID_FUNCTION_PTR_CHECK 0x42A320
#define FUN_LOAD_SCRIPT_FUNCTIONS 0x490250
#define FUN_REGISTER_LUA_FUNCTION 0x704120
#define FUN_GET_GUID_FROM_NAME 0x515970
#define FUN_CLNT_OBJ_MGR_OBJECT_PTR 0x468460
#define FUN_CLNT_OBJ_MGR_GET_ACTIVE_PLAYER 0x468550
#define FUN_CGUNIT_C_CAN_ASSIST 0x6066F0
#define FUN_CGUNIT_C_UPDATE_DISPLAY_INFO 0x60ABE0
// The handler the game registers (0x5AB650) for SMSG_MESSAGECHAT (0x96).
#define FUN_CHAT_MESSAGE_HANDLER 0x49D560
// Builds every faction's base reputation from your race (no arguments).
#define FUN_BUILD_BASE_REPUTATION 0x4D5430
// SkillRaceClassInfo for (race, class, skill), fastcall + 1 stack arg; NULL if none.
#define FUN_SKILL_RACE_CLASS_INFO 0x6DDF90
#define LUA_IS_NUMBER 0x6F34D0
#define LUA_TO_NUMBER 0x6F3620
#define LUA_PUSH_NUMBER 0x6F3810
#define LUA_IS_STRING 0x6F3510
#define LUA_TO_STRING 0x6F3690
#define LUA_ERROR 0x6F4940
#define HIGHEST_ADDRESS 0x704CD0

// Descriptor fields, as indexes into a unit's uint32 field array.
#define OBJECT_FIELD_SCALE_X 0x4 // a float
#define UNIT_FIELD_BYTES_0 0x24 // race, class, gender, power type (one byte each)

// In the unit object itself (build 5875, from 0x614640 and the per-frame
// size animation at 0x614a90): the size the model is drawn at, and when a
// size animation started (0 = none; it eases from +0xA4 to the field over 2 s).
#define UNIT_SHOWN_SCALE 0x90
#define UNIT_SCALE_ANIM_START 0xA0
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
    float scale = (float)v;
    uint32_t *f = Fields(unit);
    memcpy(f + OBJECT_FIELD_SCALE_X, &scale, sizeof scale);
    // The field is what the camera reads; the model is drawn at the unit's
    // own copy, which the game only animates towards the field when the
    // server changes it. So set that copy too, and stop any such animation,
    // as the game's own "size at once" code at 0x614640 does.
    memcpy((char *)unit + UNIT_SHOWN_SCALE, &scale, sizeof scale);
    *(uint32_t *)((char *)unit + UNIT_SCALE_ANIM_START) = 0;
    return 0;
}

// Race morphs. VanillaHelpers writes the morph's race into your race byte,
// and the game needs it there: it builds and textures your model from it
// (skin, face, hair, helmets), sometimes well after the model was built. But
// the game also reads it to decide which languages you understand, and
// garbles your own and your faction's chat when it thinks you're another
// race. So the byte keeps the morph's race, and only while the game handles
// an incoming chat message (SMSG_MESSAGECHAT), or works out your base
// reputations (BuildReputation_h, below), does it hold your own
// race (DmorphHelper_SetOwnRace). The addon swaps it the same way, without a
// rebuild, while the flight map, spellbook or reputation list is open
// (DmorphHelper_SetRace).
typedef int(GAME_FASTCALL *MessageHandler_t)(void *param, uint32_t msgId, uint32_t time, void *msg);
static MessageHandler_t ChatHandler_o = NULL;
static uint32_t g_ownRace = 0;
static uint64_t g_ownGuid = 0; // the character g_ownRace is for
typedef void (*BuildReputation_t)(void);
static BuildReputation_t BuildReputation_o = NULL;
typedef void *(GAME_FASTCALL *SkillRaceClass_t)(uint32_t race, uint32_t cls, uint32_t skill);
static SkillRaceClass_t SkillRaceClass_o = NULL;
static uint32_t g_builtRace = 0; // the race the base reputations were built with

static void *Me(void) {
    uint64_t guid = GetActivePlayer();
    return guid ? ObjectPtr(TYPEMASK_PLAYER, NULL, guid, 0) : NULL;
}

static void WriteRace(void *unit, uint32_t race) {
    uint32_t *f = Fields(unit);
    f[UNIT_FIELD_BYTES_0] = (f[UNIT_FIELD_BYTES_0] & 0xFFFFFF00u) | race;
}

// Your own race, if the addon has said it for the character you're on now
// (after logging on to another one it says it again).
static uint32_t OwnRace(void) {
    return g_ownRace && GetActivePlayer() == g_ownGuid ? g_ownRace : 0;
}

static int GAME_FASTCALL ChatHandler_h(void *param, uint32_t msgId, uint32_t time, void *msg) {
    uint32_t own = OwnRace();
    void *me = own ? Me() : NULL;
    if (!me) {
        return ChatHandler_o(param, msgId, time, msg);
    }
    uint32_t race = Fields(me)[UNIT_FIELD_BYTES_0] & 0xFF;
    WriteRace(me, own);
    int result = ChatHandler_o(param, msgId, time, msg);
    // The handler may have run addons' Lua that changed things: look again.
    me = Me();
    if (me) {
        WriteRace(me, race);
    }
    return result;
}

// How an NPC feels about you (name colour, talking to it, the bank) comes
// from your standing with its faction: what the server sent plus a base
// value per faction that depends on your race. The game works the base
// values out from the race byte once (BuildReputation, on entering the world
// and when the server sends your reputations) and keeps them. Built with an
// Alliance morph's race, Horde NPCs stay hostile until the next build. So
// every build uses your own race, and DmorphHelper_SetOwnRace builds again
// when the last one used another race.
static void BuildReputation_h(void) {
    void *me = Me();
    if (!me) {
        BuildReputation_o();
        return;
    }
    uint32_t race = Fields(me)[UNIT_FIELD_BYTES_0] & 0xFF;
    uint32_t own = OwnRace();
    if (!own) {
        own = race;
    }
    WriteRace(me, own);
    BuildReputation_o();
    me = Me();
    if (me) {
        WriteRace(me, race);
    }
    g_builtRace = own;
}

// Your skills (weapon skills, professions, languages) and how the spellbook
// sorts your spells come from a table per race and class, which the game
// looks up with your race byte. With a race morph's race there it finds no
// row for some of your skills, and the skill list (GetSkillLineInfo) reads
// the missing row and crashes. So a lookup with the morph's race in your
// byte is made with your own race.
static void *GAME_FASTCALL SkillRaceClass_h(uint32_t race, uint32_t cls, uint32_t skill) {
    uint32_t own = OwnRace();
    if (own && race != own) {
        void *me = Me();
        if (me && race == (Fields(me)[UNIT_FIELD_BYTES_0] & 0xFF)) {
            race = own;
        }
    }
    return SkillRaceClass_o(race, cls, skill);
}

static const char *RACE_USAGE = "Usage: DmorphHelper_GetRace(unit)";
static const char *SET_RACE_USAGE = "Usage: DmorphHelper_SetRace(unit, race 1-20)";
static const char *OWN_RACE_USAGE = "Usage: DmorphHelper_SetOwnRace(race 0-20)";
static const char *REBUILD_USAGE = "Usage: DmorphHelper_Rebuild(unit)";

static int GAME_FASTCALL Script_GetRace(void *L) {
    void *unit = PlayerArg(L, 1, RACE_USAGE);
    LuaPushNumber(L, Fields(unit)[UNIT_FIELD_BYTES_0] & 0xFF);
    return 1;
}

// Writes a race byte without rebuilding the model.
static int GAME_FASTCALL Script_SetRace(void *L) {
    void *unit = PlayerArg(L, 1, SET_RACE_USAGE);
    WriteRace(unit, NumberArg(L, 2, 1, 20, SET_RACE_USAGE));
    return 0;
}

// Your own race, for chat and reactions during a race morph; 0 turns it off.
static int GAME_FASTCALL Script_SetOwnRace(void *L) {
    uint32_t race = NumberArg(L, 1, 0, 20, OWN_RACE_USAGE);
    if (!ChatHandler_o || !BuildReputation_o) {
        LuaError(L, "DmorphHelper couldn't hook the game's chat or reputation code.");
        return 0;
    }
    g_ownRace = race;
    g_ownGuid = GetActivePlayer();
    if (race && race != g_builtRace && Me()) {
        BuildReputation_h();
    }
    return 0;
}

// Rebuilds a model (for a change the game made without rebuilding it).
static int GAME_FASTCALL Script_Rebuild(void *L) {
    Reload(PlayerArg(L, 1, REBUILD_USAGE));
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
    RegisterFunction("DmorphHelper_GetRace", (uintptr_t)&Script_GetRace);
    RegisterFunction("DmorphHelper_SetRace", (uintptr_t)&Script_SetRace);
    RegisterFunction("DmorphHelper_SetOwnRace", (uintptr_t)&Script_SetOwnRace);
    RegisterFunction("DmorphHelper_Rebuild", (uintptr_t)&Script_Rebuild);
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
    // Without them DmorphHelper_SetOwnRace says so; everything else still works.
    if (MH_CreateHook((LPVOID)FUN_CHAT_MESSAGE_HANDLER, (LPVOID)&ChatHandler_h,
                      (LPVOID *)&ChatHandler_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_CHAT_MESSAGE_HANDLER) != MH_OK) {
        ChatHandler_o = NULL;
    }
    if (MH_CreateHook((LPVOID)FUN_BUILD_BASE_REPUTATION, (LPVOID)&BuildReputation_h,
                      (LPVOID *)&BuildReputation_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_BUILD_BASE_REPUTATION) != MH_OK) {
        BuildReputation_o = NULL;
    }
    if (MH_CreateHook((LPVOID)FUN_SKILL_RACE_CLASS_INFO, (LPVOID)&SkillRaceClass_h,
                      (LPVOID *)&SkillRaceClass_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_SKILL_RACE_CLASS_INFO) != MH_OK) {
        SkillRaceClass_o = NULL;
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
