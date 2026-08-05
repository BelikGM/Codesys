(* ============================================================ *)
(* PRG_AlarmLogSD — ЖУРНАЛЫ НА SD-КАРТУ (3 файла В МЕСЯЦ)        *)
(* ============================================================ *)
(* Пишет на SD три отдельных журнала (чтобы записи не путались): *)
(*   • АВАРИИ     → sAlarmLogPath   (alarms-MM-YYYY.log)         *)
(*   • ИЗМЕНЕНИЯ ПЧ→ sPumpLogPath    (pump_changes-MM-YYYY.log)  *)
(*   • УСТАВКИ    → sSetpointLogPath (setpoints-MM-YYYY.log)     *)
(*                                                              *)
(* === НОВОЕ: ПОМЕСЯЧНЫЕ ФАЙЛЫ ==============================    *)
(* Имя файла содержит месяц и год, поэтому 1-го числа нового     *)
(* месяца путь меняется САМ, и старый автомат (OPEN → если нет   *)
(* файла, то CREATE + BOM) создаёт новый файл без единой строчки *)
(* дополнительной логики. Отдельного «переключателя месяца» нет  *)
(* специально: любая пропущенная граница (ПЛК был выключен,      *)
(* карту вынимали) отрабатывается сама собой при первой записи.  *)
(*                                                              *)
(* === НОВОЕ: КОНТРОЛЬ МЕСТА ================================    *)
(* FB_SdSpaceGuard раз в tSdCheckPeriod (по умолчанию час), при  *)
(* смене месяца и после серии неудачных записей удаляет три файла *)
(* самого старого месяца, если журналы переросли квоту:            *)
(*     квота = ёмкость карты − 100 МБ резерва − чужие файлы        *)
(* Файл текущего месяца удалить нельзя ни при каких условиях.      *)
(*                                                               *)
(* ЁМКОСТЬ КАРТЫ ОПРЕДЕЛЯЕТСЯ АВТОМАТИЧЕСКИ — FB_SdCardSize        *)
(* читает размер раздела у ядра (/sys/block/...). Номинал из       *)
(* выпадающего списка на экране (iSdCardSize) — только запасной    *)
(* вариант, если автоопределение не сработало. Кнопок нет.         *)
(*                                                              *)
(* Строка: "чч:мм дд.мм.гггг - текст" (для аварий) либо готовая  *)
(* строка журнала (для ПЧ/уставок). WSTRING/UTF-16LE + BOM.     *)
(*                                                              *)
(* Аварии детектируются здесь СТРОГО ПО ФРОНТУ FALSE→TRUE: пока  *)
(* авария висит, повторных записей нет. Изменения ПЧ/уставок     *)
(* кладут строку в глобальные очереди GVL_Fountain.awsSdPumpQ /  *)
(* awsSdSetpQ прямо из F_PumpLogWrite / F_FountainLogWrite —      *)
(* здесь мы их только забираем и пишем в файл.                   *)
(*                                                              *)
(* Один конечный автомат обслуживает по очереди все три файла    *)
(* (приоритет: аварии → ПЧ → уставки). ФБ CAA File асинхронные.  *)
(* Пока сторож места занят (fbGuard.xBusy) — новая строка не     *)
(* начинается, строки ждут в очередях.                           *)
(*                                                              *)
(* ТРЕБОВАНИЯ: библиотека CAA File (тип FILE.CAA.HANDLE), карта   *)
(* SD FAT16/FAT32 MBR, путь /mnt/ufs/media/mmcblk0p1/.           *)
(* ============================================================ *)
PROGRAM PRG_AlarmLogSD
VAR CONSTANT
    cAlarmCnt       : INT := 11;   // сколько аварий отслеживаем
    cQSize          : INT := 20;   // глубина очереди строк
    cWriteFailForce : INT := 3;    // столько неудачных записей подряд =
                                   // карта полна → удалить старый месяц
END_VAR
VAR
    (* --- Аварии: состояние + названия --- *)
    axAlarmNow  : ARRAY[1..cAlarmCnt] OF BOOL;
    axAlarmPrev : ARRAY[1..cAlarmCnt] OF BOOL;
    awsAlarmName : ARRAY[1..cAlarmCnt] OF WSTRING(60) := [
        "Сухой ход",
        "Сухой ход реле",
        "Клапан добора реле",
        "Насосы фонтана реле",
        "Подсветка реле",
        "Фильтрация реле (ручной режим)",
        "Связь ПЧ1",
        "Связь ПЧ2",
        "Связь ПЧ3",
        "Связь МВ-Д",
        "Связь МУ"];

    (* --- Локальная очередь аварий (сырые строки, без CRLF) --- *)
    awsAlarmQ : ARRAY[1..cQSize] OF WSTRING(120);
    iAQHead : INT;  iAQTail : INT;  iAQCount : INT;

    (* --- Конечный автомат записи --- *)
    iState     : INT;   // 0=IDLE 1=OPEN 2=CREATE 6=BOM 3=WRITE 4=FLUSH 5=CLOSE 9=DROP
    wsLineOut  : WSTRING(122);
    sActivePath : STRING(80);
    wBom       : WORD := 16#FEFF;   // BOM UTF-16LE (байты FF FE)

    (* --- ФБ CAA File --- *)
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

    (* --- Помесячные файлы --- *)
    iLogYear      : INT;    // год/месяц, в которые сейчас пишем
    iLogMonth     : INT;
    iLogYearPrev  : INT;    // 0 при старте → пути соберутся в 1-м же цикле
    iLogMonthPrev : INT;

    (* --- Сторож места на карте --- *)
    fbGuard         : FB_SdSpaceGuard;
    fbCardSize      : FB_SdCardSize;   // автоопределение ёмкости карты
    tonSdCheck      : TON;
    xGuardTrig      : BOOL;
    xGuardStart     : BOOL;
    xCapTrig        : BOOL;   // перечитать ёмкость карты
    xGuardForceAuto : BOOL;   // авто-форс: карта полна (серия отказов записи)
    iWriteFailCnt   : INT;    // неудачных записей подряд
END_VAR


(* ============================================================ *)
(* 1. КАРТА АВАРИЙ (порядок = порядок названий)                 *)
(* ============================================================ *)
axAlarmNow[1]  := xDryRunAlarm;
axAlarmNow[2]  := xDryRunRelayAlarm;
axAlarmNow[3]  := xDamperRelayAlarm;
axAlarmNow[4]  := xPumpRelayAlarm;
axAlarmNow[5]  := xLightRelayAlarm;
axAlarmNow[6]  := xNfManualRelayAlarm;
axAlarmNow[7]  := xPumpCommError[1];
axAlarmNow[8]  := xPumpCommError[2];
axAlarmNow[9]  := xPumpCommError[3];
axAlarmNow[10] := xMV110_Error;
axAlarmNow[11] := xMU110_Error;


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
(* 4. ПУТИ ФАЙЛОВ ТЕКУЩЕГО МЕСЯЦА                               *)
(* ============================================================ *)
(* Если RTC ещё не готов или сбит (села батарейка) — год выйдет  *)
(* за 2000..2199. Писать в "alarms-01-1970.log" нельзя (такой     *)
(* месяц не разберётся обратно и файл станет неудаляемым), поэтому*)
(* весь «бесчасовой» период сваливаем в один файл 01-2000. Он     *)
(* заведомо самый старый по ключу, то есть удалится первым, когда *)
(* место кончится, — и при этом защищён как «текущий», пока RTC   *)
(* не починят.                                                   *)
IF iCurrentYear >= 2000 AND iCurrentYear <= 2199
   AND iCurrentMonth >= 1 AND iCurrentMonth <= 12 THEN
    iLogYear  := iCurrentYear;
    iLogMonth := iCurrentMonth;
    xSdRtcBad := FALSE;
ELSE
    iLogYear  := 2000;
    iLogMonth := 1;
    xSdRtcBad := TRUE;
END_IF;

IF iLogYear <> iLogYearPrev OR iLogMonth <> iLogMonthPrev THEN
    sAlarmLogPath    := F_SdLogPath(sSdLogDir, sAlarmLogPrefix, iLogYear, iLogMonth);
    sPumpLogPath     := F_SdLogPath(sSdLogDir, sPumpLogPrefix,  iLogYear, iLogMonth);
    sSetpointLogPath := F_SdLogPath(sSdLogDir, sSetpLogPrefix,  iLogYear, iLogMonth);
    iLogYearPrev     := iLogYear;
    iLogMonthPrev    := iLogMonth;
    xGuardTrig       := TRUE;    // новый месяц — сразу проверить место
    xCapTrig         := TRUE;    // и заодно перечитать ёмкость карты
END_IF;


(* ============================================================ *)
(* 5. СТОРОЖ МЕСТА НА КАРТЕ                                     *)
(* ============================================================ *)
(* Периодический тик (самосброс: Q взводится на 1 цикл за период) *)
tonSdCheck(IN := NOT tonSdCheck.Q, PT := tSdCheckPeriod);
IF tonSdCheck.Q THEN
    xCapTrig   := TRUE;
    xGuardTrig := TRUE;
END_IF;

(* --- ЁМКОСТЬ КАРТЫ ---                                           *)
(* Сначала пробуем определить её САМИ (FB_SdCardSize читает размер *)
(* раздела у ядра). Получилось — номинал из списка не нужен вообще. *)
(* Не получилось — берём выбранный на экране номинал.               *)
fbCardSize(xTrigger := xCapTrig AND (iState = 0) AND NOT fbGuard.xBusy,
           sSysPath := sSdCardSysPath);
IF fbCardSize.xBusy THEN
    xCapTrig := FALSE;
END_IF;

xSdCapAuto       := fbCardSize.xValid;
udiSdCapAutoMB   := fbCardSize.udiCapacityMB;
udiSdCardSectors := fbCardSize.udiSectors;

IF iSdCardSize < 0 THEN iSdCardSize := 0; END_IF;
IF iSdCardSize > 6 THEN iSdCardSize := 6; END_IF;

IF xSdCapAuto THEN
    udiSdUsableMB := udiSdCapAutoMB;
ELSE
    udiSdUsableMB := audiSdCardMB[iSdCardSize];
END_IF;

(* АВАРИЙНЫЙ ФОРС. Если запись не проходит подряд cWriteFailForce  *)
(* раз — карта реально полна, что бы ни говорил расчёт по номиналу *)
(* (например, в списке выбрали 32 ГБ, а стоит карта на 16). Тогда  *)
(* удаляем самый старый месяц безусловно. Одиночный сбой записи к  *)
(* удалению НЕ приводит — только серия подряд.                     *)
IF iWriteFailCnt >= cWriteFailForce THEN
    xGuardTrig      := TRUE;
    xGuardForceAuto := TRUE;
    iWriteFailCnt   := 0;
END_IF;

(* Запускаем сторожа ТОЛЬКО когда автомат записи стоит в IDLE:     *)
(* так исключено удаление файла при открытом дескрипторе.          *)
xGuardStart := xGuardTrig AND xAlarmLogSDEnable
               AND (iState = 0) AND NOT fbGuard.xBusy AND NOT fbCardSize.xBusy;

fbGuard(xTrigger      := xGuardStart,
        xForce        := xGuardForceAuto,
        sDir          := sSdLogDir,
        sPrefix1      := sAlarmLogPrefix,
        sPrefix2      := sPumpLogPrefix,
        sPrefix3      := sSetpLogPrefix,
        udiUsableMB   := udiSdUsableMB,
        udiFreeMinMB  := udiSdFreeMinMB,
        iCurYear      := iLogYear,
        iCurMonth     := iLogMonth);

IF fbGuard.xBusy THEN
    xGuardTrig      := FALSE;
    xGuardForceAuto := FALSE;
END_IF;

(* Диагностика на экран *)
udiSdQuotaMB       := fbGuard.udiQuotaMB;
udiSdOursMB        := fbGuard.udiOursMB;
udiSdUsedMB        := fbGuard.udiUsedMB;
udiSdForeignMB     := fbGuard.udiForeignMB;
udiSdOldestMB      := fbGuard.udiOldestMB;
xSdNothingToDelete := fbGuard.xNothingToDelete;
xSdLogQuotaStop    := fbGuard.xQuotaStop;
xSdCleanupFault    := fbGuard.xFault;
iSdDeletedTotal    := fbGuard.iDeletedTotal;
sSdLastDeleted     := fbGuard.sLastDeleted;


(* ============================================================ *)
(* 6. КОНЕЧНЫЙ АВТОМАТ: пишет по очереди 3 файла                *)
(*    приоритет: аварии → изменения ПЧ → уставки               *)
(* ============================================================ *)
(* Запись стоит, пока сторож занят (иначе он удалял бы файл с    *)
(* открытым дескриптором) ИЛИ пока поднят xQuotaStop — последний *)
(* рубеж защиты карты: наши журналы упёрлись в квоту, а удалять   *)
(* уже нечего. Строки при этом копятся в очередях, лишние         *)
(* считаются в iDroppedCnt; журналы на экране ведутся как обычно. *)
IF NOT fbGuard.xBusy AND NOT fbCardSize.xBusy AND NOT fbGuard.xQuotaStop THEN

CASE iState OF

    0:  (* IDLE — выбрать непустую очередь, взять строку, начать *)
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

    2:  (* CREATE — MWRITE создаёт файл *)
        fbFileOpen(xExecute := TRUE, sFileName := sActivePath, eFileMode := FILE.MODE.MWRITE);
        IF fbFileOpen.xDone THEN
            hFile := fbFileOpen.hFile;
            fbFileOpen(xExecute := FALSE);
            iState := 6;
        ELSIF fbFileOpen.xError THEN
            fbFileOpen(xExecute := FALSE);
            iState := 9;
        END_IF;

    6:  (* WRITE_BOM — метка UTF-16LE в начало нового файла *)
        fbFileWrite(xExecute := TRUE, hFile := hFile, pBuffer := ADR(wBom), szSize := UDINT#2);
        IF fbFileWrite.xDone THEN
            fbFileWrite(xExecute := FALSE);
            iState := 3;
        ELSIF fbFileWrite.xError THEN
            fbFileWrite(xExecute := FALSE);
            xSdWriteFault := TRUE;
            xGuardTrig    := TRUE;
            iWriteFailCnt := iWriteFailCnt + 1;      // не пишется — проверить место
            iState := 5;
        END_IF;

    3:  (* WRITE — строка WSTRING, размер = WLEN*2 байт *)
        fbFileWrite(xExecute := TRUE, hFile := hFile,
                    pBuffer := ADR(wsLineOut), szSize := INT_TO_UDINT(WLEN(wsLineOut) * 2));
        IF fbFileWrite.xDone THEN
            fbFileWrite(xExecute := FALSE);
            iWrittenCnt := iWrittenCnt + 1;
            xSdWriteFault := FALSE;
            iWriteFailCnt := 0;         // запись прошла — серия отказов сброшена
            iState := 4;
        ELSIF fbFileWrite.xError THEN
            fbFileWrite(xExecute := FALSE);
            xSdWriteFault := TRUE;
            xGuardTrig    := TRUE;
            iWriteFailCnt := iWriteFailCnt + 1;
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

    9:  (* DROP — ошибка открытия/создания, едем дальше *)
        xSdWriteFault := TRUE;
        xGuardTrig    := TRUE;
        iWriteFailCnt := iWriteFailCnt + 1;
        iState := 0;

END_CASE;

END_IF;
