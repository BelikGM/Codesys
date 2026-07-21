FUNCTION F_PumpScheduleModeText : WSTRING(12)
(* === ДДЮТ:НОВОЕ === Переводит iPumpScheduleMode (0-2, БЕЗ "Астро") в  *)
(* текст для журнала. Своя, третья кодировка — не путать ни с            *)
(* F_SelectModeText, ни с F_LightScheduleModeText (у насосов режимов      *)
(* на один меньше, и нет положения "Астро" вообще).                       *)
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
