(* ============================================================ *)
(* F_SdLogPath — ПОЛНЫЙ ПУТЬ К ПОМЕСЯЧНОМУ ЖУРНАЛУ НА SD        *)
(* ============================================================ *)
(* Собирает "<каталог>/<префикс>MM-YYYY.log", например:          *)
(*   F_SdLogPath('/mnt/ufs/media/mmcblk0p1', 'alarms-', 2026, 8) *)
(*   → '/mnt/ufs/media/mmcblk0p1/alarms-08-2026.log'             *)
(*                                                               *)
(* ⚠️ Каталог передавать БЕЗ завершающего '/' — слэш добавляется  *)
(* здесь. Месяц дополняется нулём до 2 знаков, год — ВСЕГДА 4     *)
(* знака (вызывающий обязан проверить диапазон 2000..2199, см.    *)
(* PRG_AlarmLogSD блок 4). Ровно 11 символов "MM-YYYY.log" после  *)
(* префикса — на это же число опирается разбор в F_SdLogMonthKey. *)
(*                                                               *)
(* Длина результата: 24 (путь SD) + 1 + 13 (самый длинный         *)
(* префикс 'pump_changes-') + 11 = 49 символов, в STRING(80)      *)
(* помещается с запасом.                                         *)
(* ============================================================ *)
FUNCTION F_SdLogPath : STRING(80)
VAR_INPUT
    sDir    : STRING(80);   (* каталог на карте, БЕЗ '/' в конце *)
    sPrefix : STRING(20);   (* 'alarms-' / 'pump_changes-' / 'setpoints-' *)
    iYear   : INT;          (* 2000..2199 *)
    iMonth  : INT;          (* 1..12 *)
END_VAR
VAR
    sMM : STRING(4);
    sYY : STRING(8);
END_VAR

sMM := INT_TO_STRING(iMonth);
IF iMonth < 10 THEN
    sMM := CONCAT('0', sMM);
END_IF;

sYY := INT_TO_STRING(iYear);

F_SdLogPath := CONCAT(sDir,
               CONCAT('/',
               CONCAT(sPrefix,
               CONCAT(sMM,
               CONCAT('-',
               CONCAT(sYY, '.log'))))));
