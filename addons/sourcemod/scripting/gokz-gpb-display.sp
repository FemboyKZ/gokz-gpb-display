#include <sourcemod>
#include <globalpb>
#include <gokz>
#include <gokz/core>
#include <gokz/localdb>
#include <smjansson>
#include <SteamWorks>

#define SP_VERSION "1.1.0"

// ─────────────────────────────────────────────────────────────
// Simple in-memory PB cache (per map + mode + hasTP)
// key = "<steam32>|<mode>|<hasTP>|<map>"
// stores time (float) and points (int) in two StringMaps
// ─────────────────────────────────────────────────────────────
static StringMap g_PBTime;
static StringMap g_PBPoints;

public Plugin myinfo =
{
    name        = "gokz-gpb-display",
    author      = "Reeed & Cinyan10",
    description = "show PB/WR on spawn/mode change and PB on finish; shows Δ vs stored PB",
    version     = SP_VERSION,
    url         = "https://axekz.com/"
};

public void OnPluginStart()
{
    if (g_PBTime == null)   g_PBTime   = new StringMap();
    if (g_PBPoints == null) g_PBPoints = new StringMap();

    RegConsoleCmd("sm_pb",  Command_ShowPB);
    RegConsoleCmd("sm_gpb", Command_ShowPB);
}

public void OnClientDisconnect(int client)
{
    // optional: purge this client’s keys for current map to save memory (left out for simplicity)
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────
static void BuildKey(int client, int mode, int hasTP, const char[] map, char[] key, int keylen)
{
    int steam32 = GetSteamAccountID(client);
    Format(key, keylen, "%d|%d|%d|%s", steam32, mode, hasTP, map);
}

static void StorePB(int client, int mode, int hasTP, const char[] map, float time, int points)
{
    if (time <= 0.0) return;
    char key[192];
    BuildKey(client, mode, hasTP, map, key, sizeof key);
    g_PBTime.SetValue(key, view_as<any>(time));
    g_PBPoints.SetValue(key, view_as<any>(points));
}

static bool GetStoredPB(int client, int mode, int hasTP, const char[] map, float &time, int &points)
{
    char key[192];
    BuildKey(client, mode, hasTP, map, key, sizeof key);
    any val;
    bool ok1 = g_PBTime.GetValue(key, val);
    if (!ok1) return false;
    time = view_as<float>(val);
    if (!g_PBPoints.GetValue(key, val)) { points = 0; }
    else { points = view_as<int>(val); }
    return true;
}

static void FormatSignedDiff(char[] out, int len, float seconds)
{
    // uses FormatDuration() for absolute, prefixes sign
    char absbuf[32];
    FormatDuration(absbuf, sizeof absbuf, FloatAbs(seconds));
    if (seconds > 0.0005)
        Format(out, len, "+%s", absbuf);
    else if (seconds < -0.0005)
        Format(out, len, "-%s", absbuf);
    else
        strcopy(out, len, "±0");
}

// ─────────────────────────────────────────────────────────────
// Printing helpers
// ─────────────────────────────────────────────────────────────
static void PrintWRLine(int client, int mode, int hasTeleports, float wrTime, const char[] map)
{
    char t[32]; FormatDuration(t, sizeof t, wrTime);
    if (hasTeleports > 0)
        GOKZ_PrintToChat(client, false, "{yellow}%s {default} - {darkblue}%s{default} - {gold}NUB {red}WR {default}[ {green}%s{default} ]", map, gC_ModeShort[mode], t);
    else
        GOKZ_PrintToChat(client, false, "{yellow}%s {default} - {darkblue}%s{default} - {blue}PRO {red}WR {default}[ {green}%s{default} ]", map, gC_ModeShort[mode], t);
}

static void PrintPBLine_Base(int client, int mode, int hasTeleports, const char[] map,
                             float pbTime, int pbPts, int pbTP, const char[] dateOnly, bool pbOnly)
{
    char t[32]; FormatDuration(t, sizeof t, pbTime);
    if (pbOnly)
    {
        GOKZ_PrintToChat(client, false,
            "{darkblue}%s {default}- %s {default}- PB {default}[ {green}%s {default}| {yellow}%d{default} Pts | {yellow}%d{default} TP | {yellow}%s{default} ]",
            gC_ModeShort[mode], map, t, pbPts, pbTP, dateOnly);
    }
    else
    {
        if (hasTeleports > 0)
            GOKZ_PrintToChat(client, false,
                "{yellow}%s{default} - {darkblue}%s{default} -  {gold}NUB{default} PB {default}[ {green}%s {default}| {yellow}%d{default} Pts | {yellow}%d{default} TP | {yellow}%s{default} ]",
                map, gC_ModeShort[mode], t, pbPts, pbTP, dateOnly);
        else
            GOKZ_PrintToChat(client, false,
                "{yellow}%s{default} - {darkblue}%s{default} -  {blue}PRO{default} PB {default}[ {green}%s {default}| {yellow}%d{default} Pts | {yellow}%d{default} TP | {yellow}%s{default} ]",
                map, gC_ModeShort[mode], t, pbPts, pbTP, dateOnly);
    }
}

// Used ONLY for finish: adds Δtime and +pts (if improved)
static void PrintPBLine_WithDiff(int client, int mode, int hasTeleports, const char[] map,
                                 float pbTime, int pbPts, int pbTP, const char[] dateOnly,
                                 bool hasStored, float oldTime, int oldPts)
{
    char t[32]; FormatDuration(t, sizeof t, pbTime);

    char extra[64]; extra[0] = '\0';
    if (hasStored)
    {
        float dt = pbTime - oldTime;
        char sdt[24]; FormatSignedDiff(sdt, sizeof sdt, dt);

        if (dt < 0.0)
        {
            int dpts = pbPts - oldPts;
            if (dpts > 0)
                Format(extra, sizeof extra, " | Δ {green}%s{default} | {green}+%d{default} Pts", sdt, dpts);
            else
                Format(extra, sizeof extra, " | Δ {green}%s{default}", sdt);
        }
        else
        {
            // show Δ even if slower / unchanged
            Format(extra, sizeof extra, " | Δ {yellow}%s{default}", sdt);
        }
    }

    GOKZ_PrintToChat(client, false,
        "{darkblue}%s {default}- %s {default}- PB {default}[ {green}%s {default}| {yellow}%d{default} Pts | {yellow}%d{default} TP | {yellow}%s{default}%s ]",
        gC_ModeShort[mode], map, t, pbPts, pbTP, dateOnly, extra);
}

// ─────────────────────────────────────────────────────────────
// Events / Commands
// ─────────────────────────────────────────────────────────────
public void GOKZ_OnOptionChanged(int client, const char[] option, any newValue)
{
    if (StrEqual(option, gC_CoreOptionNames[Option_Mode]))
    {
        int mode = GOKZ_GetCoreOption(client, Option_Mode);
        RequestRecords(client, mode, false); // spawn/mode change → print WR + PB (and store baseline)
    }
}

public void GOKZ_OnFirstSpawn(int client)
{
    if (IsValidClient(client))
    {
        int mode = GOKZ_GetCoreOption(client, Option_Mode);
        RequestRecords(client, mode, false); // first spawn → print WR + PB (and store baseline)
    }
}

public Action Command_ShowPB(int client, int args)
{
    if (!IsValidClient(client)) return Plugin_Handled;
    int mode = GOKZ_GetCoreOption(client, Option_Mode);
    if (mode >= sizeof(gC_APIModes)) return Plugin_Handled;
    RequestRecords(client, mode, true); // on-demand → PB only (no WR)
    return Plugin_Handled;
}

// ─────────────────────────────────────────────────────────────
// Fetch flow
// ─────────────────────────────────────────────────────────────
static void RequestRecords(int client, int mode, bool pbOnly)
{
    char map[256];
    GetCurrentMap(map, sizeof(map));
    GetMapDisplayName(map, map, sizeof(map));

    int userid       = GetClientUserId(client);
    int targetUserid = GetClientUserId(client);

    DataPack data1 = CreateDataPack();
    data1.WriteCell(userid);
    data1.WriteCell(targetUserid);
    data1.WriteCell(mode);
    data1.WriteCell(0);      // course
    data1.WriteCell(1);      // hasTeleports = NUB for first leg
    data1.WriteString(map);
    data1.WriteCell(pbOnly ? 1 : 0);

    RequestGlobalPB(true, client, map, 0, mode, true, HTTPRequestCompleted_Stage1, data1);
}

static void HTTPRequestCompleted_Stage1(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1)
{
    if (failure || !requestSuccess || status != k_EHTTPStatusCode200OK)
    { delete request; delete data1; return; }

    float wrTime = -1.0; int wrTeleports = -1; int wrPoints = -1;
    if (!GetRequestRecordInfo(request, wrTime, wrTeleports, wrPoints))
    { delete request; delete data1; return; }

    data1.Reset();
    int userid = data1.ReadCell();
    int targetUserid = data1.ReadCell();
    int mode = data1.ReadCell();
    int course = data1.ReadCell();
    int hasTeleports = data1.ReadCell();
    char map[256]; data1.ReadString(map, sizeof map);
    bool pbOnly = data1.ReadCell() != 0;

    int client = GetClientOfUserId(userid);
    int target = GetClientOfUserId(targetUserid);
    if (client == 0 || target == 0)
    { delete request; delete data1; return; }

    if (!pbOnly && wrTime > 0.0)
        PrintWRLine(client, mode, hasTeleports, wrTime, map);

    // carry WR (unused later) in a tiny pack if needed; here we just chain PB
    RequestGlobalPB(false, target, map, course, mode, hasTeleports > 0, HTTPRequestCompleted_Stage2, data1);

    delete request;
}

static void HTTPRequestCompleted_Stage2(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1)
{
    data1.Reset();
    int userid = data1.ReadCell();
    int targetUserid = data1.ReadCell();
    int mode = data1.ReadCell();
    int course = data1.ReadCell();
    int hasTeleports = data1.ReadCell();
    char map[256]; data1.ReadString(map, sizeof map);
    int pbOnlyInt = data1.ReadCell(); bool pbOnly = (pbOnlyInt != 0);

    float pbTime = -1.0; int pbTeleports = -1; int pbPoints = -1;
    char when[64]; when[0] = '\0';
    if (!GetRequestRecordInfoWithDate(request, pbTime, pbTeleports, pbPoints, when, sizeof when))
    { delete request; delete data1; return; }
    delete request;

    // ISO → YYYY-MM-DD
    char dateOnly[16]; dateOnly[0] = '\0';
    int tpos = FindCharInString(when, 'T');
    if (tpos > 0 && tpos < sizeof(when)) { strcopy(dateOnly, sizeof(dateOnly), when); dateOnly[tpos] = '\0'; }
    else { strcopy(dateOnly, sizeof(dateOnly), when); }

    int client = GetClientOfUserId(userid);
    int target = GetClientOfUserId(targetUserid);
    if (client == 0 || target == 0) { delete data1; return; }

    // Print PB for current leg and STORE as baseline (spawn/mode-change path)
    if (pbTime > 0.0)
    {
        PrintPBLine_Base(client, mode, hasTeleports, map, pbTime, pbPoints, pbTeleports, dateOnly, pbOnly);
        StorePB(target, mode, hasTeleports, map, pbTime, pbPoints);
    }

    // If started with NUB, trigger PRO leg
    if (hasTeleports > 0)
    {
        data1.Reset();
        data1.WriteCell(userid);
        data1.WriteCell(targetUserid);
        data1.WriteCell(mode);
        data1.WriteCell(course);
        data1.WriteCell(0);          // next: PRO
        data1.WriteString(map);
        data1.WriteCell(pbOnlyInt);

        RequestGlobalPB(true, client, map, course, mode, false, HTTPRequestCompleted_Stage1, data1);
    }
    else
    {
        delete data1;
    }
}

// ─────────────────────────────────────────────────────────────
// Auto Print PB when they finished the map (PB-only)
// ─────────────────────────────────────────────────────────────
public void GOKZ_LR_OnTimeProcessed(
    int client,
    int steamID,
    int mapID,
    int course,
    int mode,
    int style,
    float runTime,
    int teleportsUsed,
    bool firstTime,
    float pbDiff,
    int rank,
    int maxRank,
    bool firstTimePro,
    float pbDiffPro,
    int rankPro,
    int maxRankPro)
{
    if (!IsValidClient(client))
        return;

    // Only when it’s actually a new PB (or first completion)
    if (!firstTime && pbDiff >= 0.0)
        return;

    bool isPro = (teleportsUsed == 0);

    DataPack dp = CreateDataPack();
    dp.WriteCell(GetClientUserId(client));
    dp.WriteCell(isPro ? 0 : 1);  // hasTP flag (0 = PRO, 1 = NUB)
    dp.WriteFloat(runTime);       // currently unused

    CreateTimer(2.0, Timer_FetchAndPrintPB, dp, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_FetchAndPrintPB(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int hasTP  = data.ReadCell();   // 1 = NUB, 0 = PRO
    data.ReadFloat();               // runTime (unused)

    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
    {
        delete data;
        return Plugin_Stop;
    }

    char map[64];
    GetCurrentMap(map, sizeof(map));
    GetMapDisplayName(map, map, sizeof(map));

    int mode = GOKZ_GetCoreOption(client, Option_Mode);

    DataPack carry = CreateDataPack();
    carry.WriteCell(userid);
    carry.WriteCell(userid);         // target
    carry.WriteCell(mode);
    carry.WriteCell(0);              // course
    carry.WriteCell(hasTP);
    carry.WriteString(map);
    carry.WriteFloat(0.0);           // placeholder

    RequestGlobalPB(false, client, map, 0, mode, hasTP == 1, GlobalPB_Callback_PrintPBWithDiff, carry);

    delete data;
    return Plugin_Stop;
}

static void GlobalPB_Callback_PrintPBWithDiff(Handle request, bool failure, bool success, EHTTPStatusCode status, DataPack data)
{
    if (failure || !success || status != k_EHTTPStatusCode200OK)
    { delete request; delete data; return; }

    float pbTime; int pbTP, pbPts; char when[64]; when[0] = '\0';
    if (!GetRequestRecordInfoWithDate(request, pbTime, pbTP, pbPts, when, sizeof when))
    { delete request; delete data; return; }
    delete request;

    data.Reset();
    int userid = data.ReadCell();
    int client = GetClientOfUserId(userid);
    data.ReadCell(); // target
    int mode = data.ReadCell();
    data.ReadCell(); // course
    int hasTP = data.ReadCell();
    char map[64]; data.ReadString(map, sizeof map);
    data.ReadFloat(); // placeholder
    if (!IsValidClient(client)) { delete data; return; }

    // ISO → YYYY-MM-DD
    char dateOnly[16]; dateOnly[0] = '\0';
    int tpos = FindCharInString(when, 'T');
    if (tpos > 0 && tpos < sizeof(when)) { strcopy(dateOnly, sizeof(dateOnly), when); dateOnly[tpos] = '\0'; }
    else { strcopy(dateOnly, sizeof(dateOnly), when); }

    // Diff vs stored baseline (from first spawn / last stored)
    float oldTime; int oldPts; bool hadBaseline = GetStoredPB(client, mode, hasTP, map, oldTime, oldPts);

    // Print with Δ and +pts (if improved)
    PrintPBLine_WithDiff(client, mode, hasTP, map, pbTime, pbPts, pbTP, dateOnly, hadBaseline, oldTime, oldPts);

    // Update baseline to the latest PB
    StorePB(client, mode, hasTP, map, pbTime, pbPts);

    delete data;
}
