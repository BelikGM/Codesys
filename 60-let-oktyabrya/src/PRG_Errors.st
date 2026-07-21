(* ============================================================ *)
(* PRG_Errors — ЕДИНЫЙ подсчёт аварий + статус системы          *)
(* Проект "60 Лет Октября" (на основе ДДЮТ / Саки Пруд).         *)
(* ============================================================ *)
PROGRAM PRG_Errors
VAR
    i : INT;
END_VAR

iErrors         := 0;
iErrorsPumps    := 0;
iErrorsModules  := 0;
iErrorsFountain := 0;
iWorkCount      := 0;
iStopCount      := 0;

(* ============================================================ *)
(* 1. АВАРИИ НАСОСОВ ПЧ (счётчик iErrorsPumps)                  *)
(* ============================================================ *)
FOR i := 1 TO cPumpCount DO
    IF xPumpAlarm[i] AND NOT xPumpCommError[i] THEN
        iErrorsPumps := iErrorsPumps + 1;
    END_IF;
    IF xPumpWork[i] THEN iWorkCount := iWorkCount + 1; END_IF;
    IF xPumpStop[i] THEN iStopCount := iStopCount + 1; END_IF;
END_FOR;

(* ============================================================ *)
(* 2. АВАРИИ СВЯЗИ МОДУЛЕЙ (счётчик iErrorsModules)              *)
(* ============================================================ *)
FOR i := 1 TO cPumpCount DO
    IF xPumpCommError[i] THEN
        iErrorsModules := iErrorsModules + 1;
    END_IF;
END_FOR;
IF xMV110_Error THEN iErrorsModules := iErrorsModules + 1; END_IF;
IF xMU110_Error THEN iErrorsModules := iErrorsModules + 1; END_IF;

(* ============================================================ *)
(* 3. АВАРИИ АВТОМАТИКИ ФОНТАНА (iErrorsFountain)                *)
(* ⚠️ Сухой ход учитывается первым по смыслу (см. sAlarmCauses      *)
(* в PRG_Fountain.st, блок 11, где он тоже первый в строке).        *)
(* Опасная ситуация (сухой ход + ручная фильтрация) сюда НЕ         *)
(* включается — это не блокирующая авария, а рекомендация            *)
(* оператору, у неё своя отдельная лампа/диалог (xShowDangerDialog). *)
(* ============================================================ *)
IF xDryRunAlarm        THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // сухой ход — САМАЯ ОПАСНАЯ
IF xDryRunRelayAlarm   THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // реле сухого хода (DO1/DI8)
IF xDamperRelayAlarm   THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // реле клапана добора (DO4/DI6)
IF xPumpRelayAlarm     THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // реле насосов фонтана (DO2/DI9)
IF xLightRelayAlarm    THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // реле подсветки (DO3/DI10)
IF xNfManualRelayAlarm THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // реле фильтрации, ручной режим

(* ============================================================ *)
(* 4. ОБЩИЙ СЧЁТЧИК ВСЕХ АВАРИЙ + ЕДИНЫЙ ФЛАГ                    *)
(* ============================================================ *)
iErrors   := iErrorsPumps + iErrorsModules + iErrorsFountain;
xAnyAlarm := (iErrors > 0);

xSystemState := NOT xAnyAlarm;
IF xSystemState THEN
    sSystemStateText := "Система: ОК";
ELSE
    sSystemStateText := "Авария";
END_IF;
