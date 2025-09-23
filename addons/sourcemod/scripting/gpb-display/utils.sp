stock void FormatDateShort(const char[] ymd, char[] out, int outlen)
{
    if (strlen(ymd) < 10) { strcopy(out, outlen, ymd); return; }

    char y[5], m[3], d[3];

    // Split by '-' safely: parts[0]=YYYY, parts[1]=MM, parts[2]=DD
    char parts[3][5];
    int n = ExplodeString(ymd, "-", parts, 3, sizeof(parts[])); // sizeof(parts[]) == 5
    if (n == 3) {
        strcopy(y, sizeof y, parts[0]);
        strcopy(m, sizeof m, parts[1]);
        strcopy(d, sizeof d, parts[2]);
    } else {
        // Fallback if format unexpected
        strcopy(out, outlen, ymd);
        return;
    }

    int mi = StringToInt(m);
    char mon[6]; // room for "Dec." + \0

    switch (mi)
    {
        case 1:  strcopy(mon, sizeof mon, "Jan.");
        case 2:  strcopy(mon, sizeof mon, "Feb.");
        case 3:  strcopy(mon, sizeof mon, "Mar.");
        case 4:  strcopy(mon, sizeof mon, "Apr.");
        case 5:  strcopy(mon, sizeof mon, "May.");
        case 6:  strcopy(mon, sizeof mon, "Jun.");
        case 7:  strcopy(mon, sizeof mon, "Jul.");
        case 8:  strcopy(mon, sizeof mon, "Aug.");
        case 9:  strcopy(mon, sizeof mon, "Sep.");
        case 10: strcopy(mon, sizeof mon, "Oct.");
        case 11: strcopy(mon, sizeof mon, "Nov.");
        case 12: strcopy(mon, sizeof mon, "Dec.");
        default: strcopy(mon, sizeof mon, m);
    }

    Format(out, outlen, "%s %s %s", d, mon, y);
}

stock void FormatSignedDiff(char[] out, int len, float seconds)
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

stock void PrintPBLine_WithDiff(int client, int mode, int hasTeleports, const char[] map, float pbTime, int pbPts, int pbTP, const char[] dateOnly, bool hasStored, float oldTime, int oldPts)
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

    char prefix[16];
    if (hasTeleports > 0)
        strcopy(prefix, sizeof(prefix), "{gold}NUB");
    else
        strcopy(prefix, sizeof(prefix), "{blue}PRO");

    GOKZ_PrintToChat(client, false,
        "{darkblue}%s {default}- %s {default}- %s {default}PB {default}[ {green}%s {default}| {yellow}%d{default} Pts | {yellow}%d{default} TP | {yellow}%s{default}%s ]",
        gC_ModeShort[mode], map, prefix, t, pbPts, pbTP, dateOnly, extra);
}
