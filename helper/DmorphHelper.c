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
//   DmorphHelper_GetItemEnchants(unit, slot)                 -> permanent, temporary, item shown (v13)
//   DmorphHelper_SetItemEnchants(unit, slot, permanent, temporary)
//   DmorphHelper_GetLook(unit)                               -> skin, face, hairStyle, hairColour, facialHair
//   DmorphHelper_SetLook(unit, skin, face, hairStyle, hairColour, facialHair)
//   DmorphHelper_GetScale(unit)                              -> scale (1 = normal size)
//   DmorphHelper_SetScale(unit, scale)                       (0.1 to 10)
//   DmorphHelper_GetRace(unit)                               -> race
//   DmorphHelper_SetRace(unit, race)                         (no rebuild)
//   DmorphHelper_SetOwnRace(race)                            (0 = off; see Race morphs)
//   DmorphHelper_Rebuild(unit)
//   DmorphHelper_SetWeather(type, intensity)                 (0 clear, 1 rain, 2 snow, 3 sandstorm; 0-1)
//   DmorphHelper_ClearWeather()                              (the server's weather again)
//   DmorphHelper_GetWeather()                                -> type, intensity, yours (1/0), server type, intensity
//   DmorphHelper_SetTime(minutes)                            (0-1439 after midnight; -1: the real time)
//   DmorphHelper_GetTime()                                   -> minutes shown, yours (1/0), real minutes
//   DmorphHelper_SetVirtualItem(itemID, templateItemID, displayID) (an item only this PC has)
//   DmorphHelper_GetVirtualItem(itemID)                       -> templateItemID, displayID
//   DmorphHelper_SetAmmo(itemID)                             (your own ammo field; 0 = none)
//   DmorphHelper_GetAmmo()                                   -> ammo item ID
//   DmorphHelper_SetRiderPose(displayID, animation)          (v14; riders of that mount display: 120 stand, 97 sit; 91 usual)
//   DmorphHelper_GetRiderPose(displayID)                     -> animation, poses work (1/0)
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

#define HELPER_VERSION 14

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
// TSGrowableArray<uint32_t> { alloc, count, data, chunk } of the map cells a
// line crosses (mouse picking, line of sight), and its reserve function
// (thiscall: array, how many more, round up; ret 8).
#define WORLD_LINE_CELLS 0xC962C0
#define FUN_GROWABLE_ARRAY_RESERVE 0x4291F0
// The world's CWeather (NULL outside the world), its SetWeather (thiscall:
// type, intensity, blend; ret 0xC) and the weather sound loop (fastcall:
// sound ID; 0 stops it). The SMSG_WEATHER handler's calls return to RET_*.
#define WEATHER_OBJECT 0xC6326C
#define FUN_CWEATHER_SET_WEATHER 0x67BAF0
#define FUN_PLAY_WEATHER_SOUND 0x4586B0
#define RET_WEATHER_PACKET_SET 0x48FAAA
#define RET_WEATHER_PACKET_SOUND 0x48FAB2
// The game clock (CGameTime at 0xCE8538): minutes of the day (thiscall, ret
// int) and the day so far, 0-1 (thiscall, ret float). The world's lighting,
// sky and sun read them for each frame from the calls returning to RET_*.
#define GAME_CLOCK 0xCE8538
#define FUN_GAME_TIME_MINUTES 0x6424C0
#define FUN_GAME_TIME_DAY_PROGRESS 0x643A70
#define RET_WORLD_LIGHT_MINUTES 0x482BD6
#define RET_WORLD_LIGHT_PROGRESS 0x482BE2
#define RET_WORLD_SKY_MINUTES 0x483DE1
// The item cache's record for an item ID (thiscall: cache, item ID, GUID*,
// callback, user data, ask the server if missing; ret 0x14): ItemStats_C,
// whose display ID is at 0x18. VanillaHelpers' GetItemDisplayID uses it.
#define FUN_DBCACHE_ITEM_STATS_GET_RECORD 0x55BA30
#define ITEM_STATS_DISPLAY_ID 0x18
#define ITEM_STATS_SIZE 468
#define HIGHEST_ADDRESS 0xC962D0

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
// PLAYER_AMMO_ID (UNIT_END 0xBC + 0x40D), only in your own player's fields.
#define PLAYER_AMMO_ID 0x4C9

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

// Ammo. A ranged attack's missile comes from your ammo item (arrows, bullets)
// for bows, guns and crossbows; a character without ammo (a wand user in a
// bow morph) fires nothing. The field is only yours: the addon writes the
// ammo it wants and puts it back when the server resends the real one.
static void *Me(void);

static int GAME_FASTCALL Script_SetAmmo(void *L) {
    uint32_t item = NumberArg(L, 1, 0, 2147483647.0, "Usage: DmorphHelper_SetAmmo(itemID or 0)");
    void *me = Me();
    if (!me) {
        LuaError(L, "Unit not found.");
        return 0;
    }
    Fields(me)[PLAYER_AMMO_ID] = item;
    return 0;
}

static int GAME_FASTCALL Script_GetAmmo(void *L) {
    void *me = Me();
    LuaPushNumber(L, me ? Fields(me)[PLAYER_AMMO_ID] : 0);
    return 1;
}

static const char *ENCHANTS_USAGE = "Usage: DmorphHelper_GetItemEnchants(unit, slot 1-19)";
static const char *SET_ENCHANTS_USAGE = "Usage: DmorphHelper_SetItemEnchants(unit, slot 1-19, permanent, temporary)";

// v13 also returns the item the slot shows (PLAYER_VISIBLE_ITEM_<slot>_0): the
// addon checks its item morphs against it. VanillaHelpers keeps a morph against
// the server's writes (its CGObject_C::SetBlock hook), but some slots went back
// to the real item in combat (user report: head, waist, legs, feet, hands while
// tanking), and asking VanillaHelpers again changes nothing while it thinks
// the morph is still on.
static int GAME_FASTCALL Script_GetItemEnchants(void *L) {
    void *unit = PlayerArg(L, 1, ENCHANTS_USAGE);
    uint32_t slot = NumberArg(L, 2, 1, 19, ENCHANTS_USAGE);
    uint32_t *f = Fields(unit) + PLAYER_VISIBLE_ITEM_1_0 + (slot - 1) * VISIBLE_ITEM_STRIDE;
    LuaPushNumber(L, f[1]);
    LuaPushNumber(L, f[2]);
    LuaPushNumber(L, f[0]);
    return 3;
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

// Weather. The server sends it (SMSG_WEATHER: type, intensity, sound) and the
// handler hands it to the world's weather object, CWeather::SetWeather
// (0x67BAF0: type 0 clear, 1 rain, 2 snow, 3 sandstorm; intensity 0-1; then
// whether to blend into it), and plays the weather's sound loop (0x4586B0).
// A weather picked here replaces what the server sends while it's on, also
// on entering another zone; what the server sent is kept for when it's off.
// Only on your screen.
typedef void(GAME_THISCALL *SetWeather_t)(void *weather, uint32_t type, float intensity, uint32_t blend);
typedef void(GAME_FASTCALL *WeatherSound_t)(uint32_t sound);
static SetWeather_t SetWeather_o = NULL;
static WeatherSound_t WeatherSound_o = NULL;
static BOOL g_weatherOn = FALSE;
static uint32_t g_weatherType = 0, g_serverWeatherType = 0, g_serverWeatherSound = 0;
static float g_weatherIntensity = 0, g_serverWeatherIntensity = 0;

static void *WeatherObject(void) {
    return *(void **)WEATHER_OBJECT;
}

// The server's sounds for each weather: light below 40%, heavy from 70%.
static uint32_t WeatherSound(uint32_t type, float intensity) {
    static const uint32_t sounds[4][3] = {
        { 0, 0, 0 }, { 8533, 8534, 8535 }, { 8536, 8537, 8538 }, { 8556, 8557, 8558 },
    };
    return sounds[type][intensity < 0.4f ? 0 : intensity < 0.7f ? 1 : 2];
}

static void GAME_FASTCALL SetWeather_h(void *weather, void *edx, uint32_t type, float intensity, uint32_t blend) {
    (void)edx;
    if (__builtin_return_address(0) == (void *)RET_WEATHER_PACKET_SET) {
        g_serverWeatherType = type;
        g_serverWeatherIntensity = intensity;
        if (g_weatherOn) {
            type = g_weatherType;
            intensity = g_weatherIntensity;
        }
    }
    SetWeather_o(weather, type, intensity, blend);
}

static void GAME_FASTCALL WeatherSound_h(uint32_t sound) {
    if (__builtin_return_address(0) == (void *)RET_WEATHER_PACKET_SOUND) {
        g_serverWeatherSound = sound;
        if (g_weatherOn) {
            sound = WeatherSound(g_weatherType, g_weatherIntensity);
        }
    }
    WeatherSound_o(sound);
}

static const char *SET_WEATHER_USAGE = "Usage: DmorphHelper_SetWeather(type 0-3, intensity 0-1)";

static BOOL WeatherReady(void *L) {
    if (!SetWeather_o || !WeatherSound_o) {
        LuaError(L, "DmorphHelper couldn't hook the game's weather.");
        return FALSE;
    }
    if (!WeatherObject()) {
        LuaError(L, "There's no weather outside the world.");
        return FALSE;
    }
    return TRUE;
}

// Your weather, until DmorphHelper_ClearWeather.
static int GAME_FASTCALL Script_SetWeather(void *L) {
    uint32_t type = NumberArg(L, 1, 0, 3, SET_WEATHER_USAGE);
    if (!LuaIsNumber(L, 2)) {
        LuaError(L, SET_WEATHER_USAGE);
        return 0;
    }
    double v = LuaToNumber(L, 2);
    if (!(v >= 0 && v <= 1)) {
        LuaError(L, SET_WEATHER_USAGE);
        return 0;
    }
    if (!WeatherReady(L)) {
        return 0;
    }
    g_weatherOn = TRUE;
    g_weatherType = type;
    g_weatherIntensity = (float)v;
    SetWeather_o(WeatherObject(), type, (float)v, 0);
    WeatherSound_o(WeatherSound(type, (float)v));
    return 0;
}

// The server's weather again.
static int GAME_FASTCALL Script_ClearWeather(void *L) {
    if (!WeatherReady(L)) {
        return 0;
    }
    g_weatherOn = FALSE;
    SetWeather_o(WeatherObject(), g_serverWeatherType, g_serverWeatherIntensity, 0);
    WeatherSound_o(g_serverWeatherSound);
    return 0;
}

// type, intensity, whether it's yours (1) or the server's (0), and the
// server's type and intensity.
static int GAME_FASTCALL Script_GetWeather(void *L) {
    LuaPushNumber(L, g_weatherOn ? g_weatherType : g_serverWeatherType);
    LuaPushNumber(L, g_weatherOn ? g_weatherIntensity : g_serverWeatherIntensity);
    LuaPushNumber(L, g_weatherOn ? 1 : 0);
    LuaPushNumber(L, g_serverWeatherType);
    LuaPushNumber(L, g_serverWeatherIntensity);
    return 5;
}

// Time of day. The world is lit, and the sky, sun and moon drawn, by the
// game clock. A picked time replaces the clock for those only: the clock
// itself (GetGameTime, the minimap) and the server keep the real time.
typedef uint32_t(GAME_THISCALL *GameTimeMinutes_t)(void *clock);
typedef float(GAME_THISCALL *GameTimeProgress_t)(void *clock);
static GameTimeMinutes_t GameTimeMinutes_o = NULL;
static GameTimeProgress_t GameTimeProgress_o = NULL;
static BOOL g_timeOn = FALSE;
static uint32_t g_timeMinutes = 0;

static uint32_t GAME_THISCALL GameTimeMinutes_h(void *clock) {
    void *from = __builtin_return_address(0);
    if (g_timeOn && (from == (void *)RET_WORLD_LIGHT_MINUTES || from == (void *)RET_WORLD_SKY_MINUTES)) {
        return g_timeMinutes;
    }
    return GameTimeMinutes_o(clock);
}

static float GAME_THISCALL GameTimeProgress_h(void *clock) {
    if (g_timeOn && __builtin_return_address(0) == (void *)RET_WORLD_LIGHT_PROGRESS) {
        return g_timeMinutes / 1440.0f;
    }
    return GameTimeProgress_o(clock);
}

static const char *SET_TIME_USAGE = "Usage: DmorphHelper_SetTime(minutes 0-1439, or -1 for the real time)";

// The time of day the world is drawn at, in minutes after midnight; -1 for
// the real time.
static int GAME_FASTCALL Script_SetTime(void *L) {
    if (!LuaIsNumber(L, 1)) {
        LuaError(L, SET_TIME_USAGE);
        return 0;
    }
    double v = LuaToNumber(L, 1);
    if (!(v == -1 || (v >= 0 && v < 1440))) {
        LuaError(L, SET_TIME_USAGE);
        return 0;
    }
    if (!GameTimeMinutes_o || !GameTimeProgress_o) {
        LuaError(L, "DmorphHelper couldn't hook the game's clock.");
        return 0;
    }
    g_timeOn = v >= 0;
    g_timeMinutes = g_timeOn ? (uint32_t)v : 0;
    return 0;
}

// minutes the world is drawn at, whether that's yours (1) or the real
// time (0), and the real minutes.
static int GAME_FASTCALL Script_GetTime(void *L) {
    uint32_t real = GameTimeMinutes_o ? GameTimeMinutes_o((void *)GAME_CLOCK) : 0;
    LuaPushNumber(L, g_timeOn ? g_timeMinutes : real);
    LuaPushNumber(L, g_timeOn ? 1 : 0);
    LuaPushNumber(L, real);
    return 3;
}

// Virtual items. The game shows a worn item by asking its item cache for the
// item's record (display ID, inventory type, sheath, ...); the server fills
// the cache. A virtual item is an item ID the server doesn't have, answered
// here with a copy of a real item's record (same kind of weapon, so it's held
// and sheathed the same) whose display ID is a model ported to this PC. Only
// this PC sees them, like every morph.
typedef void *(GAME_THISCALL *GetItemRecord_t)(void *cache, uint32_t id, const uint64_t *guid, void *callback,
                                               void *userData, uint32_t askServer);
static GetItemRecord_t GetItemRecord_o = NULL;
#define MAX_VIRTUAL_ITEMS 131072
#define VIRTUAL_HASH_SIZE 262144               // a power of two, twice the most items
typedef struct {
    uint32_t id, templateId, displayId;
    uint8_t *record;                      // our copy, made when the game first asks; kept
} VirtualItem;
static VirtualItem g_virtual[MAX_VIRTUAL_ITEMS];
static int g_virtualCount = 0;
static uint32_t g_virtualMin = 0xFFFFFFFF, g_virtualMax = 0; // quick test before looking up
static uint32_t g_virtualHash[VIRTUAL_HASH_SIZE];            // item index + 1, 0 = empty

static VirtualItem *FindVirtual(uint32_t id) {
    for (uint32_t h = (id * 2654435761u) & (VIRTUAL_HASH_SIZE - 1);; h = (h + 1) & (VIRTUAL_HASH_SIZE - 1)) {
        uint32_t slot = g_virtualHash[h];
        if (slot == 0) {
            return NULL;
        }
        if (g_virtual[slot - 1].id == id) {
            return &g_virtual[slot - 1];
        }
    }
}

static VirtualItem *AddVirtual(uint32_t id) {
    if (g_virtualCount >= MAX_VIRTUAL_ITEMS) {
        return NULL;
    }
    uint32_t h = (id * 2654435761u) & (VIRTUAL_HASH_SIZE - 1);
    while (g_virtualHash[h] != 0) {
        h = (h + 1) & (VIRTUAL_HASH_SIZE - 1);
    }
    VirtualItem *v = &g_virtual[g_virtualCount];
    v->id = id;
    g_virtualHash[h] = (uint32_t)(++g_virtualCount);
    if (id < g_virtualMin) g_virtualMin = id;
    if (id > g_virtualMax) g_virtualMax = id;
    return v;
}

static void *GAME_FASTCALL GetItemRecord_h(void *cache, void *edx, uint32_t id, const uint64_t *guid, void *callback,
                                           void *userData, uint32_t askServer) {
    (void)edx;
    VirtualItem *v = id >= g_virtualMin && id <= g_virtualMax ? FindVirtual(id) : NULL;
    if (!v) {
        return GetItemRecord_o(cache, id, guid, callback, userData, askServer);
    }
    // The template's record (the server is asked for it if it isn't cached yet).
    uint8_t *t = (uint8_t *)GetItemRecord_o(cache, v->templateId, guid, NULL, NULL, askServer);
    if (!t) {
        return NULL;
    }
    if (!v->record) {
        v->record = (uint8_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 1024);
        if (!v->record) {
            return NULL;
        }
    }
    memcpy(v->record, t, ITEM_STATS_SIZE);
    memcpy(v->record + ITEM_STATS_DISPLAY_ID, &v->displayId, 4);
    return v->record;
}

static const char *VIRTUAL_USAGE = "Usage: DmorphHelper_SetVirtualItem(itemID, templateItemID, displayID)";

// Registers (or changes) a virtual item.
static int GAME_FASTCALL Script_SetVirtualItem(void *L) {
    uint32_t id = NumberArg(L, 1, 1, 2147483647.0, VIRTUAL_USAGE);
    uint32_t templateId = NumberArg(L, 2, 1, 2147483647.0, VIRTUAL_USAGE);
    uint32_t displayId = NumberArg(L, 3, 1, 2147483647.0, VIRTUAL_USAGE);
    if (!GetItemRecord_o) {
        LuaError(L, "DmorphHelper couldn't hook the game's item cache.");
        return 0;
    }
    VirtualItem *v = FindVirtual(id);
    if (!v) {
        v = AddVirtual(id);
        if (!v) {
            LuaError(L, "DmorphHelper: too many virtual items.");
            return 0;
        }
    }
    v->templateId = templateId;
    v->displayId = displayId;
    return 0;
}

// The display ID a virtual item shows, or nothing.
static int GAME_FASTCALL Script_GetVirtualItem(void *L) {
    VirtualItem *v = FindVirtual(NumberArg(L, 1, 1, 2147483647.0, "Usage: DmorphHelper_GetVirtualItem(itemID)"));
    if (!v) {
        return 0;
    }
    LuaPushNumber(L, v->templateId);
    LuaPushNumber(L, v->displayId);
    return 2;
}

// Rider poses (v14). Some mounts in later expansions change their rider's pose
// (the spell's aura kit loops an animation on the rider, SpellVisualAnim): on
// the mage discs, boards, kites and flying carpets the rider stands crouched
// (StealthStand, 120), on a few they sit on it (SitGround, 97). 1.12 always
// uses the riding pose (Mount, 91), set in two places: right after the rider's
// model is attached to the mount's (0x607B40, push 0x5B before the call to the
// model's set-animation function 0x7121A0) and every time the unit's
// animation is picked while it has a mount model (0x5FE809, mov eax,0x5B in
// the animation picker 0x5FE2F0; the unit is in ebx). Both are patched to ask
// RiderAnim for the mount display the unit shows (UNIT_FIELD_MOUNTDISPLAYID,
// which holds a mount skin too). The addon says which displays get which pose.
#define UNIT_FIELD_MOUNTDISPLAYID 0x85
#define ANIM_MOUNT 91
#define ANIM_HIGHEST 225 // AnimationData's contiguous IDs (0-225) on this client
#define RIDER_PICK_AT 0x5FE809
#define RIDER_MOUNT_AT 0x607B3C
#define MAX_POSES 4096
#define POSE_HASH_SIZE 8192 // a power of two, twice the most poses
static uint32_t g_poseDisplay[POSE_HASH_SIZE]; // 0 = empty
static uint16_t g_poseAnim[POSE_HASH_SIZE];    // 0 after a pose is removed: the riding pose
static int g_poseCount = 0;
static BOOL g_posesPatched = FALSE;

static int PoseSlot(uint32_t display) {
    for (uint32_t h = (display * 2654435761u) & (POSE_HASH_SIZE - 1);; h = (h + 1) & (POSE_HASH_SIZE - 1)) {
        if (g_poseDisplay[h] == display || g_poseDisplay[h] == 0) {
            return (int)h;
        }
    }
}

// The rider's animation on a unit's mount (called from the patched code).
__attribute__((used)) static uint32_t RiderAnim(void *unit) __asm__("DmorphHelper_RiderAnim");
static uint32_t RiderAnim(void *unit) {
    if (g_poseCount == 0 || !unit) {
        return ANIM_MOUNT;
    }
    uint32_t *f = Fields(unit);
    uint32_t display = f ? f[UNIT_FIELD_MOUNTDISPLAYID] : 0;
    if (display == 0) {
        return ANIM_MOUNT;
    }
    int h = PoseSlot(display);
    return g_poseDisplay[h] == display && g_poseAnim[h] ? g_poseAnim[h] : ANIM_MOUNT;
}

// At 0x5FE809 (mov eax,0x5B; 5 bytes): eax = the rider's animation for ebx.
__attribute__((naked)) static void RiderPickStub(void) {
    __asm__ volatile(
        "push %ecx\n\t"
        "push %edx\n\t"
        "push %ebx\n\t"
        "call DmorphHelper_RiderAnim\n\t"
        "add $4, %esp\n\t"
        "pop %edx\n\t"
        "pop %ecx\n\t"
        "ret\n\t");
}

// At 0x607B3C (push 0; push -1; push 0x5B; 6 bytes, now call + nop): the same
// three arguments with the rider's animation for esi; ecx (the rider's model)
// kept, eax and edx are free there.
__attribute__((naked)) static void RiderMountStub(void) {
    __asm__ volatile(
        "pop %eax\n\t"
        "push $0\n\t"
        "push $-1\n\t"
        "push %eax\n\t"
        "push %ecx\n\t"
        "push %esi\n\t"
        "call DmorphHelper_RiderAnim\n\t"
        "add $4, %esp\n\t"
        "pop %ecx\n\t"
        "pop %edx\n\t"
        "push %eax\n\t"
        "jmp *%edx\n\t");
}

static BOOL WriteCall(uintptr_t at, const uint8_t *expected, size_t size, void *target) {
    if (memcmp((const void *)at, expected, size) != 0) {
        return FALSE;
    }
    uint8_t code[8];
    int32_t rel = (int32_t)((uintptr_t)target - (at + 5));
    code[0] = 0xE8;
    memcpy(code + 1, &rel, 4);
    for (size_t i = 5; i < size; i++) {
        code[i] = 0x90;
    }
    DWORD old;
    if (!VirtualProtect((LPVOID)at, size, PAGE_EXECUTE_READWRITE, &old)) {
        return FALSE;
    }
    memcpy((void *)at, code, size);
    VirtualProtect((LPVOID)at, size, old, &old);
    FlushInstructionCache(GetCurrentProcess(), (LPCVOID)at, size);
    return TRUE;
}

// Once, on the game's own thread (when it loads its Lua functions), so the
// code isn't running while it changes. Both or neither: the bytes must be the
// stock ones (another mod could have changed them).
static void PatchRiderPoses(void) {
    static BOOL tried = FALSE;
    if (tried) {
        return;
    }
    tried = TRUE;
    static const uint8_t pick[] = { 0xB8, 0x5B, 0x00, 0x00, 0x00 };
    static const uint8_t mount[] = { 0x6A, 0x00, 0x6A, 0xFF, 0x6A, 0x5B };
    if (memcmp((const void *)RIDER_PICK_AT, pick, sizeof pick) != 0 ||
        memcmp((const void *)RIDER_MOUNT_AT, mount, sizeof mount) != 0) {
        return;
    }
    g_posesPatched = WriteCall(RIDER_PICK_AT, pick, sizeof pick, (void *)&RiderPickStub) &&
                     WriteCall(RIDER_MOUNT_AT, mount, sizeof mount, (void *)&RiderMountStub);
}

static const char *POSE_USAGE = "Usage: DmorphHelper_SetRiderPose(displayID, animation) (0 or 91: the riding pose)";

// Which pose riders of a mount display get (0 or 91 = the usual riding pose).
static int GAME_FASTCALL Script_SetRiderPose(void *L) {
    uint32_t display = NumberArg(L, 1, 1, 2147483647.0, POSE_USAGE);
    uint32_t anim = NumberArg(L, 2, 0, ANIM_HIGHEST, POSE_USAGE);
    if (!g_posesPatched) {
        LuaError(L, "DmorphHelper couldn't change the game's riding pose.");
        return 0;
    }
    if (anim == ANIM_MOUNT) {
        anim = 0;
    }
    int h = PoseSlot(display);
    if (g_poseDisplay[h] != display) {
        if (anim == 0) {
            return 0;
        }
        if (g_poseCount >= MAX_POSES) {
            LuaError(L, "DmorphHelper: too many rider poses.");
            return 0;
        }
        g_poseCount++;
    }
    g_poseAnim[h] = (uint16_t)anim;
    g_poseDisplay[h] = display;
    return 0;
}

// The pose riders of a mount display get (91 = the usual riding pose), and
// whether poses work (1/0).
static int GAME_FASTCALL Script_GetRiderPose(void *L) {
    uint32_t display = NumberArg(L, 1, 1, 2147483647.0, "Usage: DmorphHelper_GetRiderPose(displayID)");
    int h = PoseSlot(display);
    LuaPushNumber(L, g_poseDisplay[h] == display && g_poseAnim[h] ? g_poseAnim[h] : ANIM_MOUNT);
    LuaPushNumber(L, g_posesPatched ? 1 : 0);
    return 2;
}

// The game lists the map cells a line crosses (the mouse pointer's line into
// the world, line of sight) in a buffer it sizes once for 2048 cells and
// never checks. The pointer's line reaches as far as your view distance, so
// with a long one (farClip above the game's 777, as launchers allow) it runs
// past the end and the game crashes (ERROR #132 at 0x0069C6DA..0x0069C8A9).
// The game's own reserve function makes it big enough for a line across a
// whole continent (64 tiles of 128 cells, up to 4 entries per cell).
#define WORLD_LINE_CELLS_WANTED 0x10000
typedef void(GAME_THISCALL *ArrayReserve_t)(void *array, uint32_t more, uint32_t roundUp);

static void GrowWorldLineCells(void) {
    uint32_t *cells = (uint32_t *)WORLD_LINE_CELLS;
    if (cells[0] < WORLD_LINE_CELLS_WANTED && cells[1] < WORLD_LINE_CELLS_WANTED) {
        ((ArrayReserve_t)FUN_GROWABLE_ARRAY_RESERVE)(cells, WORLD_LINE_CELLS_WANTED - cells[1], 1);
    }
}

static void GAME_FASTCALL LoadScriptFunctions_h(void) {
    LoadScriptFunctions_o();
    GrowWorldLineCells();
    PatchRiderPoses();
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
    RegisterFunction("DmorphHelper_SetWeather", (uintptr_t)&Script_SetWeather);
    RegisterFunction("DmorphHelper_ClearWeather", (uintptr_t)&Script_ClearWeather);
    RegisterFunction("DmorphHelper_GetWeather", (uintptr_t)&Script_GetWeather);
    RegisterFunction("DmorphHelper_SetTime", (uintptr_t)&Script_SetTime);
    RegisterFunction("DmorphHelper_GetTime", (uintptr_t)&Script_GetTime);
    RegisterFunction("DmorphHelper_SetVirtualItem", (uintptr_t)&Script_SetVirtualItem);
    RegisterFunction("DmorphHelper_GetVirtualItem", (uintptr_t)&Script_GetVirtualItem);
    RegisterFunction("DmorphHelper_SetAmmo", (uintptr_t)&Script_SetAmmo);
    RegisterFunction("DmorphHelper_GetAmmo", (uintptr_t)&Script_GetAmmo);
    RegisterFunction("DmorphHelper_SetRiderPose", (uintptr_t)&Script_SetRiderPose);
    RegisterFunction("DmorphHelper_GetRiderPose", (uintptr_t)&Script_GetRiderPose);
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
    if (MH_CreateHook((LPVOID)FUN_CWEATHER_SET_WEATHER, (LPVOID)&SetWeather_h, (LPVOID *)&SetWeather_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_CWEATHER_SET_WEATHER) != MH_OK) {
        SetWeather_o = NULL;
    }
    if (MH_CreateHook((LPVOID)FUN_PLAY_WEATHER_SOUND, (LPVOID)&WeatherSound_h, (LPVOID *)&WeatherSound_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_PLAY_WEATHER_SOUND) != MH_OK) {
        WeatherSound_o = NULL;
    }
    if (MH_CreateHook((LPVOID)FUN_GAME_TIME_MINUTES, (LPVOID)&GameTimeMinutes_h, (LPVOID *)&GameTimeMinutes_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_GAME_TIME_MINUTES) != MH_OK) {
        GameTimeMinutes_o = NULL;
    }
    if (MH_CreateHook((LPVOID)FUN_GAME_TIME_DAY_PROGRESS, (LPVOID)&GameTimeProgress_h, (LPVOID *)&GameTimeProgress_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_GAME_TIME_DAY_PROGRESS) != MH_OK) {
        GameTimeProgress_o = NULL;
    }
    if (MH_CreateHook((LPVOID)FUN_DBCACHE_ITEM_STATS_GET_RECORD, (LPVOID)&GetItemRecord_h, (LPVOID *)&GetItemRecord_o) != MH_OK ||
        MH_EnableHook((LPVOID)FUN_DBCACHE_ITEM_STATS_GET_RECORD) != MH_OK) {
        GetItemRecord_o = NULL;
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
