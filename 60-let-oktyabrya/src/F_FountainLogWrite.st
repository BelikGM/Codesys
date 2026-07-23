FUNCTION F_FountainLogWrite : BOOL
(* Без изменений относительно проекта ДДЮТ. Позиция 1 — ВСЕГДА    *)
(* самая последняя запись. При новой записи всё содержимое          *)
(* сдвигается на 1 позицию вниз (сдвиг ОБЯЗАТЕЛЬНО с конца массива   *)
(* к началу — иначе затрёшь данные раньше, чем скопируешь), новая    *)
(* запись садится на 1. Когда достигнут предел (60) — самая старая   *)
(* запись (позиция 60) просто выпадает при сдвиге. Экран использует  *)
(* ФИКСИРОВАННЫЕ индексы (aFountainLog[1], [2], [3]...).             *)
VAR_INPUT
    sChangeText : WSTRING(60);   (* полное понятное название параметра: старое→новое *)
END_VAR
VAR
    i : INT;
END_VAR

FOR i := 60 TO 2 BY -1 DO
    GVL_Fountain.aFountainLog[i] := GVL_Fountain.aFountainLog[i-1];
END_FOR;

GVL_Fountain.aFountainLog[1] := WCONCAT(F_FormatLogDateOnly(), WCONCAT(" ", sChangeText));

IF GVL_Fountain.iFountainLogCount < 60 THEN
    GVL_Fountain.iFountainLogCount := GVL_Fountain.iFountainLogCount + 1;
END_IF;

(* === ДУБЛЬ НА SD === кладём ту же строку в очередь журнала        *)
(* уставок, её заберёт и запишет в файл PRG_AlarmLogSD (CAA File).  *)
IF GVL_Fountain.iSdSetpQCount < 20 THEN
    GVL_Fountain.iSdSetpQTail := (GVL_Fountain.iSdSetpQTail MOD 20) + 1;
    GVL_Fountain.awsSdSetpQ[GVL_Fountain.iSdSetpQTail] := GVL_Fountain.aFountainLog[1];
    GVL_Fountain.iSdSetpQCount := GVL_Fountain.iSdSetpQCount + 1;
END_IF;

F_FountainLogWrite := TRUE;
