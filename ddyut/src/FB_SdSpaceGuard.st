(* ============================================================ *)
(* FB_SdSpaceGuard — СТОРОЖ МЕСТА НА SD + УДАЛЕНИЕ САМОГО        *)
(*                   СТАРОГО МЕСЯЦА ЖУРНАЛОВ                     *)
(* ============================================================ *)
(* Ёмкость карты приходит на вход udiUsableMB: её определяет сам   *)
(* FB_SdCardSize (читает размер раздела у ядра), а если не вышло — *)
(* берётся номинал из выпадающего списка на экране (iSdCardSize).  *)
(*                                                               *)
(* ЧТО ДЕЛАЕТ ЗА ОДИН ЗАПУСК (фронт xTrigger):                    *)
(*   1. Обходит каталог журналов (DirOpen → DirList → DirClose):  *)
(*      считает, сколько занимают НАШИ журналы и сколько чужие,   *)
(*      и ищет САМЫЙ СТАРЫЙ месяц.                               *)
(*   2. Считает потолок:                                          *)
(*        квота = ёмкость карты − резерв 100 МБ − чужие файлы     *)
(*      То есть журналам достаётся ВСЯ карта, кроме резерва: на   *)
(*      32 ГБ это ~28,9 ГБ, на 2 ГБ ~1,7 ГБ. Ничего не пропадает. *)
(*   3. Если наши журналы переросли квоту — удаляет ТРИ файла     *)
(*      самого старого месяца и повторяет с пункта 1, пока не     *)
(*      уложится.                                                *)
(*                                                               *)
(* ⚠️ В квоту считается объём ТОЛЬКО наших файлов (прошедших       *)
(* разбор F_SdLogMonthKey), а чужие вычитаются из ёмкости — так    *)
(* чей-то архив на карте уменьшает наш потолок, но удалён быть не  *)
(* может. Содержимое ВЛОЖЕННЫХ папок не считается (DirList в       *)
(* глубину не ходит) — папку app.spk1xxm01 с загрузочным           *)
(* приложением (единицы МБ) перекрывает резерв в 100 МБ.           *)
(*                                                               *)
(* ЗАЩИТЫ ОТ УДАЛЕНИЯ ЛИШНЕГО:                                    *)
(*   • Удаляются только имена, ТОЧНО совпавшие с шаблоном         *)
(*     "<префикс>MM-YYYY.log" (разбор в F_SdLogMonthKey).         *)
(*   • Файл текущего месяца (в который идёт запись) не может быть *)
(*     удалён в принципе: кандидат обязан быть СТРОГО СТАРШЕ.     *)
(*   • Сравнение по числовому ключу YYYY*12+MM-1, а не по строке: *)
(*     12-2025 корректно старше 01-2026.                          *)
(*   • Каталоги (deDirEntry.xDirectory) пропускаются целиком.      *)
(*   • Если обход каталога оборвался по лимиту — «самый старый»   *)
(*     недостоверен, и не удаляется НИЧЕГО.                       *)
(*                                                               *)
(* ЕСЛИ УДАЛЯТЬ УЖЕ НЕЧЕГО, А КВОТА ВСЁ РАВНО ПРЕВЫШЕНА           *)
(* (вся история — это один текущий месяц, раздутый дребезгом      *)
(* аварий), поднимается xQuotaStop, и PRG_AlarmLogSD ПРЕКРАЩАЕТ   *)
(* запись на карту. Это последний рубеж: карта не переполнится    *)
(* никогда, фонтан работает, журналы на экране ведутся как        *)
(* обычно. Снимается само при смене месяца, когда раздутый файл   *)
(* станет прошлым и его можно будет удалить. Человек не нужен.    *)
(*                                                               *)
(* ЕДИНИЦЫ. Внутри всё в КиБ (1024 байта), наружу и в пороги — в   *)
(* МиБ (1024 КиБ = 1 048 576 байт). 100 МБ = 104 857 600 байт.    *)
(* Деление целочисленное: оценка свободного всегда чуть ЗАНИЖЕНА, *)
(* то есть чистка срабатывает на доли мегабайта РАНЬШЕ.           *)
(*                                                               *)
(* ФБ асинхронный: один запуск растянут на много циклов ПЛК       *)
(* (каждый ФБ CAA File требует минимум цикл). Пока xBusy = TRUE,  *)
(* PRG_AlarmLogSD не начинает новую запись строки.                *)
(* ============================================================ *)
FUNCTION_BLOCK FB_SdSpaceGuard
VAR_INPUT
    xTrigger      : BOOL;        (* ФРОНТ — выполнить проверку *)
    xForce        : BOOL;        (* уровень, читается при старте: удалить    *)
                                 (* самый старый месяц БЕЗ проверок. Ставится*)
                                 (* автоматически, когда запись на карту не  *)
                                 (* проходит подряд несколько раз (значит,   *)
                                 (* карта реально полна — например, номинал  *)
                                 (* в списке выбран больше настоящего).      *)
    sDir          : STRING(80);  (* каталог журналов, БЕЗ '/' в конце *)
    sPrefix1      : STRING(20);  (* 'alarms-' *)
    sPrefix2      : STRING(20);  (* 'pump_changes-' *)
    sPrefix3      : STRING(20);  (* 'setpoints-' *)
    udiUsableMB   : UDINT;       (* полезная ёмкость карты, МиБ *)
    udiFreeMinMB  : UDINT;       (* резерв свободного места, МиБ (100) *)
    iCurYear      : INT;         (* текущий год  журнала (2000..2199) *)
    iCurMonth     : INT;         (* текущий месяц журнала (1..12) *)
END_VAR
VAR_OUTPUT
    xBusy            : BOOL;
    xDone            : BOOL;      (* импульс 1 цикл по завершении запуска *)
    xQuotaStop       : BOOL;      (* ⛔ писать на SD больше нельзя *)
    udiQuotaMB       : UDINT;     (* сколько реально отдано журналам, МиБ *)
    udiOursMB        : UDINT;     (* занято НАШИМИ журналами, МиБ *)
    udiUsedMB        : UDINT;     (* занято всеми файлами каталога, МиБ *)
    udiForeignMB     : UDINT;     (* занято чужими файлами рядом, МиБ *)
    udiOldestMB      : UDINT;     (* объём самого старого месяца, МиБ *)
    xNothingToDelete : BOOL;      (* чистить надо, а удалять нечего *)
    xFault           : BOOL;      (* карта/каталог недоступны, скан сорван *)
    iDeletedTotal    : INT;       (* удалено файлов с момента старта ПЛК *)
    iDeletedLast     : INT;       (* удалено за последний запуск *)
    sLastDeleted     : STRING(80);(* что удалили последним *)
    iFilesSeen       : INT;       (* файлов в каталоге на последнем скане *)
END_VAR
VAR CONSTANT
    cMaxRounds  : INT := 24;      (* не больше 24 месяцев за один запуск *)
    cMaxEntries : INT := 500;     (* страховка от бесконечного DirList *)
END_VAR
VAR
    iSt        : INT;
    xTrigPrev  : BOOL;
    iRound     : INT;

    fbDirOpen  : FILE.DirOpen;
    fbDirList  : FILE.DirList;
    fbDirClose : FILE.DirClose;
    fbDelete   : FILE.Delete;
    hDir       : FILE.CAA.HANDLE;

    udiUsedKB    : UDINT;   (* все файлы каталога, КиБ (диагностика) *)
    udiOursKB    : UDINT;   (* только наши журналы, КиБ (для квоты) *)
    udiEntryKB   : UDINT;
    udiCurKey    : UDINT;
    udiOldKey    : UDINT;
    udiOldestKB  : UDINT;   (* объём файлов самого старого месяца, КиБ *)
    udiKey       : UDINT;
    xFoundOld    : BOOL;
    xForceRun    : BOOL;
    xOverQuota   : BOOL;
    iEntries     : INT;
    sEntry       : STRING(255);

    iOldYear        : INT;
    iOldMonth       : INT;
    iDelIdx         : INT;
    iDelOkThisRound : INT;
    sDelPath        : STRING(80);
END_VAR


(* ============================================================ *)
(* ЗАПУСК ПО ФРОНТУ                                             *)
(* ============================================================ *)
IF xTrigger AND NOT xTrigPrev AND iSt = 0 THEN
    xForceRun := xForce;      (* режим запуска фиксируем в момент старта *)
    iSt := 10;
END_IF;
xTrigPrev := xTrigger;

xDone := FALSE;
xBusy := (iSt <> 0);


CASE iSt OF

    0:  (* IDLE *)
        ;

    10: (* НАЧАЛО ЗАПУСКА *)
        iRound           := 0;
        iDeletedLast     := 0;
        xNothingToDelete := FALSE;
        xFault           := FALSE;
        iSt := 11;

    11: (* НАЧАЛО РАУНДА — подготовка скана каталога *)
        IF iCurYear < 2000 OR iCurYear > 2199 OR iCurMonth < 1 OR iCurMonth > 12 THEN
            (* без достоверного «сегодня» нельзя понять, какой месяц    *)
            (* трогать нельзя → не удаляем НИЧЕГО                        *)
            xFault := TRUE;
            iSt := 90;
        ELSE
            udiCurKey    := INT_TO_UDINT(iCurYear) * 12 + INT_TO_UDINT(iCurMonth) - 1;
            udiUsedKB    := 0;
            udiOursKB    := 0;
            udiOldKey    := 0;
            udiOldestKB  := 0;
            xFoundOld    := FALSE;
            iEntries     := 0;
            iSt := 12;
        END_IF;

    12: (* DirOpen *)
        fbDirOpen(xExecute := TRUE, sDirName := sDir);
        IF fbDirOpen.xDone THEN
            hDir := fbDirOpen.hDir;
            fbDirOpen(xExecute := FALSE);
            iSt := 13;
        ELSIF fbDirOpen.xError THEN
            fbDirOpen(xExecute := FALSE);
            xFault := TRUE;          (* карты нет / каталог недоступен *)
            iSt := 90;
        END_IF;

    13: (* DirList — по ОДНОЙ записи за вызов, до NO_MORE_ENTRIES *)
        fbDirList(xExecute := TRUE, hDir := hDir);
        IF fbDirList.xDone THEN
            IF NOT fbDirList.deDirEntry.xDirectory THEN
                sEntry := fbDirList.deDirEntry.sEntry;

                (* объём: округляем вверх до КиБ — оценка занятого места     *)
                (* получается чуть больше реальной суммы байт, это в нужную  *)
                (* сторону (реальный расход по кластерам FAT ещё больше)     *)
                udiEntryKB := (fbDirList.deDirEntry.szSize / 1024) + 1;
                udiUsedKB  := udiUsedKB + udiEntryKB;

                (* наш ли это файл и за какой месяц *)
                udiKey := F_SdLogMonthKey(sEntry, sPrefix1);
                IF udiKey = 0 THEN udiKey := F_SdLogMonthKey(sEntry, sPrefix2); END_IF;
                IF udiKey = 0 THEN udiKey := F_SdLogMonthKey(sEntry, sPrefix3); END_IF;

                IF udiKey > 0 THEN
                    (* КВОТА считается только по НАШИМ файлам *)
                    udiOursKB := udiOursKB + udiEntryKB;

                    (* кандидат на удаление — только СТРОГО СТАРШЕ текущего *)
                    IF udiKey < udiCurKey THEN
                        IF NOT xFoundOld OR udiKey < udiOldKey THEN
                            (* нашли месяц старее — объём считаем заново *)
                            udiOldKey   := udiKey;
                            udiOldestKB := udiEntryKB;
                            xFoundOld   := TRUE;
                        ELSIF udiKey = udiOldKey THEN
                            (* ещё один файл того же самого старого месяца *)
                            udiOldestKB := udiOldestKB + udiEntryKB;
                        END_IF;
                    END_IF;
                END_IF;
            END_IF;

            iEntries := iEntries + 1;
            fbDirList(xExecute := FALSE);
            IF iEntries >= cMaxEntries THEN
                (* Каталог не дочитан до конца → «самый старый месяц»         *)
                (* определён по неполному списку и может быть НЕ самым старым. *)
                (* Удалять по недостоверным данным нельзя: закрываем каталог   *)
                (* и выходим с аварией. 500 файлов — это ~13 лет журналов,     *)
                (* столько бывает только если на карте лежит что-то чужое.     *)
                xFault := TRUE;
                iSt := 14;
            END_IF;
        ELSIF fbDirList.xError THEN
            (* штатное окончание обхода = ERROR.NO_MORE_ENTRIES *)
            fbDirList(xExecute := FALSE);
            iSt := 14;
        END_IF;

    14: (* DirClose — закрыть каталог НАДО в любом случае, даже по аварии *)
        fbDirClose(xExecute := TRUE, hDir := hDir);
        IF fbDirClose.xDone OR fbDirClose.xError THEN
            fbDirClose(xExecute := FALSE);
            iFilesSeen := iEntries;
            IF xFault THEN
                iSt := 90;      (* скан недостоверен — ничего не удаляем *)
            ELSE
                iSt := 20;
            END_IF;
        END_IF;

    20: (* ОЦЕНКА: КВОТА *)
        udiUsedMB   := udiUsedKB / 1024;
        udiOursMB   := udiOursKB / 1024;
        udiOldestMB := udiOldestKB / 1024;

        (* --- сколько можно отдать журналам ---                          *)
        (* Вся карта минус резерв минус ЧУЖИЕ файлы, лежащие рядом в том  *)
        (* же каталоге (например, распакованное загрузочное приложение).  *)
        (* ⚠️ Содержимое ВЛОЖЕННЫХ папок не считается — DirList в глубину  *)
        (* не ходит. Папку app.spk1xxm01 с проектом (единицы МБ) с лихвой  *)
        (* перекрывает резерв в 100 МБ.                                   *)
        udiForeignMB := udiUsedMB - udiOursMB;
        IF udiUsableMB > (udiFreeMinMB + udiForeignMB) THEN
            udiQuotaMB := udiUsableMB - udiFreeMinMB - udiForeignMB;
        ELSE
            udiQuotaMB := 0;    (* чужие файлы съели всё — чистимся до дна *)
        END_IF;

        (* --- превышен ли потолок --- *)
        xOverQuota := (udiOursMB > udiQuotaMB);

        iSt := 30;

    30: (* РЕШЕНИЕ: чистить или нет *)
        IF xForceRun OR xOverQuota THEN
            IF xFoundOld THEN
                iOldYear        := UDINT_TO_INT(udiOldKey / 12);
                iOldMonth       := UDINT_TO_INT(udiOldKey MOD 12) + 1;
                iDelIdx         := 1;
                iDelOkThisRound := 0;
                iSt := 40;
            ELSE
                (* Старше текущего месяца ничего нет. Если при этом превышена *)
                (* наша собственная квота — единственный оставшийся способ не *)
                (* переполнить карту — перестать писать. Снимется само на     *)
                (* следующем месяце.                                          *)
                xNothingToDelete := TRUE;
                xQuotaStop       := xOverQuota;
                iSt := 90;
            END_IF;
        ELSE
            (* всё в норме — снимаем запрет записи, если он был *)
            xNothingToDelete := FALSE;
            xQuotaStop       := FALSE;
            iSt := 90;
        END_IF;

    40: (* ИМЯ ОЧЕРЕДНОГО ФАЙЛА САМОГО СТАРОГО МЕСЯЦА *)
        CASE iDelIdx OF
            1: sDelPath := F_SdLogPath(sDir, sPrefix1, iOldYear, iOldMonth);
            2: sDelPath := F_SdLogPath(sDir, sPrefix2, iOldYear, iOldMonth);
            3: sDelPath := F_SdLogPath(sDir, sPrefix3, iOldYear, iOldMonth);
        END_CASE;
        iSt := 41;

    41: (* УДАЛЕНИЕ *)
        fbDelete(xExecute := TRUE, sFileName := sDelPath);
        IF fbDelete.xDone THEN
            fbDelete(xExecute := FALSE);
            iDeletedLast    := iDeletedLast + 1;
            iDeletedTotal   := iDeletedTotal + 1;
            iDelOkThisRound := iDelOkThisRound + 1;
            sLastDeleted    := sDelPath;
            iSt := 42;
        ELSIF fbDelete.xError THEN
            (* файла за этот месяц могло не быть (например, уставки никто    *)
            (* не менял) — это норма, просто идём дальше                     *)
            fbDelete(xExecute := FALSE);
            iSt := 42;
        END_IF;

    42: (* СЛЕДУЮЩИЙ ФАЙЛ ИЛИ СЛЕДУЮЩИЙ РАУНД *)
        IF iDelIdx < 3 THEN
            iDelIdx := iDelIdx + 1;
            iSt := 40;
        ELSE
            iRound    := iRound + 1;
            xForceRun := FALSE;      (* аварийный форс = ровно один месяц *)
            IF iDelOkThisRound = 0 THEN
                (* Скан этот месяц нашёл, а удалить не вышло НИ ОДНОГО файла: *)
                (* карта только для чтения / вынута / имя на ФС отличается     *)
                (* регистром. Повторять раунды бессмысленно — они будут снова  *)
                (* находить тот же месяц. Выходим с аварией, чтобы это увидели.*)
                xFault := TRUE;
                iSt := 90;
            ELSIF iRound >= cMaxRounds THEN
                iSt := 90;
            ELSE
                iSt := 11;           (* пересчитать и, если надо, ещё раз *)
            END_IF;
        END_IF;

    90: (* КОНЕЦ ЗАПУСКА *)
        xDone := TRUE;
        iSt   := 0;

END_CASE;
