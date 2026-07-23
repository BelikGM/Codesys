(* ============================================================ *)
(* PRG_AlarmLogSD — ЖУРНАЛ АВАРИЙ НА SD-КАРТУ (ДДЮТ)            *)
(* ============================================================ *)
(* По ФРОНТУ появления каждой аварии дописывает в файл на SD     *)
(* строку вида:  "чч:мм дд.мм.гггг - <название аварии>"          *)
(*                                                              *)
(* Зачем: разгрузить RETAIN-память контроллера (журналы ПЧ и     *)
(* уставок её почти исчерпали) — история аварий уходит на карту. *)
(*                                                              *)
(* КОДИРОВКА: строки пишутся как WSTRING (UTF-16LE), в начало     *)
(* нового файла добавляется BOM 0xFF 0xFE — так кириллица         *)
(* корректно открывается в Блокноте/Excel на ПК.                 *)
(*                                                              *)
(* ТРЕБОВАНИЯ:                                                    *)
(*   1. Библиотека "CAA File" в дереве проекта (тянет CAA Types). *)
(*      Тип дескриптора — FILE.CAA.HANDLE (НЕ CAA.HANDLE!).       *)
(*   2. SD-карта: FAT16/FAT32, разделы MBR. Путь по умолчанию     *)
(*      /mnt/ufs/media/mmcblk0p1/  (GVL_Fountain.sAlarmLogPath).  *)
(*                                                              *)
(* Вызывается в PLC_PRG ПОСЛЕ PRG_Fountain (нужны iCurrentHour   *)
(* и т.д.). ФБ CAA File асинхронные — запись идёт конечным        *)
(* автоматом за несколько сканов, цикл ПЛК не блокируется.        *)
(* ============================================================ *)
PROGRAM PRG_AlarmLogSD
VAR CONSTANT
    cAlarmCnt : INT := 12;   // сколько аварий отслеживаем (ДДЮТ)
    cQSize    : INT := 20;   // глубина очереди строк на запись
END_VAR
VAR
    (* --- Список аварий: текущее/прошлое состояние + названия --- *)
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

    (* --- Очередь строк (кольцевой буфер) --- *)
    awsQueue : ARRAY[1..cQSize] OF WSTRING(100);
    iQHead  : INT;
    iQTail  : INT;
    iQCount : INT;

    (* --- Конечный автомат записи --- *)
    iState    : INT;   // 0=IDLE 1=OPEN 2=CREATE 6=BOM 3=WRITE 4=FLUSH 5=CLOSE 9=DROP
    wsLineOut : WSTRING(100);
    wBom      : WORD := 16#FEFF;   // BOM UTF-16LE (в памяти: байты FF FE)

    (* --- Экземпляры ФБ CAA File --- *)
    fbFileOpen  : FILE.Open;
    fbFileWrite : FILE.Write;
    fbFileFlush : FILE.Flush;
    fbFileClose : FILE.Close;
    hFile       : FILE.CAA.HANDLE;

    (* --- Диагностика --- *)
    iWrittenCnt : INT;   // успешно записано строк
    iDroppedCnt : INT;   // отброшено (переполнение очереди)

    (* --- Рабочие --- *)
    i          : INT;
    wsTimeStamp : WSTRING(24);
    wsHH : WSTRING(4);  wsMM : WSTRING(4);
    wsDD : WSTRING(4);  wsMo : WSTRING(4);  wsYY : WSTRING(6);
END_VAR


(* ============================================================ *)
(* 1. КАРТА ОТСЛЕЖИВАЕМЫХ АВАРИЙ (порядок = порядок названий)    *)
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
(* 2. МЕТКА ВРЕМЕНИ ЭТОГО СКАНА "чч:мм дд.мм.гггг"               *)
(* ============================================================ *)
wsHH := INT_TO_WSTRING(iCurrentHour);   IF iCurrentHour   < 10 THEN wsHH := WCONCAT("0", wsHH); END_IF;
wsMM := INT_TO_WSTRING(iCurrentMinute); IF iCurrentMinute < 10 THEN wsMM := WCONCAT("0", wsMM); END_IF;
wsDD := INT_TO_WSTRING(iCurrentDay);    IF iCurrentDay    < 10 THEN wsDD := WCONCAT("0", wsDD); END_IF;
wsMo := INT_TO_WSTRING(iCurrentMonth);  IF iCurrentMonth  < 10 THEN wsMo := WCONCAT("0", wsMo); END_IF;
wsYY := INT_TO_WSTRING(iCurrentYear);
wsTimeStamp := WCONCAT(wsHH, WCONCAT(":", WCONCAT(wsMM, WCONCAT(" ",
               WCONCAT(wsDD, WCONCAT(".", WCONCAT(wsMo, WCONCAT(".", wsYY))))))));


(* ============================================================ *)
(* 3. ДЕТЕКТ ФРОНТА КАЖДОЙ АВАРИИ → строка в очередь             *)
(* ============================================================ *)
FOR i := 1 TO cAlarmCnt DO
    IF axAlarmNow[i] AND NOT axAlarmPrev[i] THEN
        IF xAlarmLogSDEnable THEN
            IF iQCount < cQSize THEN
                iQTail := (iQTail MOD cQSize) + 1;
                (* строка: "чч:мм дд.мм.гггг - <название>" + CRLF *)
                awsQueue[iQTail] := WCONCAT(wsTimeStamp,
                                     WCONCAT(" - ", WCONCAT(awsAlarmName[i], "$R$N")));
                iQCount := iQCount + 1;
            ELSE
                iDroppedCnt := iDroppedCnt + 1;   // очередь полна — теряем строку
            END_IF;
        END_IF;
    END_IF;
    axAlarmPrev[i] := axAlarmNow[i];
END_FOR;


(* ============================================================ *)
(* 4. КОНЕЧНЫЙ АВТОМАТ ЗАПИСИ (асинхронно, CAA File)             *)
(* ============================================================ *)
CASE iState OF

    0:  (* IDLE — если в очереди есть строка, начать запись *)
        IF (iQCount > 0) AND xAlarmLogSDEnable THEN
            iQHead    := (iQHead MOD cQSize) + 1;
            wsLineOut := awsQueue[iQHead];
            iQCount   := iQCount - 1;
            iState    := 1;
        END_IF;

    1:  (* OPEN на дозапись *)
        fbFileOpen(xExecute := TRUE, sFileName := sAlarmLogPath, eFileMode := FILE.MODE.MAPPD);
        IF fbFileOpen.xDone THEN
            hFile := fbFileOpen.hFile;
            fbFileOpen(xExecute := FALSE);
            iState := 3;                 // файл есть — сразу пишем строку
        ELSIF fbFileOpen.xError THEN
            IF fbFileOpen.eError = FILE.ERROR.NOT_EXIST THEN
                fbFileOpen(xExecute := FALSE);
                iState := 2;             // файла нет — создать
            ELSE
                fbFileOpen(xExecute := FALSE);
                iState := 9;             // иная ошибка (карты нет и т.п.) — отбросить строку
            END_IF;
        END_IF;

    2:  (* CREATE — MWRITE создаёт файл при первой записи *)
        fbFileOpen(xExecute := TRUE, sFileName := sAlarmLogPath, eFileMode := FILE.MODE.MWRITE);
        IF fbFileOpen.xDone THEN
            hFile := fbFileOpen.hFile;
            fbFileOpen(xExecute := FALSE);
            iState := 6;                 // новый файл — сперва BOM
        ELSIF fbFileOpen.xError THEN
            fbFileOpen(xExecute := FALSE);
            iState := 9;
        END_IF;

    6:  (* WRITE_BOM — метка UTF-16LE в начало нового файла (2 байта) *)
        fbFileWrite(xExecute := TRUE, hFile := hFile, pBuffer := ADR(wBom), szSize := UDINT#2);
        IF fbFileWrite.xDone THEN
            fbFileWrite(xExecute := FALSE);
            iState := 3;
        ELSIF fbFileWrite.xError THEN
            fbFileWrite(xExecute := FALSE);
            iState := 5;                 // не вышло — всё равно закрыть
        END_IF;

    3:  (* WRITE — строка WSTRING, размер = WLEN*2 байт (UTF-16LE) *)
        fbFileWrite(xExecute := TRUE, hFile := hFile,
                    pBuffer := ADR(wsLineOut), szSize := INT_TO_UDINT(WLEN(wsLineOut) * 2));
        IF fbFileWrite.xDone THEN
            fbFileWrite(xExecute := FALSE);
            iWrittenCnt := iWrittenCnt + 1;
            iState := 4;
        ELSIF fbFileWrite.xError THEN
            fbFileWrite(xExecute := FALSE);
            iState := 5;                 // всё равно закрыть дескриптор
        END_IF;

    4:  (* FLUSH — гарантированно сбросить буфер на карту *)
        fbFileFlush(xExecute := TRUE, hFile := hFile);
        IF fbFileFlush.xDone OR fbFileFlush.xError THEN
            fbFileFlush(xExecute := FALSE);
            iState := 5;
        END_IF;

    5:  (* CLOSE — закрыть дескриптор, вернуться в IDLE *)
        fbFileClose(xExecute := TRUE, hFile := hFile);
        IF fbFileClose.xDone OR fbFileClose.xError THEN
            fbFileClose(xExecute := FALSE);
            iState := 0;
        END_IF;

    9:  (* DROP — строку не записали (ошибка открытия), едем дальше *)
        iState := 0;

END_CASE;

(* Диагностика (iWrittenCnt/iDroppedCnt/iState) — локальная; при      *)
(* необходимости вынесу в GVL для вывода на экран.                    *)
