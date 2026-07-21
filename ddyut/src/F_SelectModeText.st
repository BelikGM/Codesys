FUNCTION F_SelectModeText : WSTRING(12)
(* === ДДЮТ:НОВОЕ === Переводит 0/1/2 (единый селектор pH/альгицид/     *)
(* биопаг/свет/насосы/заслонка) в читаемый текст для журнала изменений. *)
VAR_INPUT
    iMode : INT;
END_VAR

CASE iMode OF
    0: F_SelectModeText := "Ручной";
    1: F_SelectModeText := "Выкл";
    2: F_SelectModeText := "Авто";
ELSE
    F_SelectModeText := "?";
END_CASE;
