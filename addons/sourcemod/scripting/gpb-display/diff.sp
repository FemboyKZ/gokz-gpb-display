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

    float fetchedPBTime; int pbTP, fetchedPts; char when[64]; when[0] = '\0';
    if (!GetRequestRecordInfoWithDate(request, fetchedPBTime, pbTP, fetchedPts, when, sizeof when))
    { delete request; delete data; return; }
    delete request;

    data.Reset();
    int userid = data.ReadCell();
    int client = GetClientOfUserId(userid);
    data.ReadCell();                    // target
    int mode = data.ReadCell();
    data.ReadCell();                    // course
    int hasTP = data.ReadCell();
    char map[64]; data.ReadString(map, sizeof map);

    float newRunTime = data.ReadFloat();  // authoritative NEW time
    float oldTime    = data.ReadFloat();  // authoritative OLD time (snapshot)
    int oldPts       = data.ReadCell();   // authoritative OLD points
    bool hadBaseline = (data.ReadCell() != 0);

    if (!IsValidClient(client)) { delete data; return; }

    // ISO → YYYY-MM-DD
    char dateOnly[16]; dateOnly[0] = '\0';
    int tpos = FindCharInString(when, 'T');
    if (tpos > 0 && tpos < sizeof(when)) { strcopy(dateOnly, sizeof(dateOnly), when); dateOnly[tpos] = '\0'; }
    else { strcopy(dateOnly, sizeof(dateOnly), when); }

    // Use NEW time from the run we *just finished*
    float pbTimeToShow = newRunTime;
    int   pbPtsToShow  = fetchedPts;   // use fetched NEW points
    int   dPts         = hadBaseline ? (pbPtsToShow - oldPts) : 0;

    // Print with Δ computed against the snapshotted baseline
    PrintPBLine_WithDiff(client, mode, hasTP, map,
                         pbTimeToShow, pbPtsToShow, pbTP, dateOnly,
                         hadBaseline, oldTime, oldPts);

    // Update baseline *after* printing
    StorePB(client, mode, hasTP, map, pbTimeToShow, pbPtsToShow);

    delete data;
}
