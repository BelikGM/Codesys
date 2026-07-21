FUNCTION F_LightScheduleModeText : WSTRING(12)
(* === ДДЮТ:НОВОЕ === Переводит iLightScheduleMode (0-3) в текст для    *)
(* журнала. ВНИМАНИЕ: кодировка ДРУГАЯ, чем у F_SelectModeText          *)
(* (тройные селекторы pH/альгицид/биопаг/свет/насосы/заслонка) — не      *)
(* перепутать! Здесь 0=Авто, а не Ручной.                                *)
VAR_INPUT
    iMode : INT;
END_VAR

CASE iMode OF
    0: F_LightScheduleModeText := "Авто";
    1: F_LightScheduleModeText := "Вкл";
    2: F_LightScheduleModeText := "Выкл";
    3: F_LightScheduleModeText := "Астро";
ELSE
    F_LightScheduleModeText := "?";
END_CASE;
