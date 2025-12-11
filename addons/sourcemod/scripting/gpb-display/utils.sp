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
        case 1:  strcopy(mon, sizeof mon, "Jan");
        case 2:  strcopy(mon, sizeof mon, "Feb");
        case 3:  strcopy(mon, sizeof mon, "Mar");
        case 4:  strcopy(mon, sizeof mon, "Apr");
        case 5:  strcopy(mon, sizeof mon, "May");
        case 6:  strcopy(mon, sizeof mon, "Jun");
        case 7:  strcopy(mon, sizeof mon, "Jul");
        case 8:  strcopy(mon, sizeof mon, "Aug");
        case 9:  strcopy(mon, sizeof mon, "Sep");
        case 10: strcopy(mon, sizeof mon, "Oct");
        case 11: strcopy(mon, sizeof mon, "Nov");
        case 12: strcopy(mon, sizeof mon, "Dec");
        default: strcopy(mon, sizeof mon, m);
    }

    Format(out, outlen, "%s. %s %s", d, mon, y);
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

stock int FormatDurationDiff(char[] buffer, int maxlength, float duration)
{
    // Format duration for diffs - no "0:" prefix for times < 1 minute
    int hours = RoundToFloor(duration / 3600.0);
    duration -= hours * 3600;
    int minutes = RoundToFloor(duration / 60.0);
    duration -= minutes * 60;
    int seconds = RoundToFloor(duration);
    duration -= seconds;
    int milliseconds = RoundToFloor(duration * 100.0);

    if (hours > 0)
        return Format(buffer, maxlength, "%02d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds);
    else if (minutes > 0)
        return Format(buffer, maxlength, "%02d:%02d.%02d", minutes, seconds, milliseconds);

    return Format(buffer, maxlength, "%02d.%02d", seconds, milliseconds);
}
