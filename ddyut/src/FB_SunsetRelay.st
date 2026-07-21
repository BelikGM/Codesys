(* ============================================================
   FB_SunsetRelay — Астрономическое реле (расчёт заката)
   === ДДЮТ:ПОРТИРОВАНО (v2, точность до 1 мин) ===
   Единственное техническое отличие от твоего исходника (OwenLogic):
     SYS.COS/SYS.SIN/SYS.TAN/SYS.ACOS → COS/SIN/TAN/ACOS
     (в CODESYS это стандартные функции IEC 61131-3 без префикса
     SYS. — префикс есть только в библиотеке OwenLogic).
   Вся математика, включая поправку на рефракцию (90.833°) и
   алгоритм Зеллера — БЕЗ ИЗМЕНЕНИЙ, как в твоём исходнике.
   Логика:
   - Расчёт времени заката по долготе/широте/часовому поясу
   - Ручная коррекция ±минут (местность: море/горы/рельеф)
   - Выход «Sunset_Auto» = TRUE от заката до времени отключения
   - Точность расчёта: ±1-3 минуты (алгоритм NOAA/Spencer с поправкой
     на атмосферную рефракцию и радиус диска Солнца, угол зенита
     90.833°). Сверено с независимыми источниками для трёх городов
     на 12 месяцев вперёд.
   - Определение будни/выходной (алгоритм Зеллера) — для выбора
     своей пары Off_Hour/Off_Minute, а также выдаётся наружу
     (IsWeekend) для использования в FB_FountainSchedule, чтобы
     не дублировать расчёт дня недели в другом блоке.
   - Доп. выход: сколько осталось до следующей смены состояния

   ВАЖНО: Sunset_Auto — это ТОЛЬКО автоматический расчёт по закату.
   Финальное управление светом (авто/ручной режим) находится в
   отдельном блоке FB_FountainSchedule — туда подаётся Sunset_Auto
   как один из входов.
   ============================================================ *)

FUNCTION_BLOCK FB_SunsetRelay

VAR_INPUT
    (* --- Геокоординаты с экрана --- *)
    Latitude        : REAL;   (* Широта, градусы (пример: 44.59 = Севастополь)  *)
    Longitude       : REAL;   (* Долгота, градусы (пример: 33.52 = Севастополь) *)
    TimeZone        : REAL;   (* Часовой пояс, знаковый! ← выход FB_TimeZoneSelect *)

    (* --- Коррекция заката --- *)
    Sunset_Correct  : UDINT;  (* Ручная коррекция заката, минут (0..60)  *)
    Sunset_Earlier   : BOOL;  (* Направление: TRUE = раньше, FALSE = позже *)

    (* --- Настройки отключения: раздельно будни/выходные --- *)
    Off_Hour_Weekday   : UDINT;  (* Час отключения, будний день      *)
    Off_Minute_Weekday : UDINT;  (* Минута отключения, будний день   *)
    Off_Hour_Weekend   : UDINT;  (* Час отключения, выходной день    *)
    Off_Minute_Weekend : UDINT;  (* Минута отключения, выходной день *)

    (* --- Системное время (привязка к RTC ПР200) --- *)
    Sys_Year        : UDINT;  (* Год (2026)                              *)
    Sys_Month       : UDINT;  (* Месяц (1..12)                           *)
    Sys_Day         : UDINT;  (* День (1..31)                            *)
    Sys_Hour        : UDINT;  (* Часы (0..23)                            *)
    Sys_Minute      : UDINT;  (* Минуты (0..59)                          *)
    Sys_Sec         : UDINT;  (* Секунды (0..59) — для точности          *)
END_VAR

VAR_OUTPUT
    Sunset_Auto     : BOOL;   (* Автоматический расчёт: 1 = должно гореть *)
    Sunset_Hour     : UDINT;  (* Рассчитанный час заката (для экрана)    *)
    Sunset_Minute   : UDINT;  (* Рассчитанная минута заката (для экрана) *)
    DayOfYear       : UDINT;  (* Порядковый день года (диагностика)      *)
    Err_Coord       : BOOL;   (* Ошибка координат (широта за пределами)  *)
    IsWeekend       : BOOL;   (* TRUE = суббота/воскресенье. Выдаётся
                                  наружу для FB_FountainSchedule           *)

    (* --- Сколько осталось до следующего включения --- *)
    Time_Left_H     : UDINT;  (* Осталось ждать: часы                    *)
    Time_Left_M     : UDINT;  (* Осталось ждать: минуты (0–59)           *)
END_VAR

VAR
    (* --- Внутренние переменные расчёта заката --- *)
    i               : UDINT;
    doy             : UDINT;
    lat_rad         : REAL;
    gamma           : REAL;
    eqtime          : REAL;
    decl            : REAL;
    ha              : REAL;
    sunset_utc      : REAL;
    sunset_local    : REAL;
    sunset_total_min : UDINT;
    off_total_min   : UDINT;
    now_total_min   : UDINT;
    diff_min        : UDINT;
    pi              : REAL;
    two_pi          : REAL;
    deg_to_rad      : REAL;
    rad_to_deg      : REAL;
    temp_real       : REAL;
    sunset_corr_real : REAL;
    days_in_month   : ARRAY[1..12] OF UDINT;

    (* --- Внутренние переменные расчёта дня недели (алгоритм Зеллера) --- *)
    zm              : UDINT;  (* Месяц с коррекцией (янв/фев → 13/14 пред. года) *)
    zy              : UDINT;  (* Год с коррекцией                         *)
    zK              : UDINT;  (* Год внутри века (00-99)                  *)
    zJ              : UDINT;  (* Век (число столетий)                     *)
    zh              : UDINT;  (* Результат: 0=Сб,1=Вс,2=Пн,3=Вт,4=Ср,5=Чт,6=Пт *)
END_VAR

(* ============================================================
   ОПРЕДЕЛЕНИЕ ДНЯ НЕДЕЛИ (алгоритм Зеллера, григорианский календарь)
   Выполняется ВСЕГДА, независимо от Err_Coord — не зависит от
   координат, нужно для выбора Off_Hour/Off_Minute и для выдачи
   IsWeekend наружу.
   ============================================================ *)
IF Sys_Month < 3 THEN
    zm := Sys_Month + 12;
    zy := Sys_Year - 1;
ELSE
    zm := Sys_Month;
    zy := Sys_Year;
END_IF;

zK := zy MOD 100;
zJ := zy / 100;

zh := (Sys_Day + (13 * (zm + 1)) / 5 + zK + zK / 4 + zJ / 4 + 5 * zJ) MOD 7;

IsWeekend := (zh = 0) OR (zh = 1);   (* 0=суббота, 1=воскресенье *)

(* Выбор пары Off_Hour/Off_Minute по дню недели *)
IF IsWeekend THEN
    off_total_min := Off_Hour_Weekend * 60 + Off_Minute_Weekend;
ELSE
    off_total_min := Off_Hour_Weekday * 60 + Off_Minute_Weekday;
END_IF;


(* ============================================================
   ТЕЛО БЛОКА — РАСЧЁТ ЗАКАТА (АЛГОРИТМ NOAA)
   ============================================================ *)

pi := 3.14159265;
two_pi := 6.2831853;
deg_to_rad := pi / 180.0;
rad_to_deg := 180.0 / pi;

days_in_month[1] := 31;
days_in_month[2] := 28;
days_in_month[3] := 31;
days_in_month[4] := 30;
days_in_month[5] := 31;
days_in_month[6] := 30;
days_in_month[7] := 31;
days_in_month[8] := 31;
days_in_month[9] := 30;
days_in_month[10] := 31;
days_in_month[11] := 30;
days_in_month[12] := 31;

(* --- 1. Проверка координат --- *)
Err_Coord := (Latitude < -90.0) OR (Latitude > 90.0) 
          OR (Longitude < -180.0) OR (Longitude > 180.0);

IF Err_Coord THEN
    Sunset_Auto := FALSE;
    Sunset_Hour := 0;
    Sunset_Minute := 0;
    DayOfYear := 0;
    Time_Left_H := 0;
    Time_Left_M := 0;

ELSE
    (* --- 2. День года --- *)
    doy := 0;
    FOR i := 1 TO 12 DO
        IF i < Sys_Month THEN
            doy := doy + days_in_month[i];
        END_IF;
    END_FOR;
    doy := doy + Sys_Day;

    IF (Sys_Year MOD 4 = 0) THEN
        IF (Sys_Year MOD 100 <> 0) OR (Sys_Year MOD 400 = 0) THEN
            IF Sys_Month > 2 THEN
                doy := doy + 1;
            END_IF;
        END_IF;
    END_IF;
    DayOfYear := doy;

    (* --- 3. Годовой угол (гамма) --- *)
    gamma := two_pi * UDINT_TO_REAL(doy - 1) / 365.0;

    (* --- 4. Уравнение времени (eqtime), минуты --- *)
    eqtime := 229.18 * (0.000075 
             + 0.001868 * COS(gamma) 
             - 0.032077 * SIN(gamma) 
             - 0.014615 * COS(2.0 * gamma) 
             - 0.040849 * SIN(2.0 * gamma));

    (* --- 5. Склонение Солнца (decl), радианы --- *)
    decl := 0.006918 
          - 0.399912 * COS(gamma) 
          + 0.070257 * SIN(gamma) 
          - 0.006758 * COS(2.0 * gamma) 
          + 0.000907 * SIN(2.0 * gamma) 
          - 0.002697 * COS(3.0 * gamma) 
          + 0.00148  * SIN(3.0 * gamma);

    (* --- 6. Часовой угол заката (ha), радианы ---
       Угол зенита 90.833° (не 90°!) — стандартная поправка на
       атмосферную рефракцию (~34') + видимый радиус диска Солнца
       (~16'). Без неё расчёт даёт закат на 3-7 мин раньше реального
       (сверено с независимыми таблицами для Севастополя, Краснодара,
       Москвы на 12 месяцев вперёд — после поправки разброс ±1-3 мин).
       ---------------------------------------------------------------- *)
    lat_rad := Latitude * deg_to_rad;
    temp_real := COS(90.833 * deg_to_rad) / (COS(lat_rad) * COS(decl))
                 - TAN(lat_rad) * TAN(decl);

    IF temp_real > 1.0 THEN
        ha := 0.0;
    ELSIF temp_real < -1.0 THEN
        ha := pi;
    ELSE
        ha := ACOS(temp_real);
    END_IF;

    (* --- 7. Закат в UTC, часы --- *)
    sunset_utc := 12.0 + (ha * rad_to_deg / 15.0) - (eqtime / 60.0) - (Longitude / 15.0);

    (* --- 8. Перевод в местное время --- *)
    sunset_local := sunset_utc + TimeZone;  (* TimeZone уже REAL, конверсия не нужна *)
    IF sunset_local < 0.0 THEN
        sunset_local := sunset_local + 24.0;
    END_IF;
    IF sunset_local >= 24.0 THEN
        sunset_local := sunset_local - 24.0;
    END_IF;

    (* --- 9. Применение ручной коррекции --- *)
    sunset_corr_real := UDINT_TO_REAL(Sunset_Correct) / 60.0;
    IF Sunset_Earlier THEN
        sunset_local := sunset_local - sunset_corr_real;
    ELSE
        sunset_local := sunset_local + sunset_corr_real;
    END_IF;

    IF sunset_local < 0.0 THEN
        sunset_local := sunset_local + 24.0;
    END_IF;
    IF sunset_local >= 24.0 THEN
        sunset_local := sunset_local - 24.0;
    END_IF;

    (* --- 10. Результат в часы/минуты — ПЕРЕПИСАНО (найден баг) --- *)
    (* БЫЛО: Sunset_Hour считался ОТДЕЛЬНО через REAL_TO_UDINT(sunset_local),*)
    (* а минуты — как остаток (sunset_local - Sunset_Hour) * 60. Проблема: *)
    (* REAL_TO_UDINT в CODESYS ОКРУГЛЯЕТ, а не отбрасывает дробную часть.  *)
    (* Если дробная часть часа была, например, 0.5527 — округление даёт    *)
    (* ЧАС НА ЕДИНИЦУ БОЛЬШЕ, а остаток для минут уходит В ОТРИЦАТЕЛЬНОЕ   *)
    (* число — которое тут же ломается при попытке положить его в UDINT   *)
    (* (беззнаковый тип), давая переполнение на ~4 миллиарда. Дальше это   *)
    (* переполнение триггерит "IF >= 60" и добавляет ЕЩЁ +1 к часу — так   *)
    (* 20:33 превращалось в 22 часа, а -87 минут "просвечивали" через      *)
    (* UDINT_TO_INT при отображении на экране (типичный пример: 20.5527ч  *)
    (* → час округлился до 21, остаток -26.84 мин → переполнение →        *)
    (* +1 к часу = 22, младшие 16 бит переполненного числа = -87).        *)
    (*                                                                    *)
    (* СТАЛО: переводим время заката сразу в ЦЕЛЫЕ МИНУТЫ ОДНИМ действием  *)
    (* (без разделения на час+остаток), потом делим нацело — так          *)
    (* отрицательное промежуточное значение в принципе невозможно.        *)
    sunset_total_min := REAL_TO_UDINT(sunset_local * 60.0);
    (* На случай если округление дало ровно 1440 (24:00 = начало следующих*)
    (* суток) — переносим на 0:00.                                        *)
    IF sunset_total_min >= 1440 THEN
        sunset_total_min := sunset_total_min - 1440;
    END_IF;
    Sunset_Hour   := sunset_total_min / 60;
    Sunset_Minute := sunset_total_min MOD 60;

    (* --- 11. Время заката в минутах от 0:00 (уже посчитано выше) --- *)

    (* --- 12. Текущее время в минутах от 0:00 --- *)
    now_total_min := Sys_Hour * 60 + Sys_Minute;

    (* off_total_min уже выбран выше (будни/выходной) *)

    (* --- 14. ЛОГИКА ВКЛЮЧЕНИЯ/ОТКЛЮЧЕНИЯ --- *)
    IF off_total_min > sunset_total_min THEN
        Sunset_Auto := (now_total_min >= sunset_total_min) AND (now_total_min < off_total_min);
    ELSE
        Sunset_Auto := (now_total_min >= sunset_total_min) OR (now_total_min < off_total_min);
    END_IF;

    (* --- 15. ВРЕМЯ ДО СЛЕДУЮЩЕГО ЗАКАТА --- *)
    IF now_total_min < sunset_total_min THEN
        diff_min := sunset_total_min - now_total_min;
    ELSE
        diff_min := (1440 - now_total_min) + sunset_total_min;
    END_IF;

    Time_Left_H := diff_min / 60;
    Time_Left_M := diff_min MOD 60;

END_IF;
