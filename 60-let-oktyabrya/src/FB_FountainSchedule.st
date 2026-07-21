(* ================================================================
   FB_FountainSchedule — Расписание Фонтана (свет + насосы)
   Без изменений относительно проекта ДДЮТ.

   СВЕТ (Light_Mode, UDINT, 4 положения):
     0 = АВТО, 1 = ВКЛ, 2 = ВЫКЛ, 3 = АСТРО

   НАСОСЫ (Pump_Mode, UDINT, 3 положения — БЕЗ режима "Астро"):
     0 = АВТО, 1 = ВКЛ, 2 = ВЫКЛ

   ВАЖНО: это ВНУТРЕННИЙ выбор — работает только когда ВНЕШНИЙ
   селектор узла (GVL_Fountain.iLightSelect / iPumpSelect) стоит
   в положении "Авто" (=2).
   ================================================================ *)

FUNCTION_BLOCK FB_FountainSchedule

VAR_INPUT
    Sunset_Auto         : BOOL;
    Sunset_Hour         : UDINT;
    Sunset_Minute       : UDINT;
    IsWeekend           : BOOL;

    Light_Mode          : UDINT;

    Light_On_Hour_Weekday   : UDINT;
    Light_On_Minute_Weekday : UDINT;
    Light_On_Hour_Weekend   : UDINT;
    Light_On_Minute_Weekend : UDINT;

    Off_Hour_Weekday    : UDINT;
    Off_Minute_Weekday  : UDINT;
    Off_Hour_Weekend    : UDINT;
    Off_Minute_Weekend  : UDINT;

    Pump_Mode                : UDINT;

    Pump_On_Hour_Weekday    : UDINT;
    Pump_On_Minute_Weekday  : UDINT;
    Pump_On_Hour_Weekend    : UDINT;
    Pump_On_Minute_Weekend  : UDINT;

    Sys_Hour            : UDINT;
    Sys_Minute          : UDINT;
END_VAR

VAR_OUTPUT
    Light_Out             : BOOL;
    Pump_Out               : BOOL;

    Light_On_Result_Hour   : UDINT;
    Light_On_Result_Minute : UDINT;

    Pump_On_Result_Hour     : UDINT;
    Pump_On_Result_Minute   : UDINT;

    Off_Result_Hour         : UDINT;
    Off_Result_Minute       : UDINT;

    Light_ShowInputFields    : BOOL;
    Light_ShowComputedTime   : BOOL;
    Light_ShowAlwaysOnText   : BOOL;
    Light_ShowAlwaysOffText  : BOOL;

    Pump_ShowInputFields     : BOOL;
    Pump_ShowComputedTime    : BOOL;
    Pump_ShowAlwaysOnText    : BOOL;
    Pump_ShowAlwaysOffText   : BOOL;

    Off_Time_Visible          : BOOL;
END_VAR

VAR
    now_total_min       : UDINT;
    light_on_min         : UDINT;
    light_off_min        : UDINT;
    pump_on_min           : UDINT;
    pump_off_min          : UDINT;
    off_today_min         : UDINT;
END_VAR

now_total_min := Sys_Hour * 60 + Sys_Minute;

IF IsWeekend THEN
    off_today_min := Off_Hour_Weekend * 60 + Off_Minute_Weekend;
ELSE
    off_today_min := Off_Hour_Weekday * 60 + Off_Minute_Weekday;
END_IF;

(* ================== СВЕТ ================== *)
IF Light_Mode = 0 THEN
    IF IsWeekend THEN
        light_on_min := Light_On_Hour_Weekend * 60 + Light_On_Minute_Weekend;
    ELSE
        light_on_min := Light_On_Hour_Weekday * 60 + Light_On_Minute_Weekday;
    END_IF;
    light_off_min := off_today_min;

    IF light_off_min > light_on_min THEN
        Light_Out := (now_total_min >= light_on_min) AND (now_total_min < light_off_min);
    ELSE
        Light_Out := (now_total_min >= light_on_min) OR (now_total_min < light_off_min);
    END_IF;

ELSIF Light_Mode = 1 THEN
    Light_Out := TRUE;

ELSIF Light_Mode = 3 THEN
    light_on_min  := Sunset_Hour * 60 + Sunset_Minute;
    light_off_min := off_today_min;

    IF light_off_min > light_on_min THEN
        Light_Out := (now_total_min >= light_on_min) AND (now_total_min < light_off_min);
    ELSE
        Light_Out := (now_total_min >= light_on_min) OR (now_total_min < light_off_min);
    END_IF;

ELSE
    Light_Out := FALSE;
END_IF;

IF Light_Mode = 0 THEN
    IF IsWeekend THEN
        Light_On_Result_Hour   := Light_On_Hour_Weekend;
        Light_On_Result_Minute := Light_On_Minute_Weekend;
    ELSE
        Light_On_Result_Hour   := Light_On_Hour_Weekday;
        Light_On_Result_Minute := Light_On_Minute_Weekday;
    END_IF;
ELSIF Light_Mode = 3 THEN
    Light_On_Result_Hour   := Sunset_Hour;
    Light_On_Result_Minute := Sunset_Minute;
ELSE
    Light_On_Result_Hour   := 0;
    Light_On_Result_Minute := 0;
END_IF;

Light_ShowInputFields   := (Light_Mode = 0);
Light_ShowComputedTime  := (Light_Mode = 0) OR (Light_Mode = 3);
Light_ShowAlwaysOnText  := (Light_Mode = 1);
Light_ShowAlwaysOffText := (Light_Mode = 2);

(* ================== НАСОСЫ ================== *)
IF Pump_Mode = 0 THEN
    IF IsWeekend THEN
        pump_on_min := Pump_On_Hour_Weekend * 60 + Pump_On_Minute_Weekend;
    ELSE
        pump_on_min := Pump_On_Hour_Weekday * 60 + Pump_On_Minute_Weekday;
    END_IF;
    pump_off_min := off_today_min;

    IF pump_off_min > pump_on_min THEN
        Pump_Out := (now_total_min >= pump_on_min) AND (now_total_min < pump_off_min);
    ELSE
        Pump_Out := (now_total_min >= pump_on_min) OR (now_total_min < pump_off_min);
    END_IF;

ELSIF Pump_Mode = 1 THEN
    Pump_Out := TRUE;

ELSE
    Pump_Out := FALSE;
END_IF;

IF Pump_Mode = 0 THEN
    IF IsWeekend THEN
        Pump_On_Result_Hour   := Pump_On_Hour_Weekend;
        Pump_On_Result_Minute := Pump_On_Minute_Weekend;
    ELSE
        Pump_On_Result_Hour   := Pump_On_Hour_Weekday;
        Pump_On_Result_Minute := Pump_On_Minute_Weekday;
    END_IF;
ELSE
    Pump_On_Result_Hour   := 0;
    Pump_On_Result_Minute := 0;
END_IF;

Pump_ShowInputFields   := (Pump_Mode = 0);
Pump_ShowComputedTime  := (Pump_Mode = 0);
Pump_ShowAlwaysOnText  := (Pump_Mode = 1);
Pump_ShowAlwaysOffText := (Pump_Mode = 2);

Off_Result_Hour   := off_today_min / 60;
Off_Result_Minute := off_today_min MOD 60;

Off_Time_Visible := Light_ShowComputedTime OR Pump_ShowComputedTime;
