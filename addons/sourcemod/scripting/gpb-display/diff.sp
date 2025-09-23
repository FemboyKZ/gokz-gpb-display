StringMap g_PBTime;
StringMap g_PBPoints;

stock void BuildKey(int client, int mode, int hasTP, const char[] map, char[] key, int keylen)
{
    int steam32 = GetSteamAccountID(client);
    Format(key, keylen, "%d|%d|%d|%s", steam32, mode, hasTP, map);
}

stock void StorePB(int client, int mode, int hasTP, const char[] map, float time, int points)
{
    if (time <= 0.0) return;
    char key[192];
    BuildKey(client, mode, hasTP, map, key, sizeof key);
    g_PBTime.SetValue(key, view_as<any>(time));
    g_PBPoints.SetValue(key, view_as<any>(points));
}

stock bool GetStoredPB(int client, int mode, int hasTP, const char[] map, float &time, int &points)
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

stock void GlobalPB_Callback_PrintPBWithDiff(Handle request, bool failure, bool success, EHTTPStatusCode status, DataPack data)
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
