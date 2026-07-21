FUNCTION F_PumpScheduleModeText : WSTRING(12)
(* Переводит iPumpScheduleMode (0-2, БЕЗ "Астро") в текст для        *)
(* журнала. Своя, третья кодировка. Без изменений от ДДЮТ.            *)
VAR_INPUT
    iMode : INT;
END_VAR

CASE iMode OF
    0: F_PumpScheduleModeText := "Авто";
    1: F_PumpScheduleModeText := "Вкл";
    2: F_PumpScheduleModeText := "Выкл";
ELSE
    F_PumpScheduleModeText := "?";
END_CASE;
