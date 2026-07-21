FUNCTION F_FormatLogTimestamp : WSTRING(20)
(* === ДДЮТ: без изменений относительно Саки Пруд === *)
VAR
    sDay, sMon, sYear, sHour, sMin, sSec : WSTRING(4);
END_VAR
IF iCurrentDay < 10 THEN
    sDay := WCONCAT("0", INT_TO_WSTRING(iCurrentDay));
ELSE sDay := INT_TO_WSTRING(iCurrentDay); END_IF;
IF iCurrentMonth < 10 THEN
    sMon := WCONCAT("0", INT_TO_WSTRING(iCurrentMonth));
ELSE sMon := INT_TO_WSTRING(iCurrentMonth); END_IF;
sYear := INT_TO_WSTRING(iCurrentYear MOD 100);
IF (iCurrentYear MOD 100) < 10 THEN
    sYear := WCONCAT("0", sYear);
END_IF;
IF iCurrentHour < 10 THEN
    sHour := WCONCAT("0", INT_TO_WSTRING(iCurrentHour));
ELSE sHour := INT_TO_WSTRING(iCurrentHour); END_IF;
IF iCurrentMinute < 10 THEN
    sMin := WCONCAT("0", INT_TO_WSTRING(iCurrentMinute));
ELSE sMin := INT_TO_WSTRING(iCurrentMinute); END_IF;
IF iCurrentSecond < 10 THEN
    sSec := WCONCAT("0", INT_TO_WSTRING(iCurrentSecond));
ELSE sSec := INT_TO_WSTRING(iCurrentSecond); END_IF;
F_FormatLogTimestamp := WCONCAT(sDay, WCONCAT(".",
    WCONCAT(sMon, WCONCAT(".",
    WCONCAT(sYear, WCONCAT(" ",
    WCONCAT(sHour, WCONCAT(":",
    WCONCAT(sMin, WCONCAT(":", sSec))))))))));
