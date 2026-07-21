(* ============================================================
   FB_SunsetRelay — Астрономическое реле (расчёт заката)
   Без изменений относительно проекта ДДЮТ.
   Логика:
   - Расчёт времени заката по долготе/широте/часовому поясу
   - Ручная коррекция ±минут (местность: море/горы/рельеф)
   - Выход «Sunset_Auto» = TRUE от заката до времени отключения
   - Точность расчёта: ±1-3 минуты (алгоритм NOAA/Spencer с поправкой
     на атмосферную рефракцию и радиус диска Солнца, угол зенита
     90.833°).
   - Определение будни/выходной (алгоритм Зеллера) — для выбора
     своей пары Off_Hour/Off_Minute, а также выдаётся наружу
     (IsWeekend) для использования в FB_FountainSchedule.
   - Доп. выход: сколько осталось до следующей смены состояния

   ВАЖНО: Sunset_Auto — это ТОЛЬКО автоматический расчёт по закату.
   Финальное управление светом (авто/ручной режим) находится в
   отдельном блоке FB_FountainSchedule — туда подаётся Sunset_Auto
   как один из входов.
   ============================================================ *)

FUNCTION_BLOCK FB_SunsetRelay

VAR_INPUT
    (* --- Геокоординаты с экрана --- *)
    Latitude        : REAL;   (* Широта, градусы  *)
    Longitude       : REAL;   (* Долгота, градусы *)
    TimeZone        : REAL;   (* Часовой пояс, знаковый! ← выход FB_TimeZoneSelect *)

    (* --- Коррекция заката --- *)
    Sunset_Correct  : UDINT;  (* Ручная коррекция заката, минут (0..60)  *)
    Sunset_Earlier   : BOOL;  (* Направление: TRUE = раньше, FALSE = позже *)

    (* --- Настройки отключения: раздельно будни/выходные --- *)
    Off_Hour_Weekday   : UDINT;
    Off_Minute_Weekday : UDINT;
    Off_Hour_Weekend   : UDINT;
    Off_Minute_Weekend : UDINT;

    (* --- Системное время --- *)
    Sys_Year        : UDINT;
    Sys_Month       : UDINT;
    Sys_Day         : UDINT;
    Sys_Hour        : UDINT;
    Sys_Minute      : UDINT;
    Sys_Sec         : UDINT;
END_VAR

VAR_OUTPUT
    Sunset_Auto     : BOOL;   (* Автоматический расчёт: 1 = должно гореть *)
    Sunset_Hour     : UDINT;
    Sunset_Minute   : UDINT;
    DayOfYear       : UDINT;
    Err_Coord       : BOOL;
    IsWeekend       : BOOL;

    Time_Left_H     : UDINT;
    Time_Left_M     : UDINT;
END_VAR

VAR
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

    zm              : UDINT;
    zy              : UDINT;
    zK              : UDINT;
    zJ              : UDINT;
    zh              : UDINT;
END_VAR

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

IF IsWeekend THEN
    off_total_min := Off_Hour_Weekend * 60 + Off_Minute_Weekend;
ELSE
    off_total_min := Off_Hour_Weekday * 60 + Off_Minute_Weekday;
END_IF;

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

    gamma := two_pi * UDINT_TO_REAL(doy - 1) / 365.0;

    eqtime := 229.18 * (0.000075
             + 0.001868 * COS(gamma)
             - 0.032077 * SIN(gamma)
             - 0.014615 * COS(2.0 * gamma)
             - 0.040849 * SIN(2.0 * gamma));

    decl := 0.006918
          - 0.399912 * COS(gamma)
          + 0.070257 * SIN(gamma)
          - 0.006758 * COS(2.0 * gamma)
          + 0.000907 * SIN(2.0 * gamma)
          - 0.002697 * COS(3.0 * gamma)
          + 0.00148  * SIN(3.0 * gamma);

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

    sunset_utc := 12.0 + (ha * rad_to_deg / 15.0) - (eqtime / 60.0) - (Longitude / 15.0);

    sunset_local := sunset_utc + TimeZone;
    IF sunset_local < 0.0 THEN
        sunset_local := sunset_local + 24.0;
    END_IF;
    IF sunset_local >= 24.0 THEN
        sunset_local := sunset_local - 24.0;
    END_IF;

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

    sunset_total_min := REAL_TO_UDINT(sunset_local * 60.0);
    IF sunset_total_min >= 1440 THEN
        sunset_total_min := sunset_total_min - 1440;
    END_IF;
    Sunset_Hour   := sunset_total_min / 60;
    Sunset_Minute := sunset_total_min MOD 60;

    now_total_min := Sys_Hour * 60 + Sys_Minute;

    IF off_total_min > sunset_total_min THEN
        Sunset_Auto := (now_total_min >= sunset_total_min) AND (now_total_min < off_total_min);
    ELSE
        Sunset_Auto := (now_total_min >= sunset_total_min) OR (now_total_min < off_total_min);
    END_IF;

    IF now_total_min < sunset_total_min THEN
        diff_min := sunset_total_min - now_total_min;
    ELSE
        diff_min := (1440 - now_total_min) + sunset_total_min;
    END_IF;

    Time_Left_H := diff_min / 60;
    Time_Left_M := diff_min MOD 60;

END_IF;
