FUNCTION F_PumpLogWrite : BOOL
(* === ДДЮТ:ИЗМЕНЕНО (round 7, ФИНАЛЬНАЯ СХЕМА) === Та же схема сдвига,    *)
(* что у F_FountainLogWrite (см. подробный комментарий там) — позиция 1     *)
(* всегда самая свежая запись, сдвиг ОБЯЗАТЕЛЬНО с конца массива к началу.  *)
VAR_INPUT
    sChangeText : WSTRING(65);   (* готовая строка одной записи *)
END_VAR
VAR
    i : INT;
END_VAR

FOR i := 30 TO 2 BY -1 DO
    GVL.aPumpLog[i] := GVL.aPumpLog[i-1];
END_FOR;

GVL.aPumpLog[1] := sChangeText;

IF GVL.iPumpLogCount < 30 THEN
    GVL.iPumpLogCount := GVL.iPumpLogCount + 1;
END_IF;

(* === ДУБЛЬ НА SD === та же строка в очередь журнала ПЧ,          *)
(* её заберёт и запишет в файл PRG_AlarmLogSD (CAA File).           *)
IF GVL_Fountain.iSdPumpQCount < 20 THEN
    GVL_Fountain.iSdPumpQTail := (GVL_Fountain.iSdPumpQTail MOD 20) + 1;
    GVL_Fountain.awsSdPumpQ[GVL_Fountain.iSdPumpQTail] := sChangeText;
    GVL_Fountain.iSdPumpQCount := GVL_Fountain.iSdPumpQCount + 1;
END_IF;

F_PumpLogWrite := TRUE;
