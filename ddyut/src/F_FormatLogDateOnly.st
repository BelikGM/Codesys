FUNCTION F_FormatLogDateOnly : WSTRING(10)
(* === ДДЮТ:НОВОЕ === Дата в формате ДД.ММ.ГГГГ, БЕЗ времени — для     *)
(* сжатого журнала изменений параметров фонтана (F_FountainLogWrite).  *)
(* Не трогает существующую F_FormatLogTimestamp() (дата+время) —       *)
(* та используется журналом ПЧ и другими местами без изменений.        *)
VAR
    sDay   : WSTRING(4);
    sMonth : WSTRING(4);
END_VAR

IF GVL_Fountain.iCurrentDay < 10 THEN
    sDay := WCONCAT("0", INT_TO_WSTRING(GVL_Fountain.iCurrentDay));
ELSE
    sDay := INT_TO_WSTRING(GVL_Fountain.iCurrentDay);
END_IF;

IF GVL_Fountain.iCurrentMonth < 10 THEN
    sMonth := WCONCAT("0", INT_TO_WSTRING(GVL_Fountain.iCurrentMonth));
ELSE
    sMonth := INT_TO_WSTRING(GVL_Fountain.iCurrentMonth);
END_IF;

F_FormatLogDateOnly := WCONCAT(sDay, WCONCAT(".", WCONCAT(sMonth,
    WCONCAT(".", INT_TO_WSTRING(GVL_Fountain.iCurrentYear)))));
