(* ============================================================ *)
(* PRG_AlarmLogSD — ЖУРНАЛЫ НА SD-КАРТУ (3 файла) — ДДЮТ        *)
(* ============================================================ *)
(* Пишет на SD три отдельных журнала (чтобы записи не путались): *)
(*   • АВАРИИ      → sAlarmLogPath   (alarms.log)               *)
(*   • ИЗМЕНЕНИЯ ПЧ → sPumpLogPath    (pump_changes.log)         *)
(*   • УСТАВКИ     → sSetpointLogPath (setpoints.log)           *)
(*                                                              *)
(* Строка: "чч:мм дд.мм.гггг - текст" (аварии) либо готовая      *)
(* строка журнала (ПЧ/уставки). WSTRING/UTF-16LE + BOM.         *)
(*                                                              *)
(* Аварии детектируются здесь (по фронту). Изменения ПЧ/уставок  *)
(* кладут строку в GVL_Fountain.awsSdPumpQ / awsSdSetpQ прямо из *)
(* F_PumpLogWrite / F_FountainLogWrite — здесь только пишем.     *)
(*                                                              *)
(* Один автомат обслуживает 3 файла (приоритет: аварии → ПЧ →    *)
(* уставки). ФБ CAA File асинхронные. Тип дескриптора            *)
(* FILE.CAA.HANDLE. SD FAT16/FAT32 MBR, /mnt/ufs/media/mmcblk0p1.*)
(* ============================================================ *)
PROGRAM PRG_AlarmLogSD
VAR CONSTANT
    cAlarmCnt : INT := 12;   // сколько аварий отслеживаем (ДДЮТ)
    cQSize    : INT := 20;
END_VAR
VAR
    (* --- Аварии: состояние + названия --- *)
    axAlarmNow  : ARRAY[1..cAlarmCnt] OF BOOL;
    axAlarmPrev : ARRAY[1..cAlarmCnt] OF BOOL;
    awsAlarmName : ARRAY[1..cAlarmCnt] OF WSTRING(60) := [
        "Сухой ход",
        "Сухой ход реле",
        "Добор — исчерпаны попытки",
        "Альгицид (защ.таймер)",
        "Биопаг (защ.таймер)",
        "pH реле",
        "Альгицид реле",
        "Биопаг реле",
        "Связь ПЧ1",
        "Связь ПЧ2",
        "Связь МВ-Д",
        "Связь МУ"];

    (* --- Локальная очередь аварий (сырые строки) --- *)
    awsAlarmQ : ARRAY[1..cQSize] OF WSTRING(120);
    iAQHead : INT;  iAQTail : INT;  iAQCount : INT;

    (* --- Конечный автомат --- *)
    iState     : INT;
    wsLineOut  : WSTRING(122);
    sActivePath : STRING(80);
    wBom       : WORD := 16#FEFF;

    fbFileOpen  : FILE.Open;
    fbFileWrite : FILE.Write;
    fbFileFlush : FILE.Flush;
    fbFileClose : FILE.Close;
    hFile       : FILE.CAA.HANDLE;

    iWrittenCnt : INT;
    iDroppedCnt : INT;

    i          : INT;
    wsTimeStamp : WSTRING(24);
    wsHH : WSTRING(4);  wsMM : WSTRING(4);
    wsDD : WSTRING(4);  wsMo : WSTRING(4);  wsYY : WSTRING(6);
END_VAR


(* ============================================================ *)
(* 1. КАРТА АВАРИЙ (порядок = порядок названий)                 *)
(* ============================================================ *)
axAlarmNow[1]  := xDryRunAlarm;
axAlarmNow[2]  := xDryRunRelayAlarm;
axAlarmNow[3]  := xRefillAttemptsAlarm;
axAlarmNow[4]  := xAlgAlarm;
axAlarmNow[5]  := xBioAlarm;
axAlarmNow[6]  := xPhRelayAlarm;
axAlarmNow[7]  := xAlgRelayAlarm;
axAlarmNow[8]  := xBioRelayAlarm;
axAlarmNow[9]  := xPumpCommError[1];
axAlarmNow[10] := xPumpCommError[2];
axAlarmNow[11] := xMV110_Error;
axAlarmNow[12] := xMU110_Error;


(* ============================================================ *)
(* 2. МЕТКА ВРЕМЕНИ "чч:мм дд.мм.гггг"                          *)
(* ============================================================ *)
wsHH := INT_TO_WSTRING(iCurrentHour);   IF iCurrentHour   < 10 THEN wsHH := WCONCAT("0", wsHH); END_IF;
wsMM := INT_TO_WSTRING(iCurrentMinute); IF iCurrentMinute < 10 THEN wsMM := WCONCAT("0", wsMM); END_IF;
wsDD := INT_TO_WSTRING(iCurrentDay);    IF iCurrentDay    < 10 THEN wsDD := WCONCAT("0", wsDD); END_IF;
wsMo := INT_TO_WSTRING(iCurrentMonth);  IF iCurrentMonth  < 10 THEN wsMo := WCONCAT("0", wsMo); END_IF;
wsYY := INT_TO_WSTRING(iCurrentYear);
wsTimeStamp := WCONCAT(wsHH, WCONCAT(":", WCONCAT(wsMM, WCONCAT(" ",
               WCONCAT(wsDD, WCONCAT(".", WCONCAT(wsMo, WCONCAT(".", wsYY))))))));


(* ============================================================ *)
(* 3. ФРОНТ АВАРИИ → строка в локальную очередь аварий          *)
(* ============================================================ *)
FOR i := 1 TO cAlarmCnt DO
    IF axAlarmNow[i] AND NOT axAlarmPrev[i] THEN
        IF xAlarmLogSDEnable THEN
            IF iAQCount < cQSize THEN
                iAQTail := (iAQTail MOD cQSize) + 1;
                awsAlarmQ[iAQTail] := WCONCAT(wsTimeStamp, WCONCAT(" - ", awsAlarmName[i]));
                iAQCount := iAQCount + 1;
            ELSE
                iDroppedCnt := iDroppedCnt + 1;
            END_IF;
        END_IF;
    END_IF;
    axAlarmPrev[i] := axAlarmNow[i];
END_FOR;


(* ============================================================ *)
(* 4. КОНЕЧНЫЙ АВТОМАТ: 3 файла (аварии → ПЧ → уставки)         *)
(* ============================================================ *)
CASE iState OF

    0:  (* IDLE — выбрать непустую очередь *)
        IF xAlarmLogSDEnable THEN
            IF iAQCount > 0 THEN
                iAQHead := (iAQHead MOD cQSize) + 1;
                wsLineOut := WCONCAT(awsAlarmQ[iAQHead], "$R$N");
                iAQCount := iAQCount - 1;
                sActivePath := sAlarmLogPath;
                iState := 1;
            ELSIF iSdPumpQCount > 0 THEN
                iSdPumpQHead := (iSdPumpQHead MOD 20) + 1;
                wsLineOut := WCONCAT(awsSdPumpQ[iSdPumpQHead], "$R$N");
                iSdPumpQCount := iSdPumpQCount - 1;
                sActivePath := sPumpLogPath;
                iState := 1;
            ELSIF iSdSetpQCount > 0 THEN
                iSdSetpQHead := (iSdSetpQHead MOD 20) + 1;
                wsLineOut := WCONCAT(awsSdSetpQ[iSdSetpQHead], "$R$N");
                iSdSetpQCount := iSdSetpQCount - 1;
                sActivePath := sSetpointLogPath;
                iState := 1;
            END_IF;
        END_IF;

    1:  (* OPEN на дозапись *)
        fbFileOpen(xExecute := TRUE, sFileName := sActivePath, eFileMode := FILE.MODE.MAPPD);
        IF fbFileOpen.xDone THEN
            hFile := fbFileOpen.hFile;
            fbFileOpen(xExecute := FALSE);
            iState := 3;
        ELSIF fbFileOpen.xError THEN
            IF fbFileOpen.eError = FILE.ERROR.NOT_EXIST THEN
                fbFileOpen(xExecute := FALSE);
                iState := 2;
            ELSE
                fbFileOpen(xExecute := FALSE);
                iState := 9;
            END_IF;
        END_IF;

    2:  (* CREATE *)
        fbFileOpen(xExecute := TRUE, sFileName := sActivePath, eFileMode := FILE.MODE.MWRITE);
        IF fbFileOpen.xDone THEN
            hFile := fbFileOpen.hFile;
            fbFileOpen(xExecute := FALSE);
            iState := 6;
        ELSIF fbFileOpen.xError THEN
            fbFileOpen(xExecute := FALSE);
            iState := 9;
        END_IF;

    6:  (* WRITE_BOM *)
        fbFileWrite(xExecute := TRUE, hFile := hFile, pBuffer := ADR(wBom), szSize := UDINT#2);
        IF fbFileWrite.xDone THEN
            fbFileWrite(xExecute := FALSE);
            iState := 3;
        ELSIF fbFileWrite.xError THEN
            fbFileWrite(xExecute := FALSE);
            iState := 5;
        END_IF;

    3:  (* WRITE строки *)
        fbFileWrite(xExecute := TRUE, hFile := hFile,
                    pBuffer := ADR(wsLineOut), szSize := INT_TO_UDINT(WLEN(wsLineOut) * 2));
        IF fbFileWrite.xDone THEN
            fbFileWrite(xExecute := FALSE);
            iWrittenCnt := iWrittenCnt + 1;
            iState := 4;
        ELSIF fbFileWrite.xError THEN
            fbFileWrite(xExecute := FALSE);
            iState := 5;
        END_IF;

    4:  (* FLUSH *)
        fbFileFlush(xExecute := TRUE, hFile := hFile);
        IF fbFileFlush.xDone OR fbFileFlush.xError THEN
            fbFileFlush(xExecute := FALSE);
            iState := 5;
        END_IF;

    5:  (* CLOSE *)
        fbFileClose(xExecute := TRUE, hFile := hFile);
        IF fbFileClose.xDone OR fbFileClose.xError THEN
            fbFileClose(xExecute := FALSE);
            iState := 0;
        END_IF;

    9:  (* DROP *)
        iState := 0;

END_CASE;
