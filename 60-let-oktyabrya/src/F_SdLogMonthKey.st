(* ============================================================ *)
(* F_SdLogMonthKey — РАЗБОР ИМЕНИ ФАЙЛА ЖУРНАЛА → КЛЮЧ МЕСЯЦА   *)
(* ============================================================ *)
(* Принимает ИМЯ ФАЙЛА (не путь!), как его отдаёт FILE.DirList в  *)
(* deDirEntry.sEntry, и префикс журнала. Если имя ТОЧНО совпадает *)
(* с шаблоном "<префикс>MM-YYYY.log" — возвращает ключ месяца:    *)
(*                                                               *)
(*        КЛЮЧ = YYYY * 12 + (MM - 1)                            *)
(*                                                               *)
(* Ключ монотонно растёт со временем, поэтому "самый старый       *)
(* месяц" = минимальный ключ. Декабрь 2025 = 24311, январь 2026 = *)
(* 24312 — переход через год сравнивается правильно, в отличие от *)
(* сравнения строк "12-2025" и "01-2026".                        *)
(*                                                               *)
(* Возвращает 0, если имя НЕ подходит под шаблон. Ноль как признак*)
(* "не наш файл" безопасен: минимально возможный реальный ключ =  *)
(* 2000*12 = 24000, нулём он не станет никогда.                  *)
(*                                                               *)
(* ⚠️ ГЛАВНОЕ НАЗНАЧЕНИЕ — ЗАЩИТА ОТ УДАЛЕНИЯ ЧУЖИХ ФАЙЛОВ.       *)
(* Проверяется ВСЁ: длина имени, префикс, что MM и YYYY — цифры,  *)
(* разделители '-' и '.', расширение 'log', диапазоны MM 1..12 и  *)
(* YYYY 2000..2199. Любое несовпадение → 0 → файл не тронут.      *)
(* Регистр букв игнорируется (FAT может отдать имя иначе).        *)
(* ============================================================ *)
FUNCTION F_SdLogMonthKey : UDINT
VAR_INPUT
    sName   : STRING(255);  (* имя файла из DirList, без пути *)
    sPrefix : STRING(20);   (* 'alarms-' / 'pump_changes-' / 'setpoints-' *)
END_VAR
VAR
    iLenName : INT;
    iLenPref : INT;
    iOfs     : INT;
    i        : INT;
    bN       : BYTE;
    bP       : BYTE;
    iMM      : INT;
    iYY      : INT;
END_VAR

F_SdLogMonthKey := 0;

iLenPref := LEN(sPrefix);
iLenName := LEN(sName);

(* "MM-YYYY.log" — ровно 11 символов после префикса *)
IF iLenPref = 0 OR iLenName <> iLenPref + 11 THEN
    RETURN;
END_IF;

(* --- префикс, без учёта регистра --- *)
FOR i := 0 TO iLenPref - 1 DO
    bN := sName[i];
    bP := sPrefix[i];
    IF bN >= 65 AND bN <= 90 THEN bN := bN + 32; END_IF;   // 'A'..'Z' → нижний
    IF bP >= 65 AND bP <= 90 THEN bP := bP + 32; END_IF;
    IF bN <> bP THEN
        RETURN;
    END_IF;
END_FOR;

iOfs := iLenPref;

(* --- MM (2 цифры) --- *)
iMM := 0;
FOR i := iOfs TO iOfs + 1 DO
    bN := sName[i];
    IF bN < 48 OR bN > 57 THEN RETURN; END_IF;             // не цифра
    iMM := iMM * 10 + BYTE_TO_INT(bN) - 48;
END_FOR;

(* --- разделитель '-' --- *)
IF sName[iOfs + 2] <> 45 THEN RETURN; END_IF;

(* --- YYYY (4 цифры) --- *)
iYY := 0;
FOR i := iOfs + 3 TO iOfs + 6 DO
    bN := sName[i];
    IF bN < 48 OR bN > 57 THEN RETURN; END_IF;
    iYY := iYY * 10 + BYTE_TO_INT(bN) - 48;
END_FOR;

(* --- точка --- *)
IF sName[iOfs + 7] <> 46 THEN RETURN; END_IF;

(* --- расширение 'log' без учёта регистра --- *)
bN := sName[iOfs + 8];
IF bN >= 65 AND bN <= 90 THEN bN := bN + 32; END_IF;
IF bN <> 108 THEN RETURN; END_IF;                          // 'l'
bN := sName[iOfs + 9];
IF bN >= 65 AND bN <= 90 THEN bN := bN + 32; END_IF;
IF bN <> 111 THEN RETURN; END_IF;                          // 'o'
bN := sName[iOfs + 10];
IF bN >= 65 AND bN <= 90 THEN bN := bN + 32; END_IF;
IF bN <> 103 THEN RETURN; END_IF;                          // 'g'

(* --- диапазоны --- *)
IF iMM < 1 OR iMM > 12 THEN RETURN; END_IF;
IF iYY < 2000 OR iYY > 2199 THEN RETURN; END_IF;

F_SdLogMonthKey := INT_TO_UDINT(iYY) * 12 + INT_TO_UDINT(iMM) - 1;
