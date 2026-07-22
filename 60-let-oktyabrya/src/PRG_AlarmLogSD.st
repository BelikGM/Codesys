(* ============================================================ *)
(* PRG_AlarmLogSD — ЖУРНАЛ АВАРИЙ НА SD-КАРТУ                   *)
(* ============================================================ *)
(* По ФРОНТУ появления каждой аварии дописывает в файл на SD     *)
(* строку вида:  "чч:мм дд.мм.гггг - <название аварии>"          *)
(*                                                              *)
(* Зачем: разгрузить RETAIN-память контроллера (журналы ПЧ и     *)
(* уставок её почти исчерпали) — история аварий уходит на карту. *)
(*                                                              *)
(* ⚠️ ТРЕБОВАНИЯ ПЕРЕД ЗАПУСКОМ (проверить на объекте):          *)
(*   1. В дерево проекта добавить библиотеку "CAA File"          *)
(*      (Менеджер библиотек → Добавить). С ней подтянется        *)
(*      "CAA Types" (нужен тип CAA.HANDLE).                      *)
(*   2. SD-карта: FAT16/FAT32, разделы MBR, вставлена и          *)
(*      примонтирована. Путь по умолчанию                        *)
(*      /mnt/ufs/media/mmcblk0p1/  (GVL_Fountain.sAlarmLogPath). *)
(*   3. Кириллица в файле: строки пишутся как STRING (как в       *)
(*      официальном примере ОВЕН). Если в файле кириллица         *)
(*      окажется «кракозябрами» — сообщи, переведём буфер строки  *)
(*      на WSTRING (UTF-16) или на латиницу.                     *)
(*                                                              *)
(* Вызывается в PLC_PRG ПОСЛЕ PRG_Fountain (нужны iCurrentHour   *)
(* и т.д.). Файловые ФБ CAA File асинхронные — запись идёт        *)
(* конечным автоматом за несколько сканов, цикл ПЛК не блокирует. *)
(* ============================================================ *)
PROGRAM PRG_AlarmLogSD
VAR CONSTANT
    cAlarmCnt : INT := 11;   // сколько аварий отслеживаем
    cQSize    : INT := 20;   // глубина очереди строк на запись
END_VAR
VAR
    (* --- Список аварий: текущее/прошлое состояние + названия --- *)
    axAlarmNow  : ARRAY[1..cAlarmCnt] OF BOOL;
    axAlarmPrev : ARRAY[1..cAlarmCnt] OF BOOL;
    asAlarmName : ARRAY[1..cAlarmCnt] OF STRING(60) := [
        'Сухой ход',
        'Сухой ход реле',
        'Клапан добора реле',
        'Насосы фонтана реле',
        'Подсветка реле',
        'Фильтрация реле (ручной режим)',
        'Связь ПЧ1',
        'Связь ПЧ2',
        'Связь ПЧ3',
        'Связь МВ-Д',
        'Связь МУ'];

    (* --- Очередь строк (кольцевой буфер) --- *)
    asQueue : ARRAY[1..cQSize] OF STRING(100);
    iQHead  : INT;
    iQTail  : INT;
    iQCount : INT;

    (* --- Конечный автомат записи --- *)
    iState   : INT;   // 0=IDLE 1=OPEN 2=CREATE 3=WRITE 4=FLUSH 5=CLOSE 9=DROP
    sLineOut : STRING(100);

    (* --- Экземпляры ФБ CAA File --- *)
    fbFileOpen  : FILE.Open;
    fbFileWrite : FILE.Write;
    fbFileFlush : FILE.Flush;
    fbFileClose : FILE.Close;
    hFile       : CAA.HANDLE;

    (* --- Диагностика --- *)
    iWrittenCnt : INT;   // успешно записано строк
    iDroppedCnt : INT;   // отброшено (переполнение очереди)

    (* --- Рабочие --- *)
    i          : INT;
    sTimeStamp : STRING(24);
    sHH : STRING(4);  sMM : STRING(4);
    sDD : STRING(4);  sMo : STRING(4);  sYY : STRING(6);
END_VAR


(* ============================================================ *)
(* 1. КАРТА ОТСЛЕЖИВАЕМЫХ АВАРИЙ (порядок = порядок названий)    *)
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
(* 2. МЕТКА ВРЕМЕНИ ЭТОГО СКАНА "чч:мм дд.мм.гггг"               *)
(* ============================================================ *)
sHH := INT_TO_STRING(iCurrentHour);   IF iCurrentHour   < 10 THEN sHH := CONCAT('0', sHH); END_IF;
sMM := INT_TO_STRING(iCurrentMinute); IF iCurrentMinute < 10 THEN sMM := CONCAT('0', sMM); END_IF;
sDD := INT_TO_STRING(iCurrentDay);    IF iCurrentDay    < 10 THEN sDD := CONCAT('0', sDD); END_IF;
sMo := INT_TO_STRING(iCurrentMonth);  IF iCurrentMonth  < 10 THEN sMo := CONCAT('0', sMo); END_IF;
sYY := INT_TO_STRING(iCurrentYear);
sTimeStamp := CONCAT(sHH, CONCAT(':', CONCAT(sMM, CONCAT(' ',
              CONCAT(sDD, CONCAT('.', CONCAT(sMo, CONCAT('.', sYY))))))));


(* ============================================================ *)
(* 3. ДЕТЕКТ ФРОНТА КАЖДОЙ АВАРИИ → строка в очередь             *)
(* ============================================================ *)
FOR i := 1 TO cAlarmCnt DO
    IF axAlarmNow[i] AND NOT axAlarmPrev[i] THEN
        IF xAlarmLogSDEnable THEN
            IF iQCount < cQSize THEN
                iQTail := (iQTail MOD cQSize) + 1;
                (* строка: "чч:мм дд.мм.гггг - <название>" + CRLF *)
                asQueue[iQTail] := CONCAT(sTimeStamp,
                                    CONCAT(' - ', CONCAT(asAlarmName[i], '$R$N')));
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
            iQHead   := (iQHead MOD cQSize) + 1;
            sLineOut := asQueue[iQHead];
            iQCount  := iQCount - 1;
            iState   := 1;
        END_IF;

    1:  (* OPEN на дозапись *)
        fbFileOpen(xExecute := TRUE, sFileName := sAlarmLogPath, eFileMode := FILE.MODE.MAPPD);
        IF fbFileOpen.xDone THEN
            hFile := fbFileOpen.hFile;
            fbFileOpen(xExecute := FALSE);
            iState := 3;
        ELSIF fbFileOpen.xError THEN
            IF fbFileOpen.eError = FILE.ERROR.NOT_EXIST THEN
                fbFileOpen(xExecute := FALSE);
                iState := 2;   // файла нет — создать
            ELSE
                fbFileOpen(xExecute := FALSE);
                iState := 9;   // иная ошибка (карты нет и т.п.) — отбросить строку
            END_IF;
        END_IF;

    2:  (* CREATE — MWRITE создаёт файл при первой записи *)
        fbFileOpen(xExecute := TRUE, sFileName := sAlarmLogPath, eFileMode := FILE.MODE.MWRITE);
        IF fbFileOpen.xDone THEN
            hFile := fbFileOpen.hFile;
            fbFileOpen(xExecute := FALSE);
            iState := 3;
        ELSIF fbFileOpen.xError THEN
            fbFileOpen(xExecute := FALSE);
            iState := 9;
        END_IF;

    3:  (* WRITE — пишем строку (STRING, по LEN байт) *)
        fbFileWrite(xExecute := TRUE, hFile := hFile,
                    pBuffer := ADR(sLineOut), szSize := INT_TO_UDINT(LEN(sLineOut)));
        IF fbFileWrite.xDone THEN
            fbFileWrite(xExecute := FALSE);
            iWrittenCnt := iWrittenCnt + 1;
            iState := 4;
        ELSIF fbFileWrite.xError THEN
            fbFileWrite(xExecute := FALSE);
            iState := 5;   // всё равно закрыть дескриптор
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

(* Экспорт диагностики в GVL при желании — можно завести на экран:  *)
(*   iAlarmLogSDWritten, iAlarmLogSDDropped, iAlarmLogSDState.       *)
(* Здесь оставлены локальными (iWrittenCnt/iDroppedCnt/iState),      *)
(* чтобы не раздувать GVL; при необходимости — подниму в глобальные. *)
