(* ================================================================
   FB_FountainSchedule — Расписание Фонтана (свет + насосы)
   === ДДЮТ:ИЗМЕНЕНО (round 2) === У СВЕТА и НАСОСОВ теперь РАЗНОЕ
   число режимов и РАЗНАЯ кодировка — не путать порядок!

   СВЕТ (Light_Mode, UDINT, 4 положения):
     0 = АВТО   — включение по фиксированному расписанию
                  (Light_On_Hour/Minute_Weekday/Weekend), выключение
                  — общий Off_Hour/Minute (будни/выходные)
     1 = ВКЛ    — горит постоянно, не выключается никогда
     2 = ВЫКЛ   — не включается никогда
     3 = АСТРО  — включение по расчёту заката (Sunset_Hour/Minute
                  от FB_SunsetRelay), выключение — тот же общий
                  Off_Hour/Minute

   НАСОСЫ (Pump_Mode, UDINT, 3 положения — БЕЗ режима "Астро"):
     0 = АВТО   — включение по фиксированному расписанию
                  (Pump_On_Hour/Minute_Weekday/Weekend), выключение
                  — тот же общий Off_Hour/Minute
     1 = ВКЛ    — работает постоянно, не выключается никогда
     2 = ВЫКЛ   — не включается никогда

   === ДДЮТ:ИЗМЕНЕНО === Раньше (round 1) у обоих было по 4
   одинаковых положения (0=Астро,1=Авто,2=Вкл,3=Выкл), полная
   симметрия. По итогам практики решили, что насосам "Астро" не
   нужен — оставили только 3 положения, и заодно поменяли порядок
   у света (Авто теперь 0, Астро — последний, 3). Если переносишь
   в другой проект — ПЕРЕПРОВЕРЬ кодировку, она несимметричная.

   ВАЖНО: это ВНУТРЕННИЙ выбор — работает только когда ВНЕШНИЙ
   селектор узла (GVL_Fountain.iLightSelect / iPumpSelect, экран
   "Свет/Насосы") стоит в положении "Авто" (=2). При "Ручной пуск"
   (=0) и "Выкл" (=1) на внешнем селекторе — этот блок и его режимы
   вообще не участвуют в управлении DO1/DO9.

   ================================================================
   ФЛАГИ ВИДИМОСТИ ДЛЯ ЭКРАНА — единая схема имён:
   Объект_ЧтоПоказывает (Light_/Pump_ + ShowInputFields/
   ShowComputedTime/ShowAlwaysOnText/ShowAlwaysOffText)

   СВЕТ (4 положения, 0=Авто,1=Вкл,2=Выкл,3=Астро):
   Light_ShowInputFields  = TRUE при Режим=0 (Авто) — поля ручного
     ввода расписания (Light_On_Hour/Minute_Weekday/Weekend).
   Light_ShowComputedTime = TRUE при Режим=0 (Авто) ИЛИ Режим=3
     (Астро) — число результата (Light_On_Result_Hour/Minute).
   Light_ShowAlwaysOnText  = TRUE при Режим=1 (Вкл) — текст
     "Свет Вкл ручн".
   Light_ShowAlwaysOffText = TRUE при Режим=2 (Выкл) — текст
     "Свет Выкл ручн".

   НАСОСЫ (3 положения, 0=Авто,1=Вкл,2=Выкл — своя кодировка!):
   Pump_ShowInputFields  = TRUE при Режим=0 (Авто) — поля ручного
     ввода расписания (Pump_On_Hour/Minute_Weekday/Weekend).
   Pump_ShowComputedTime = TRUE при Режим=0 (Авто) — число
     результата. У насосов больше НЕТ режима "Астро" — этот флаг
     истинен только в одном положении, не в двух, как у света.
   Pump_ShowAlwaysOnText  = TRUE при Режим=1 (Вкл) — текст
     "Насосы Вкл ручн".
   Pump_ShowAlwaysOffText = TRUE при Режим=2 (Выкл) — текст
     "Насосы Выкл ручн".

   ---- ОБЩИЕ ПОЛЯ ВЫКЛЮЧЕНИЯ (Off_Result_Hour/Minute — результат,
   и Off_Hour/Minute_Weekday/Weekend — поля ручного ввода уставок) ----
   Актуальны (должны быть видны), если ХОТЯ БЫ ОДИН из двух объектов
   (свет ИЛИ насос) сейчас работает по времени — то есть находится
   в режиме, где Xxx_ShowComputedTime истинен. Если оба постоянно
   "Вкл"/"Выкл" — время выключения нигде не используется, поля
   можно скрыть.

   Off_Time_Visible = Light_ShowComputedTime ИЛИ Pump_ShowComputedTime

   Привязать «Видимость» ко ВСЕМ 6 полям сразу (один и тот же провод
   на несколько свойств «Видимость» — это нормально):
     Off_Result_Hour, Off_Result_Minute,
     Off_Hour_Weekday, Off_Minute_Weekday,
     Off_Hour_Weekend, Off_Minute_Weekend
   ================================================================ *)

FUNCTION_BLOCK FB_FountainSchedule

VAR_INPUT
    (* --- От FB_SunsetRelay --- *)
    Sunset_Auto         : BOOL;
    Sunset_Hour         : UDINT;
    Sunset_Minute       : UDINT;
    IsWeekend           : BOOL;

    (* --- Селектор режима СВЕТА: 0=Авто,1=Вкл,2=Выкл,3=Астро --- *)
    Light_Mode          : UDINT;

    (* --- Ручное расписание СВЕТА (режим 0=Авто): включение --- *)
    Light_On_Hour_Weekday   : UDINT;
    Light_On_Minute_Weekday : UDINT;
    Light_On_Hour_Weekend   : UDINT;
    Light_On_Minute_Weekend : UDINT;

    (* --- Выключение (общее для света и насосов) --- *)
    Off_Hour_Weekday    : UDINT;
    Off_Minute_Weekday  : UDINT;
    Off_Hour_Weekend    : UDINT;
    Off_Minute_Weekend  : UDINT;

    (* --- Селектор режима НАСОСОВ: 0=Авто,1=Вкл,2=Выкл (БЕЗ Астро) --- *)
    Pump_Mode                : UDINT;

    (* --- Ручное расписание НАСОСОВ (режим 0=Авто): включение --- *)
    Pump_On_Hour_Weekday    : UDINT;
    Pump_On_Minute_Weekday  : UDINT;
    Pump_On_Hour_Weekend    : UDINT;
    Pump_On_Minute_Weekend  : UDINT;

    (* --- Текущее время --- *)
    Sys_Hour            : UDINT;
    Sys_Minute          : UDINT;
END_VAR

VAR_OUTPUT
    Light_Out             : BOOL;   (* ВЫХОД на освещение (DO)                *)
    Pump_Out               : BOOL;   (* ВЫХОД на насосы фонтана (DO)           *)

    (* Итоговое время включения СВЕТА на сегодня — для экрана.
       В режимах 1/2 (Вкл/Выкл) содержит 0:00 (заглушка) — привязать
       видимость к Light_ShowComputedTime, чтобы не показывать её.  *)
    Light_On_Result_Hour   : UDINT;
    Light_On_Result_Minute : UDINT;

    (* Итоговое время включения НАСОСОВ на сегодня — для экрана.
       Аналогично, заглушка 0:00 в режимах 1/2 (Вкл/Выкл).          *)
    Pump_On_Result_Hour     : UDINT;
    Pump_On_Result_Minute   : UDINT;

    (* Единое время ВЫКЛЮЧЕНИЯ — общее поле для света и насосов *)
    Off_Result_Hour         : UDINT;
    Off_Result_Minute       : UDINT;

    (* --- Флаги видимости: СВЕТ (0=Авто,1=Вкл,2=Выкл,3=Астро) --- *)
    Light_ShowInputFields    : BOOL;  (* Режим=0(Авто) → поля ручного ввода *)
    Light_ShowComputedTime   : BOOL;  (* Режим=0(Авто) или 3(Астро) → число результата *)
    Light_ShowAlwaysOnText   : BOOL;  (* Режим=1(Вкл) → текст "Свет Вкл ручн" *)
    Light_ShowAlwaysOffText  : BOOL;  (* Режим=2(Выкл) → текст "Свет Выкл ручн" *)

    (* --- Флаги видимости: НАСОСЫ (0=Авто,1=Вкл,2=Выкл, своя кодировка) --- *)
    Pump_ShowInputFields     : BOOL;  (* Режим=0(Авто) → поля ручного ввода *)
    Pump_ShowComputedTime    : BOOL;  (* Режим=0(Авто) → число результата (Астро нет) *)
    Pump_ShowAlwaysOnText    : BOOL;  (* Режим=1(Вкл) → текст "Насосы Вкл ручн" *)
    Pump_ShowAlwaysOffText   : BOOL;  (* Режим=2(Выкл) → текст "Насосы Выкл ручн" *)

    (* Комбинированный флаг для полей времени ВЫКЛЮЧЕНИЯ фонтана
       (Off_Result_Hour/Minute И Off_Hour/Minute_Weekday/Weekend).
       TRUE если хотя бы один из объектов (свет ИЛИ насос) сейчас
       работает по времени.                                        *)
    Off_Time_Visible          : BOOL;
END_VAR

VAR
    now_total_min       : UDINT;
    light_on_min         : UDINT;
    light_off_min        : UDINT;
    pump_on_min           : UDINT;
    pump_off_min          : UDINT;
    off_today_min         : UDINT;  (* Общее время выключения на сегодня (мин) *)
END_VAR


(* ----------------------------------------------------------------
   Текущее время в минутах от 0:00
   ---------------------------------------------------------------- *)
now_total_min := Sys_Hour * 60 + Sys_Minute;

(* Общее время выключения на сегодня (будни/выходные) — используется
   и светом, и насосами, в любом режиме, где это осмысленно          *)
IF IsWeekend THEN
    off_today_min := Off_Hour_Weekend * 60 + Off_Minute_Weekend;
ELSE
    off_today_min := Off_Hour_Weekday * 60 + Off_Minute_Weekday;
END_IF;


(* ================================================================
   СВЕТ — 4 положения: 0=Авто,1=Вкл,2=Выкл,3=Астро
   ================================================================ *)

(* --- Light_Out по режиму --- *)
IF Light_Mode = 0 THEN
    (* АВТО: фиксированное расписание будни/выходные *)
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
    Light_Out := TRUE;   (* ВКЛ: горит постоянно *)

ELSIF Light_Mode = 3 THEN
    (* АСТРО: закат → общий Off *)
    light_on_min  := Sunset_Hour * 60 + Sunset_Minute;
    light_off_min := off_today_min;

    IF light_off_min > light_on_min THEN
        Light_Out := (now_total_min >= light_on_min) AND (now_total_min < light_off_min);
    ELSE
        Light_Out := (now_total_min >= light_on_min) OR (now_total_min < light_off_min);
    END_IF;

ELSE
    Light_Out := FALSE;  (* ВЫКЛ (2) или некорректное значение *)
END_IF;

(* --- Light_On_Result --- *)
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
    Light_On_Result_Hour   := 0;   (* заглушка, режимы 1/2 (Вкл/Выкл) *)
    Light_On_Result_Minute := 0;
END_IF;

(* --- Флаги видимости СВЕТА --- *)
Light_ShowInputFields   := (Light_Mode = 0);
Light_ShowComputedTime  := (Light_Mode = 0) OR (Light_Mode = 3);
Light_ShowAlwaysOnText  := (Light_Mode = 1);
Light_ShowAlwaysOffText := (Light_Mode = 2);


(* ================================================================
   НАСОСЫ — 3 положения: 0=Авто,1=Вкл,2=Выкл (БЕЗ режима "Астро")
   ================================================================ *)

(* --- Pump_Out по режиму --- *)
IF Pump_Mode = 0 THEN
    (* АВТО: фиксированное расписание будни/выходные *)
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
    Pump_Out := TRUE;   (* ВКЛ: работает постоянно *)

ELSE
    Pump_Out := FALSE;  (* ВЫКЛ (2) или некорректное значение *)
END_IF;

(* --- Pump_On_Result --- *)
IF Pump_Mode = 0 THEN
    IF IsWeekend THEN
        Pump_On_Result_Hour   := Pump_On_Hour_Weekend;
        Pump_On_Result_Minute := Pump_On_Minute_Weekend;
    ELSE
        Pump_On_Result_Hour   := Pump_On_Hour_Weekday;
        Pump_On_Result_Minute := Pump_On_Minute_Weekday;
    END_IF;
ELSE
    Pump_On_Result_Hour   := 0;   (* заглушка, режимы 1/2 (Вкл/Выкл) *)
    Pump_On_Result_Minute := 0;
END_IF;

(* --- Флаги видимости НАСОСОВ --- *)
Pump_ShowInputFields   := (Pump_Mode = 0);
Pump_ShowComputedTime  := (Pump_Mode = 0);
Pump_ShowAlwaysOnText  := (Pump_Mode = 1);
Pump_ShowAlwaysOffText := (Pump_Mode = 2);


(* ================================================================
   ОБЩЕЕ ПОЛЕ Off_Result (время выключения, одно на экране)
   ================================================================ *)
Off_Result_Hour   := off_today_min / 60;
Off_Result_Minute := off_today_min MOD 60;

Off_Time_Visible := Light_ShowComputedTime OR Pump_ShowComputedTime;
