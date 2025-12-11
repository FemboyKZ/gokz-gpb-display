StringMap g_PBTime;
StringMap g_PBPoints;
StringMap g_PBDate;

stock void BuildKey(int client, int mode, int hasTP, const char[] map, char[] key, int keylen)
{
    int steam32 = GetSteamAccountID(client);
    Format(key, keylen, "%d|%d|%d|%s", steam32, mode, hasTP, map);
}

stock void StorePB(int client, int mode, int hasTP, const char[] map, float time, int points, const char[] date = "")
{
    if (time <= 0.0) return;
    char key[192];
    BuildKey(client, mode, hasTP, map, key, sizeof key);
    g_PBTime.SetValue(key, view_as<any>(time));
    g_PBPoints.SetValue(key, view_as<any>(points));
    if (strlen(date) > 0)
    {
        char[] dateCopy = new char[16];
        strcopy(dateCopy, 16, date);
        g_PBDate.SetString(key, dateCopy);
    }
}

stock bool GetStoredPB(int client, int mode, int hasTP, const char[] map, float &time, int &points, char[] date = "", int dateLen = 0)
{
    char key[192];
    BuildKey(client, mode, hasTP, map, key, sizeof key);
    any val;
    bool ok1 = g_PBTime.GetValue(key, val);
    if (!ok1) return false;
    time = view_as<float>(val);
    if (!g_PBPoints.GetValue(key, val)) { points = 0; }
    else { points = view_as<int>(val); }
    if (dateLen > 0)
    {
        if (!g_PBDate.GetString(key, date, dateLen))
            date[0] = '\0';
    }
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

    // Print with Δ computed against the snapshotted baseline
    PrintPBLine_WithDiff(client, mode, hasTP, map,
                         pbTimeToShow, pbPtsToShow, pbTP, dateOnly,
                         hadBaseline, oldTime, oldPts);

    // Update baseline *after* printing
    StorePB(client, mode, hasTP, map, pbTimeToShow, pbPtsToShow, dateOnly);

    delete data;
}

stock void PrintPBLine_WithDiff(int client, int mode, int hasTeleports, const char[] map,
                                float pbTime, int pbPts, int pbTP /*unused*/, const char[] dateOnly,
                                bool hasStored, float oldTime, int oldPts)
{
    char t[32];     FormatDuration(t, sizeof t, pbTime);
    char dateS[32]; FormatDateShort(dateOnly, dateS, sizeof dateS);

    char diffInline[48]; diffInline[0] = '\0';
    int dPts = 0;

    if (hasStored)
    {
        float dt = pbTime - oldTime;
        float dAbs = FloatAbs(dt);

        char dTimeS[24]; FormatDurationDiff(dTimeS, sizeof dTimeS, dAbs);

        if (dt < 0.0)
        {
            Format(diffInline, sizeof diffInline, " ({green}-%s{default})", dTimeS);
            dPts = pbPts - oldPts;
            if (dPts < 0) dPts = 0;
        }
        else if (dt > 0.0)
        {
            Format(diffInline, sizeof diffInline, " ({red}+%s{default})", dTimeS);
        }
        else
        {
            Format(diffInline, sizeof diffInline, " (±00:00.00)");
        }
    }

    char ptsText[64];
    if (dPts > 0)
        Format(ptsText, sizeof ptsText, "{yellow}%d{default} ({green}+%d{default}){grey} Pts{default}", pbPts, dPts);
    else
        Format(ptsText, sizeof ptsText, "{yellow}%d{default}{grey} Pts{default}", pbPts);

    // Use buffer instead of inline ternary
    char prefix[16];
    if (hasTeleports > 0)
        strcopy(prefix, sizeof prefix, "{gold}NUB");
    else
        strcopy(prefix, sizeof prefix, "{blue}PRO");

    GOKZ_PrintToChat(
        client, false,
        "{purple}%s{default} - {darkblue}%s{default} - %s{default}  {yellow}PB {default}[ {lightgreen}%s{default}%s | %s | {bluegrey}%s{default} ]",
        map, gC_ModeShort[mode], prefix, t, diffInline, ptsText, dateS
    );
}
