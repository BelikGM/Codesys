(* ============================================================ *)
(* PRG_Errors — ЕДИНЫЙ подсчёт аварий + статус системы          *)
(* Проект ДДЮТ (на основе Fontan_V1 / Саки Пруд).                *)
(*                                                                *)
(* === ДДЮТ:ИЗМЕНЕНО === Убраны аварии несуществующего            *)
(* оборудования (перелив/датчик/протечка/концевики/свет/резерв   *)
(* полива/МВ-8А). Добавлены: биопаг (в Саки не считался — это     *)
(* был пробел, тут исправлено) и три аварии реле обратной связи   *)
(* дозаторов (pH/альгицид/биопаг).                                *)
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
(* 1. АВАРИИ НАСОСОВ ПЧ (счётчик iErrorsPumps)                 *)
(* ============================================================ *)
FOR i := 1 TO cPumpCount DO
    IF xPumpAlarm[i] AND NOT xPumpCommError[i] THEN
        iErrorsPumps := iErrorsPumps + 1;
    END_IF;
    IF xPumpWork[i] THEN iWorkCount := iWorkCount + 1; END_IF;
    IF xPumpStop[i] THEN iStopCount := iStopCount + 1; END_IF;
END_FOR;

(* ============================================================ *)
(* 2. АВАРИИ СВЯЗИ МОДУЛЕЙ (счётчик iErrorsModules)             *)
(* ============================================================ *)
FOR i := 1 TO cPumpCount DO
    IF xPumpCommError[i] THEN
        iErrorsModules := iErrorsModules + 1;
    END_IF;
END_FOR;
IF xMV110_Error THEN iErrorsModules := iErrorsModules + 1; END_IF;  // МВ110-16Д
IF xMU110_Error THEN iErrorsModules := iErrorsModules + 1; END_IF;  // МУ110-16Р
(* === ДДЮТ:УДАЛИТЬ === нет модуля МВ110-8А (аналоговый) *)
(* IF xMV110_8A_Error THEN iErrorsModules := iErrorsModules + 1; END_IF; *)

(* ============================================================ *)
(* 3. АВАРИИ АВТОМАТИКИ ФОНТАНА (iErrorsFountain)               *)
(* ============================================================ *)
IF xDryRunAlarm         THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // сухой ход (вычисляемый)
IF xDryRunRelayAlarm    THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // ДДЮТ: DO13/DI6 расхождение
IF xRefillAttemptsAlarm THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // ДДЮТ: исчерпаны попытки добора
IF xAlgAlarm            THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // альгицид (защ.таймер)
IF xBioAlarm            THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // биопаг (защ.таймер) — ДДЮТ:добавлено
IF xPhRelayAlarm       THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // ДДЮТ: реле pH нет подтверждения
IF xAlgRelayAlarm      THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // ДДЮТ: реле альгицида
IF xBioRelayAlarm      THEN iErrorsFountain := iErrorsFountain + 1; END_IF;  // ДДЮТ: реле биопага

(* === ДДЮТ:УДАЛИТЬ === аварии несуществующего оборудования *)
(*
IF xAlarmOverflow      THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xAlarmWaterSensor   THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xDamperAlarm        THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xDamperSensorFault  THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xLeakAlarm          THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xLightFault         THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xSpkErrPereliv      THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xSpkErrDobor        THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
IF xSpkErrPoliv        THEN iErrorsFountain := iErrorsFountain + 1; END_IF;
*)

(* ============================================================ *)
(* 4. ОБЩИЙ СЧЁТЧИК ВСЕХ АВАРИЙ + ЕДИНЫЙ ФЛАГ                  *)
(* ============================================================ *)
iErrors   := iErrorsPumps + iErrorsModules + iErrorsFountain;
xAnyAlarm := (iErrors > 0);

xSystemState := NOT xAnyAlarm;
IF xSystemState THEN
    sSystemStateText := "Система: ОК";
ELSE
    sSystemStateText := "Авария";
END_IF;
