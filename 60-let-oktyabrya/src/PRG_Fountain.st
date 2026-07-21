PROGRAM PRG_Fountain
(* ============================================================ *)
(* PRG_Fountain — автоматика "60 Лет Октября"                   *)
(* (на основе ДДЮТ / Саки Пруд)                                 *)
(* ============================================================ *)
VAR
    dwUtcTime : DWORD;
    sysTime   : SYSTIMEDATE;
    rtcResult : DWORD;

    fbTimeZone : FB_TimeZoneSelect;
    fbSunset : FB_SunsetRelay;
    fbSchedule : FB_FountainSchedule;

    tonBlinkFastOff : TON;
    tonBlinkSlowOff : TON;

    tonNfContinuous : TON;

    (* 60ЛО: таймеры проверки реле (обрыв/залипание) *)
    tonDryRunRelayAlarm : TON;   // DO1 vs DI8, 2с
    tonDamperRelayAlarm : TON;   // DO4 vs DI6, 20с (процесс не мгновенный)
    tonPumpRelayAlarm   : TON;   // DO2 vs DI9, 2с
    tonLightRelayAlarm  : TON;   // DO3 vs DI10, 2с
    tonNfManualRelayAlarm : TON; // ручной режим (DI12) и DI7=0, 2с

    iClearIdx : INT;

    tonFountainLogClearedMsg : TON;
    tonFountainLogPassBadMsg : TON;
    tonPumpLogClearedMsg     : TON;
    tonPumpLogPassBadMsg     : TON;
END_VAR


(* ============================================================ *)
(* 1. ЧТЕНИЕ СИСТЕМНОГО ВРЕМЕНИ (RTC) — БЕЗ ИЗМЕНЕНИЙ            *)
(* ============================================================ *)
dwUtcTime := SysTimeRtcGet(pResult := rtcResult);
dwUtcTime := dwUtcTime + INT_TO_DWORD(iTimeZoneOffsetSec);
rtcResult := SysTimeRtcConvertUtcToDate(dwTimestampUtc := dwUtcTime, pDate := sysTime);
iCurrentYear         := WORD_TO_INT(sysTime.wYear);
iCurrentMonth        := WORD_TO_INT(sysTime.wMonth);
iCurrentDay          := WORD_TO_INT(sysTime.wDay);
iCurrentHour         := WORD_TO_INT(sysTime.wHour);
iCurrentMinute       := WORD_TO_INT(sysTime.wMinute);
iCurrentSecond       := WORD_TO_INT(sysTime.wSecond);
iCurrentTotalMinutes := iCurrentHour * 60 + iCurrentMinute;

IF iCurrentDay < 10 THEN
    sCurrentDateStr := WCONCAT("0", INT_TO_WSTRING(iCurrentDay));
ELSE
    sCurrentDateStr := INT_TO_WSTRING(iCurrentDay);
END_IF;
IF iCurrentMonth < 10 THEN
    sCurrentDateStr := WCONCAT(sCurrentDateStr, WCONCAT(".0", INT_TO_WSTRING(iCurrentMonth)));
ELSE
    sCurrentDateStr := WCONCAT(sCurrentDateStr, WCONCAT(".", INT_TO_WSTRING(iCurrentMonth)));
END_IF;
sCurrentDateStr := WCONCAT(sCurrentDateStr, WCONCAT(".", INT_TO_WSTRING(iCurrentYear)));


(* ============================================================ *)
(* 2. РАСПАКОВКА ВХОДОВ DI — 60ЛО: НОВАЯ КАРТА                    *)
(* ============================================================ *)
xPump1Work := xDI[1];    // ПЧ1 (информационный)
xPump2Work := xDI[2];    // ПЧ2 (информационный)
xPump3Work := xDI[3];    // ПЧ3 (информационный, НОВЫЙ)
xDryRunOk       := xDI[4];    // сухой ход от Мусидоры, 1=норма
xDamperCmdRaw   := xDI[5];    // пуск добора от Мусидоры
xDamperRelayFb  := xDI[6];    // подтверждение положения клапана добора
xNfWork         := xDI[7];    // контактор фильтрации
xDryRunRelayFb  := xDI[8];    // подтверждение реле сухого хода
xPumpRelayFb    := xDI[9];    // подтверждение работы насосов фонтана
xLightRelayFb   := xDI[10];   // подтверждение работы подсветки
xNfAutoSwitch   := xDI[11];   // ручка режима фильтрации = АВТО
xNfManualSwitch := xDI[12];   // ручка режима фильтрации = РУЧНОЙ


(* ============================================================ *)
(* 2а. РЕЖИМЫ — СЕЛЕКТОР ДЛЯ СВЕТА И НАСОСОВ ФОНТАНА             *)
(* ============================================================ *)
(*   0 = Ручной пуск (принудительно вкл, минуя автоматику)         *)
(*   1 = Выкл (запрет)                                             *)
(*   2 = Авто (штатная логика по расписанию)                       *)

(* Насосы фонтана *)
IF iPumpSelect = 0 THEN
    xManualPermissionNasos := FALSE;
    xPumpsForceOn          := TRUE;
ELSIF iPumpSelect = 2 THEN
    xManualPermissionNasos := TRUE;
    xPumpsForceOn          := FALSE;
ELSE
    xManualPermissionNasos := FALSE;
    xPumpsForceOn          := FALSE;
END_IF;

xPumpOuterForcedOn  := (iPumpSelect = 0);
xPumpOuterForcedOff := (iPumpSelect = 1);

(* Свет *)
IF iLightSelect = 0 THEN
    xLightEnable  := FALSE;
    xLightForceOn := TRUE;
ELSIF iLightSelect = 2 THEN
    xLightEnable  := TRUE;
    xLightForceOn := FALSE;
ELSE
    xLightEnable  := FALSE;
    xLightForceOn := FALSE;
END_IF;

xLightOuterForcedOn  := (iLightSelect = 0);
xLightOuterForcedOff := (iLightSelect = 1);


(* ============================================================ *)
(* 3. СУХОЙ ХОД + ПРОВЕРКА РЕЛЕ (2с)                             *)
(* ============================================================ *)
xDryRunAlarm := NOT xDryRunOk;    // ЖИВАЯ, НЕ защёлка. САМАЯ ПЕРВАЯ авария в списке!

(* === 60ЛО:ИСПРАВЛЕНО (баг) === Раньше здесь сравнивался xDO[1]  *)
(* — но он ещё не переписан на этом цикле (запись в блоке 15,     *)
(* позже), т.е. сравнение шло со значением ПРОШЛОГО цикла.        *)
(* xDryRunOk — то же самое значение, которое уйдёт на DO1 в этом   *)
(* же цикле (просто зеркало DI4→DO1), поэтому сравниваем с ним     *)
(* напрямую — без задержки на цикл.                                *)
tonDryRunRelayAlarm(IN := xDryRunOk <> xDryRunRelayFb, PT := T#2S);
IF tonDryRunRelayAlarm.Q THEN
    xDryRunRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xDryRunRelayAlarm := FALSE;
    tonDryRunRelayAlarm(IN := FALSE, PT := T#2S);
END_IF;


(* ============================================================ *)
(* 4. КЛАПАН ДОБОРА — ЗЕРКАЛО DI5→DO4, проверка реле 20с          *)
(* ============================================================ *)
IF xDamperRelayFb THEN
    sDamperPosition := "Открыт";
ELSE
    sDamperPosition := "Закрыт";
END_IF;

tonDamperRelayAlarm(IN := xDamperCmdRaw <> xDamperRelayFb, PT := T#20S);
IF tonDamperRelayAlarm.Q THEN
    xDamperRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xDamperRelayAlarm := FALSE;
    tonDamperRelayAlarm(IN := FALSE, PT := T#20S);
END_IF;


(* ============================================================ *)
(* 5. ФИЛЬТРАЦИЯ — режим/авария реле (2с)                        *)
(* ============================================================ *)
tonNfManualRelayAlarm(IN := xNfManualSwitch AND NOT xNfWork, PT := T#2S);
IF tonNfManualRelayAlarm.Q THEN
    xNfManualRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xNfManualRelayAlarm := FALSE;
    tonNfManualRelayAlarm(IN := FALSE, PT := T#2S);
END_IF;

(* === 60ЛО:ИСПРАВЛЕНО (баг компиляции) === Раньше здесь стоял      *)
(* CASE TRUE OF — в CODESYS так писать НЕЛЬЗЯ (метка CASE требует   *)
(* целочисленный литерал, не BOOL). Заменено на обычный IF/ELSIF.   *)
(* Логика: если ни DI11, ни DI12 не активны одновременно — это      *)
(* либо промежуточное положение ручки (если оно физически возможно),*)
(* либо обрыв провода на оба входа — статус "?" сигнализирует       *)
(* оператору о нештатной ситуации, чтобы не осталось старое          *)
(* значение "Авто"/"Ручной" на экране.                               *)
IF xNfAutoSwitch THEN
    sNfModeStatus := "Авто";
ELSIF xNfManualSwitch THEN
    sNfModeStatus := "Ручной";
ELSE
    sNfModeStatus := "?";   // ни один вход не активен — обрыв линии или промежуточное положение
END_IF;

IF xNfWork THEN sNfStatus := "Работает"; ELSE sNfStatus := "Стоп"; END_IF;


(* ============================================================ *)
(* 5а. СЧЁТЧИК ПРОМЫВОК НФ — БЕЗ ИЗМЕНЕНИЙ АЛГОРИТМА             *)
(* ============================================================ *)
IF NOT xNfFirstScanDone THEN
    xNfFirstScanDone := TRUE;
    xNfWorkPrev := xNfWork;
END_IF;

IF xNfHealthy THEN
    iNfFlushStage := 0;
    xNfFlushReady := TRUE;
END_IF;

IF xNfWork AND NOT xNfWorkPrev THEN
    iNfLastOnHour  := iCurrentHour;
    iNfLastOnMin   := iCurrentMinute;
    iNfLastOnDay   := iCurrentDay;
    iNfLastOnMonth := iCurrentMonth;
    iNfLastOnYear  := iCurrentYear;
END_IF;

IF (NOT xNfWork) AND xNfWorkPrev THEN
    iNfJustEndedSec := DINT_TO_INT(TIME_TO_DINT(tonNfContinuous.ET) / 1000);

    IF xNfFlushReady THEN
        IF (iNfJustEndedSec > 60) AND (iNfJustEndedSec < (iFilterMinRunMin * 60)) THEN
            IF iNfFlushStage = 0 THEN
                iNfFlushStage := 1;
            ELSE
                iNfFlushCount  := iNfFlushCount + 1;
                iNfFlushHour   := iCurrentHour;
                iNfFlushMin    := iCurrentMinute;
                iNfFlushDay    := iCurrentDay;
                iNfFlushMonth  := iCurrentMonth;
                iNfFlushYear   := iCurrentYear;
                iNfFlushStage  := 0;
                xNfFlushReady  := FALSE;
            END_IF;
        END_IF;
    END_IF;
END_IF;

xNfWorkPrev := xNfWork;

(* Сброс счётчика промывок — СВОЙ отдельный диалог, НЕ через xAlarmReset. *)
IF xConfirmResetNfFlush THEN
    iNfFlushCount  := 0;
    iNfFlushStage  := 0;
    xNfFlushReady  := TRUE;
    iNfFlushHour   := 0;
    iNfFlushMin    := 0;
    iNfFlushDay    := 0;
    iNfFlushMonth  := 0;
    iNfFlushYear   := 0;
    xAskResetNfFlush     := FALSE;
    xConfirmResetNfFlush := FALSE;
    F_FountainLogWrite("Сброс счётчика промывок НФ");
END_IF;
(* Кнопки на экране: "Сбросить" → xAskResetNfFlush:=TRUE (показать окно);  *)
(* "Подтвердить" → xConfirmResetNfFlush:=TRUE; "Отмена" → xAskResetNfFlush:=FALSE. *)


(* ============================================================ *)
(* 5б. ИСПРАВНОСТЬ НФ — непрерывная наработка, БЕЗ ИЗМЕНЕНИЙ      *)
(* ============================================================ *)
tonNfContinuous(IN := xNfWork,
    PT := DINT_TO_TIME(INT_TO_DINT(iFilterMinRunMin) * 60000));
xNfHealthy := tonNfContinuous.Q;

iNfContinuousRunHour := DINT_TO_INT(TIME_TO_DINT(tonNfContinuous.ET) / 3600000);
iNfContinuousRunMin  := DINT_TO_INT((TIME_TO_DINT(tonNfContinuous.ET) MOD 3600000) / 60000);
iNfContinuousRunSec  := DINT_TO_INT((TIME_TO_DINT(tonNfContinuous.ET) MOD 60000) / 1000);


(* ============================================================ *)
(* 6. РАСЧЁТ ЗАКАТА — NOAA v2, БЕЗ ИЗМЕНЕНИЙ                     *)
(* ============================================================ *)
IF (rSunLongitude > rSunLongitudePrev + 0.01) OR (rSunLongitude < rSunLongitudePrev - 0.01) THEN
    rSunLongitudePrev := rSunLongitude;
    iChoseTimeZone := REAL_TO_INT(rSunLongitude / 15.0) + 11;
    IF iChoseTimeZone > 23 THEN
        iChoseTimeZone := 23;
    ELSIF iChoseTimeZone < 0 THEN
        iChoseTimeZone := 0;
    END_IF;
END_IF;

fbTimeZone(ChoseTimeZone := INT_TO_UDINT(iChoseTimeZone));
rSunTimeZone := fbTimeZone.TimeZone;

IF iSunsetCorrectSigned < 0 THEN
    xSunsetCorrectEarlier := TRUE;
    iSunsetCorrectMin     := -iSunsetCorrectSigned;
ELSE
    xSunsetCorrectEarlier := FALSE;
    iSunsetCorrectMin     := iSunsetCorrectSigned;
END_IF;

fbSunset(
    Latitude           := rSunLatitude,
    Longitude          := rSunLongitude,
    TimeZone           := rSunTimeZone,
    Sunset_Correct     := INT_TO_UDINT(iSunsetCorrectMin),
    Sunset_Earlier     := xSunsetCorrectEarlier,
    Off_Hour_Weekday   := INT_TO_UDINT(iOffHourWeekday),
    Off_Minute_Weekday := INT_TO_UDINT(iOffMinuteWeekday),
    Off_Hour_Weekend   := INT_TO_UDINT(iOffHourWeekend),
    Off_Minute_Weekend := INT_TO_UDINT(iOffMinuteWeekend),
    Sys_Year           := INT_TO_UDINT(iCurrentYear),
    Sys_Month          := INT_TO_UDINT(iCurrentMonth),
    Sys_Day            := INT_TO_UDINT(iCurrentDay),
    Sys_Hour           := INT_TO_UDINT(iCurrentHour),
    Sys_Minute         := INT_TO_UDINT(iCurrentMinute),
    Sys_Sec            := INT_TO_UDINT(iCurrentSecond)
);
xSunsetActive     := fbSunset.Sunset_Auto;
xSunsetCoordError := fbSunset.Err_Coord;
iSunsetHourCalc   := UDINT_TO_INT(fbSunset.Sunset_Hour);
iSunsetMinuteCalc := UDINT_TO_INT(fbSunset.Sunset_Minute);
iSunsetTimeLeftH  := UDINT_TO_INT(fbSunset.Time_Left_H);
iSunsetTimeLeftM  := UDINT_TO_INT(fbSunset.Time_Left_M);
iSunsetDayOfYear  := UDINT_TO_INT(fbSunset.DayOfYear);
xIsWeekend        := fbSunset.IsWeekend;


(* ============================================================ *)
(* 7. РАСПИСАНИЕ СВЕТА/НАСОСОВ — FB_FountainSchedule, БЕЗ ИЗМЕНЕНИЙ *)
(* ============================================================ *)
fbSchedule(
    Sunset_Auto             := fbSunset.Sunset_Auto,
    Sunset_Hour             := fbSunset.Sunset_Hour,
    Sunset_Minute           := fbSunset.Sunset_Minute,
    IsWeekend               := fbSunset.IsWeekend,
    Light_Mode              := INT_TO_UDINT(iLightScheduleMode),
    Light_On_Hour_Weekday   := INT_TO_UDINT(iLightOnHourWeekday),
    Light_On_Minute_Weekday := INT_TO_UDINT(iLightOnMinuteWeekday),
    Light_On_Hour_Weekend   := INT_TO_UDINT(iLightOnHourWeekend),
    Light_On_Minute_Weekend := INT_TO_UDINT(iLightOnMinuteWeekend),
    Off_Hour_Weekday        := INT_TO_UDINT(iOffHourWeekday),
    Off_Minute_Weekday      := INT_TO_UDINT(iOffMinuteWeekday),
    Off_Hour_Weekend        := INT_TO_UDINT(iOffHourWeekend),
    Off_Minute_Weekend      := INT_TO_UDINT(iOffMinuteWeekend),
    Pump_Mode                := INT_TO_UDINT(iPumpScheduleMode),
    Pump_On_Hour_Weekday    := INT_TO_UDINT(iPumpOnHourWeekday),
    Pump_On_Minute_Weekday  := INT_TO_UDINT(iPumpOnMinuteWeekday),
    Pump_On_Hour_Weekend    := INT_TO_UDINT(iPumpOnHourWeekend),
    Pump_On_Minute_Weekend  := INT_TO_UDINT(iPumpOnMinuteWeekend),
    Sys_Hour                := INT_TO_UDINT(iCurrentHour),
    Sys_Minute              := INT_TO_UDINT(iCurrentMinute)
);
xScheduleLightOut      := fbSchedule.Light_Out;
xSchedulePumpOut       := fbSchedule.Pump_Out;
iScheduleLightOnHour   := UDINT_TO_INT(fbSchedule.Light_On_Result_Hour);
iScheduleLightOnMinute := UDINT_TO_INT(fbSchedule.Light_On_Result_Minute);
iScheduleOffHour       := UDINT_TO_INT(fbSchedule.Off_Result_Hour);
iScheduleOffMinute     := UDINT_TO_INT(fbSchedule.Off_Result_Minute);
iSchedulePumpOnHour    := UDINT_TO_INT(fbSchedule.Pump_On_Result_Hour);
iSchedulePumpOnMinute  := UDINT_TO_INT(fbSchedule.Pump_On_Result_Minute);

xLightShowInputFields   := fbSchedule.Light_ShowInputFields;
xLightShowComputedTime  := fbSchedule.Light_ShowComputedTime;
xLightShowAlwaysOnText  := fbSchedule.Light_ShowAlwaysOnText;
xLightShowAlwaysOffText := fbSchedule.Light_ShowAlwaysOffText;
xPumpShowInputFields    := fbSchedule.Pump_ShowInputFields;
xPumpShowComputedTime   := fbSchedule.Pump_ShowComputedTime;
xPumpShowAlwaysOnText   := fbSchedule.Pump_ShowAlwaysOnText;
xPumpShowAlwaysOffText  := fbSchedule.Pump_ShowAlwaysOffText;
xOffTimeVisible         := fbSchedule.Off_Time_Visible;


(* ============================================================ *)
(* 8. ГЕНЕРАТОРЫ МИГАНИЯ — БЕЗ ИЗМЕНЕНИЙ                          *)
(* ============================================================ *)
tonBlinkFastOff(IN := xBlinkFast, PT := T#20MS);
IF tonBlinkFastOff.Q THEN xBlinkFast := FALSE; END_IF;
IF NOT xBlinkFast AND NOT tonBlinkFastOff.IN THEN xBlinkFast := TRUE; END_IF;

tonBlinkSlowOff(IN := xBlinkSlow, PT := T#100MS);
IF tonBlinkSlowOff.Q THEN xBlinkSlow := FALSE; END_IF;
IF NOT xBlinkSlow AND NOT tonBlinkSlowOff.IN THEN xBlinkSlow := TRUE; END_IF;


(* ============================================================ *)
(* 9. НАСОСЫ ФОНТАНА (DO2) + проверка реле (2с)                  *)
(* ============================================================ *)
xPumpsCmd := xVseSist AND NOT xDryRunAlarm AND xManualPermissionNasos AND xSchedulePumpOut;
IF xPumpsForceOn THEN
    xPumpsCmd := TRUE;   // ручной пуск — минуя все запреты
END_IF;

tonPumpRelayAlarm(IN := xPumpsCmd <> xPumpRelayFb, PT := T#2S);
IF tonPumpRelayAlarm.Q THEN
    xPumpRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xPumpRelayAlarm := FALSE;
    tonPumpRelayAlarm(IN := FALSE, PT := T#2S);
END_IF;

CASE iPumpSelect OF
    0: sPermissionStatus := "Ручной пуск";
    2: sPermissionStatus := "Авто";
ELSE
    sPermissionStatus := "Выкл";
END_CASE;


(* ============================================================ *)
(* 10. ПОДСВЕТКА (DO3) + проверка реле (2с)                      *)
(* ============================================================ *)
xLightCmd := NOT xDryRunAlarm AND xVseSist AND xLightEnable AND xScheduleLightOut;
IF xLightForceOn THEN
    xLightCmd := TRUE;
END_IF;

tonLightRelayAlarm(IN := xLightCmd <> xLightRelayFb, PT := T#2S);
IF tonLightRelayAlarm.Q THEN
    xLightRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xLightRelayAlarm := FALSE;
    tonLightRelayAlarm(IN := FALSE, PT := T#2S);
END_IF;

CASE iLightSelect OF
    0: sLightStatus := "Ручной пуск";
    2: sLightStatus := "Авто (закат)";
ELSE
    sLightStatus := "Выкл";
END_CASE;


(* ============================================================ *)
(* 11. ОБЩАЯ АВАРИЯ + СТРОКА ПРИЧИН — сухой ход ПЕРВЫМ            *)
(* ============================================================ *)
(* === 60ЛО:ИЗМЕНЕНО === "Опасная ситуация" (сухой ход + ручная  *)
(* фильтрация) СЮДА больше не выводится — у неё СВОЯ отдельная    *)
(* лампа/диалог (xShowDangerDialog, блок 12). Если добавить её     *)
(* и в общий список причин, счётчик iErrors (PRG_Errors.st) и      *)
(* текст sAlarmCauses разойдутся, т.к. в счётчик она не входит      *)
(* (не блокирующая авария, а рекомендация оператору).               *)
xAlarmFountain := xDryRunAlarm
              OR xDryRunRelayAlarm
              OR xDamperRelayAlarm
              OR xPumpRelayAlarm
              OR xLightRelayAlarm
              OR xNfManualRelayAlarm;

sAlarmCauses := "";
IF xDryRunAlarm         THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Сухой ход, ");            END_IF;
IF xDryRunRelayAlarm    THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Сухой ход реле, ");        END_IF;
IF xDamperRelayAlarm    THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Клапан добора реле, ");    END_IF;
IF xPumpRelayAlarm      THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Насосы фонтана реле, ");   END_IF;
IF xLightRelayAlarm     THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Подсветка реле, ");        END_IF;
IF xNfManualRelayAlarm  THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Фильтрация реле (ручной режим), "); END_IF;
IF xPumpCommError[1]    THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь ПЧ1, ");             END_IF;
IF xPumpCommError[2]    THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь ПЧ2, ");             END_IF;
IF xPumpCommError[3]    THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь ПЧ3, ");             END_IF;
IF xMV110_Error         THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь МВ-Д, ");            END_IF;
IF xMU110_Error         THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь МУ, ");              END_IF;
IF sAlarmCauses = ""    THEN sAlarmCauses := "Нет аварий";                                    END_IF;

IF xAlarmReset THEN
    xAlarmReset := FALSE;
END_IF;

IF xAlarmFountain THEN sAlarmStopStatus := "Да"; ELSE sAlarmStopStatus := "Нет"; END_IF;


(* ============================================================ *)
(* 12. ОПАСНАЯ СИТУАЦИЯ: СУХОЙ ХОД + РУЧНАЯ ФИЛЬТРАЦИЯ            *)
(* ============================================================ *)
(* Ничего не блокируем — только напоминание. Показ по фронту       *)
(* появления, кнопка "ОК" на диалоге выполняет ОДНУ строку:         *)
(*   GVL_Fountain.xConfirmDangerDialog := TRUE;                     *)
(* Если ситуация уйдёт и появится заново — диалог покажется снова.  *)
xDangerCondition := xDryRunAlarm AND xNfManualSwitch;

IF xDangerCondition AND NOT xDangerCondition_Prev THEN
    xShowDangerDialog := TRUE;
END_IF;
IF xConfirmDangerDialog THEN
    xShowDangerDialog    := FALSE;
    xConfirmDangerDialog := FALSE;
END_IF;
xDangerCondition_Prev := xDangerCondition;


(* ============================================================ *)
(* 13. ЖУРНАЛ ИЗМЕНЕНИЙ ПАРАМЕТРОВ ФОНТАНА — СПИСОК СОКРАЩЁН      *)
(* ============================================================ *)
IF xFountainLogPinSubmit THEN
    xFountainLogPinSubmit := FALSE;
    IF iFountainLogPinEntry = iAdminPassCorrect THEN
        xFountainLogClear      := TRUE;
        xAskClearFountainLog   := FALSE;
        xFountainLogClearedMsg := TRUE;
    ELSE
        xFountainLogPassBadMsg := TRUE;
    END_IF;
    iFountainLogPinEntry := 0;
END_IF;

tonFountainLogClearedMsg(IN := xFountainLogClearedMsg, PT := T#3S);
IF tonFountainLogClearedMsg.Q THEN xFountainLogClearedMsg := FALSE; END_IF;

tonFountainLogPassBadMsg(IN := xFountainLogPassBadMsg, PT := T#3S);
IF tonFountainLogPassBadMsg.Q THEN xFountainLogPassBadMsg := FALSE; END_IF;

IF xFountainLogClear THEN
    FOR iClearIdx := 1 TO 60 DO
        aFountainLog[iClearIdx] := "";
    END_FOR;
    iFountainLogCount    := 0;
    xFountainLogClear     := FALSE;
    xAskClearFountainLog  := FALSE;
END_IF;

IF xPumpLogPinSubmit THEN
    xPumpLogPinSubmit := FALSE;
    IF iPumpLogPinEntry = iAdminPassCorrect THEN
        GVL.xLogClear       := TRUE;
        GVL.xAskClearLog    := FALSE;
        xPumpLogClearedMsg  := TRUE;
    ELSE
        xPumpLogPassBadMsg := TRUE;
    END_IF;
    iPumpLogPinEntry := 0;
END_IF;

tonPumpLogClearedMsg(IN := xPumpLogClearedMsg, PT := T#3S);
IF tonPumpLogClearedMsg.Q THEN xPumpLogClearedMsg := FALSE; END_IF;

tonPumpLogPassBadMsg(IN := xPumpLogPassBadMsg, PT := T#3S);
IF tonPumpLogPassBadMsg.Q THEN xPumpLogPassBadMsg := FALSE; END_IF;

IF NOT xFountainLogInitialized THEN
    iLogPrevPumpSelect          := iPumpSelect;
    iLogPrevLightSelect         := iLightSelect;
    xLogPrevVseSist             := xVseSist;
    iLogPrevLightScheduleMode   := iLightScheduleMode;
    iLogPrevPumpScheduleMode    := iPumpScheduleMode;
    iLogPrevLightOnHourWeekday   := iLightOnHourWeekday;
    iLogPrevLightOnMinuteWeekday := iLightOnMinuteWeekday;
    iLogPrevLightOnHourWeekend   := iLightOnHourWeekend;
    iLogPrevLightOnMinuteWeekend := iLightOnMinuteWeekend;
    iLogPrevPumpOnHourWeekday    := iPumpOnHourWeekday;
    iLogPrevPumpOnMinuteWeekday  := iPumpOnMinuteWeekday;
    iLogPrevPumpOnHourWeekend    := iPumpOnHourWeekend;
    iLogPrevPumpOnMinuteWeekend  := iPumpOnMinuteWeekend;
    iLogPrevOffHourWeekday       := iOffHourWeekday;
    iLogPrevOffMinuteWeekday     := iOffMinuteWeekday;
    iLogPrevOffHourWeekend       := iOffHourWeekend;
    iLogPrevOffMinuteWeekend     := iOffMinuteWeekend;
    iLogPrevSunsetCorrectSigned  := iSunsetCorrectSigned;
    iLogPrevChoseTimeZone        := iChoseTimeZone;
    rLogPrevSunLatitude          := rSunLatitude;
    rLogPrevSunLongitude         := rSunLongitude;
    iLogPrevFilterMinRunMin      := iFilterMinRunMin;
    xLogPrevAlarmReset           := xAlarmReset;
    xFountainLogInitialized      := TRUE;
END_IF;

IF iPumpSelect <> iLogPrevPumpSelect THEN
    F_FountainLogWrite(WCONCAT("Режим насосов: ", WCONCAT(F_SelectModeText(iLogPrevPumpSelect), WCONCAT(" → ", F_SelectModeText(iPumpSelect)))));
    iLogPrevPumpSelect := iPumpSelect;
END_IF;

IF iLightSelect <> iLogPrevLightSelect THEN
    F_FountainLogWrite(WCONCAT("Режим света: ", WCONCAT(F_SelectModeText(iLogPrevLightSelect), WCONCAT(" → ", F_SelectModeText(iLightSelect)))));
    iLogPrevLightSelect := iLightSelect;
END_IF;

IF xVseSist <> xLogPrevVseSist THEN
    F_FountainLogWrite(WCONCAT("Общее разрешение: ", WCONCAT(SEL(xLogPrevVseSist, "Запрещено", "Разрешено"), WCONCAT(" → ", SEL(xVseSist, "Запрещено", "Разрешено")))));
    xLogPrevVseSist := xVseSist;
END_IF;

IF iLightScheduleMode <> iLogPrevLightScheduleMode THEN
    F_FountainLogWrite(WCONCAT("Расписание света: ", WCONCAT(F_LightScheduleModeText(iLogPrevLightScheduleMode), WCONCAT(" → ", F_LightScheduleModeText(iLightScheduleMode)))));
    iLogPrevLightScheduleMode := iLightScheduleMode;
END_IF;

IF iPumpScheduleMode <> iLogPrevPumpScheduleMode THEN
    F_FountainLogWrite(WCONCAT("Расписание насосов: ", WCONCAT(F_PumpScheduleModeText(iLogPrevPumpScheduleMode), WCONCAT(" → ", F_PumpScheduleModeText(iPumpScheduleMode)))));
    iLogPrevPumpScheduleMode := iPumpScheduleMode;
END_IF;

IF iLightOnHourWeekday <> iLogPrevLightOnHourWeekday THEN
    F_FountainLogWrite(WCONCAT("Свет вкл будние дни, час: ", WCONCAT(INT_TO_WSTRING(iLogPrevLightOnHourWeekday), WCONCAT(" → ", INT_TO_WSTRING(iLightOnHourWeekday)))));
    iLogPrevLightOnHourWeekday := iLightOnHourWeekday;
END_IF;
IF iLightOnMinuteWeekday <> iLogPrevLightOnMinuteWeekday THEN
    F_FountainLogWrite(WCONCAT("Свет вкл будние дни, мин: ", WCONCAT(INT_TO_WSTRING(iLogPrevLightOnMinuteWeekday), WCONCAT(" → ", INT_TO_WSTRING(iLightOnMinuteWeekday)))));
    iLogPrevLightOnMinuteWeekday := iLightOnMinuteWeekday;
END_IF;
IF iLightOnHourWeekend <> iLogPrevLightOnHourWeekend THEN
    F_FountainLogWrite(WCONCAT("Свет вкл выходные дни, час: ", WCONCAT(INT_TO_WSTRING(iLogPrevLightOnHourWeekend), WCONCAT(" → ", INT_TO_WSTRING(iLightOnHourWeekend)))));
    iLogPrevLightOnHourWeekend := iLightOnHourWeekend;
END_IF;
IF iLightOnMinuteWeekend <> iLogPrevLightOnMinuteWeekend THEN
    F_FountainLogWrite(WCONCAT("Свет вкл выходные дни, мин: ", WCONCAT(INT_TO_WSTRING(iLogPrevLightOnMinuteWeekend), WCONCAT(" → ", INT_TO_WSTRING(iLightOnMinuteWeekend)))));
    iLogPrevLightOnMinuteWeekend := iLightOnMinuteWeekend;
END_IF;

IF iPumpOnHourWeekday <> iLogPrevPumpOnHourWeekday THEN
    F_FountainLogWrite(WCONCAT("Насосы вкл будние дни, час: ", WCONCAT(INT_TO_WSTRING(iLogPrevPumpOnHourWeekday), WCONCAT(" → ", INT_TO_WSTRING(iPumpOnHourWeekday)))));
    iLogPrevPumpOnHourWeekday := iPumpOnHourWeekday;
END_IF;
IF iPumpOnMinuteWeekday <> iLogPrevPumpOnMinuteWeekday THEN
    F_FountainLogWrite(WCONCAT("Насосы вкл будние дни, мин: ", WCONCAT(INT_TO_WSTRING(iLogPrevPumpOnMinuteWeekday), WCONCAT(" → ", INT_TO_WSTRING(iPumpOnMinuteWeekday)))));
    iLogPrevPumpOnMinuteWeekday := iPumpOnMinuteWeekday;
END_IF;
IF iPumpOnHourWeekend <> iLogPrevPumpOnHourWeekend THEN
    F_FountainLogWrite(WCONCAT("Насосы вкл выходные дни, час: ", WCONCAT(INT_TO_WSTRING(iLogPrevPumpOnHourWeekend), WCONCAT(" → ", INT_TO_WSTRING(iPumpOnHourWeekend)))));
    iLogPrevPumpOnHourWeekend := iPumpOnHourWeekend;
END_IF;
IF iPumpOnMinuteWeekend <> iLogPrevPumpOnMinuteWeekend THEN
    F_FountainLogWrite(WCONCAT("Насосы вкл выходные дни, мин: ", WCONCAT(INT_TO_WSTRING(iLogPrevPumpOnMinuteWeekend), WCONCAT(" → ", INT_TO_WSTRING(iPumpOnMinuteWeekend)))));
    iLogPrevPumpOnMinuteWeekend := iPumpOnMinuteWeekend;
END_IF;

IF iOffHourWeekday <> iLogPrevOffHourWeekday THEN
    F_FountainLogWrite(WCONCAT("Выкл фонтана будние дни, час: ", WCONCAT(INT_TO_WSTRING(iLogPrevOffHourWeekday), WCONCAT(" → ", INT_TO_WSTRING(iOffHourWeekday)))));
    iLogPrevOffHourWeekday := iOffHourWeekday;
END_IF;
IF iOffMinuteWeekday <> iLogPrevOffMinuteWeekday THEN
    F_FountainLogWrite(WCONCAT("Выкл фонтана будние дни, мин: ", WCONCAT(INT_TO_WSTRING(iLogPrevOffMinuteWeekday), WCONCAT(" → ", INT_TO_WSTRING(iOffMinuteWeekday)))));
    iLogPrevOffMinuteWeekday := iOffMinuteWeekday;
END_IF;
IF iOffHourWeekend <> iLogPrevOffHourWeekend THEN
    F_FountainLogWrite(WCONCAT("Выкл фонтана выходные дни, час: ", WCONCAT(INT_TO_WSTRING(iLogPrevOffHourWeekend), WCONCAT(" → ", INT_TO_WSTRING(iOffHourWeekend)))));
    iLogPrevOffHourWeekend := iOffHourWeekend;
END_IF;
IF iOffMinuteWeekend <> iLogPrevOffMinuteWeekend THEN
    F_FountainLogWrite(WCONCAT("Выкл фонтана выходные дни, мин: ", WCONCAT(INT_TO_WSTRING(iLogPrevOffMinuteWeekend), WCONCAT(" → ", INT_TO_WSTRING(iOffMinuteWeekend)))));
    iLogPrevOffMinuteWeekend := iOffMinuteWeekend;
END_IF;

IF iSunsetCorrectSigned <> iLogPrevSunsetCorrectSigned THEN
    F_FountainLogWrite(WCONCAT("Коррекция заката: ", WCONCAT(INT_TO_WSTRING(iLogPrevSunsetCorrectSigned), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iSunsetCorrectSigned), ", мин")))));
    iLogPrevSunsetCorrectSigned := iSunsetCorrectSigned;
END_IF;

IF iChoseTimeZone <> iLogPrevChoseTimeZone THEN
    F_FountainLogWrite(WCONCAT("Часовой пояс: ", WCONCAT(INT_TO_WSTRING(iLogPrevChoseTimeZone), WCONCAT(" → ", INT_TO_WSTRING(iChoseTimeZone)))));
    iLogPrevChoseTimeZone := iChoseTimeZone;
END_IF;

IF rSunLatitude <> rLogPrevSunLatitude THEN
    F_FountainLogWrite(WCONCAT("Широта: ", WCONCAT(REAL_TO_WSTRING(rLogPrevSunLatitude), WCONCAT(" → ", REAL_TO_WSTRING(rSunLatitude)))));
    rLogPrevSunLatitude := rSunLatitude;
END_IF;

IF rSunLongitude <> rLogPrevSunLongitude THEN
    F_FountainLogWrite(WCONCAT("Долгота: ", WCONCAT(REAL_TO_WSTRING(rLogPrevSunLongitude), WCONCAT(" → ", REAL_TO_WSTRING(rSunLongitude)))));
    rLogPrevSunLongitude := rSunLongitude;
END_IF;

IF iFilterMinRunMin <> iLogPrevFilterMinRunMin THEN
    F_FountainLogWrite(WCONCAT("Порог подтв.режима НФ: ", WCONCAT(INT_TO_WSTRING(iLogPrevFilterMinRunMin), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iFilterMinRunMin), ", мин")))));
    iLogPrevFilterMinRunMin := iFilterMinRunMin;
END_IF;

IF xAlarmReset AND NOT xLogPrevAlarmReset THEN
    F_FountainLogWrite("Сброс всех аварий");
END_IF;
xLogPrevAlarmReset := xAlarmReset;


(* ============================================================ *)
(* 14. ОБЩИЕ СТРОКОВЫЕ СТАТУСЫ                                   *)
(* ============================================================ *)
IF xVseSist THEN sVseSistStatus := "Разрешен"; ELSE sVseSistStatus := "Запрещен"; END_IF;
xPermissionToWork := xVseSist AND NOT xDryRunAlarm;


(* ============================================================ *)
(* 15. ЗАПИСЬ ВЫХОДОВ DO — НОВАЯ КАРТА (ТОЛЬКО 4 ВЫХОДА)          *)
(* ============================================================ *)
xDO[1]  := xDryRunOk;      // DO1 — дубляж сухого хода (=DI4)
xDO[2]  := xPumpsCmd;      // DO2 — пуск насосов фонтана
xDO[3]  := xLightCmd;      // DO3 — пуск подсветки
xDO[4]  := xDamperCmdRaw;  // DO4 — дубляж клапана добора (=DI5)
xDO[5]  := FALSE;
xDO[6]  := FALSE;
xDO[7]  := FALSE;
xDO[8]  := FALSE;
xDO[9]  := FALSE;
xDO[10] := FALSE;
xDO[11] := FALSE;
xDO[12] := FALSE;
xDO[13] := FALSE;
xDO[14] := FALSE;
xDO[15] := FALSE;
xDO[16] := FALSE;
