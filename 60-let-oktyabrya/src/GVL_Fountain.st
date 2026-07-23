(* ============================================================ *)
(* GVL_Fountain — переменные автоматики "60 Лет Октября"        *)
(* (на основе ДДЮТ / Саки Пруд)                                 *)
(*                                                              *)
(* === 60ЛО: ГЛАВНЫЕ ОТЛИЧИЯ ОТ ДДЮТ ===                        *)
(*  - Дозация (pH/альгицид/биопаг) на другом контроллере.       *)
(*  - Добор воды решает Мусидора — мы зеркалим DI5→DO4,         *)
(*    проверяем DI6 (20с).                                      *)
(*  - Только 4 физических DO. У света/насосов появилось         *)
(*    подтверждение реле (DI9/DI10, 2с).                        *)
(*  - ПР200 и резерв полива СПК не нужны вообще.                *)
(*                                                              *)
(* ВАЖНО: переменные, оставшиеся от ДДЮТ и не задействованные   *)
(* в новой логике, НЕ УДАЛЕНЫ — только помечены комментарием    *)
(* "60ЛО: не используется" — их значение ничем не пишется, но   *)
(* они остаются объявленными, чтобы не ломать привязки экранов. *)
(* Финальное решение по удалению — за тобой после проверки.     *)
(* ============================================================ *)

VAR_GLOBAL CONSTANT
    (* =x`== ДДЮТ:УДАЛИТЬ — шкала уровня чаши по AI1, не нужна === *)
    (*
    cWaterRawMin : REAL := 4.0;
    cWaterRawMax : REAL := 20.0;
    cWaterCmMin  : REAL := 0.0;
    cWaterCmMax  : REAL := 100.0;
    *)

    (* 60ЛО: не используется — были нужны только для *)
    (* PRG_PolivSPK.st, который выводится из проекта. *)
    cSlivRawMin : REAL := 4.0;
    cSlivRawMax : REAL := 20.0;
    cSlivCmMin  : REAL := 0.0;
    cSlivCmMax  : REAL := 100.0;
END_VAR


VAR_GLOBAL RETAIN
    aFountainLog       : ARRAY[1..60] OF WSTRING(60);
    iFountainLogCount  : INT;

    iAdminPassCorrect : INT := 1234;

    (* ===== ГЛАВНЫЕ ТУМБЛЕРЫ С ЭКРАНА ====================== *)
    xVseSist : BOOL := TRUE;
    iPumpSelect : INT := 2;   // насосы фонтана: 0=ручной,1=выкл,2=авто

    xNfEnable : BOOL := TRUE;   // 60ЛО: не используется в новой логике (была тупиковой ещё в ДДЮТ), оставлено для визуализации

    (* 60ЛО: не используется — старая система 2/3 датчиков и гистерезисов уровня. *)
    (* Добор полностью решает Мусидора, мы клапаном не управляем.                 *)
    iLevelSensorCountPending : INT := 2;
    tLevel1DebounceSec : INT := 20;
    tLevel2DebounceSec : INT := 20;
    tLevel3DebounceSec : INT := 20;
    iRefillOffDelayMin : INT := 2;
    iRefillOffDelaySec : INT := 0;

    iTimeZoneOffsetSec : INT := 10800;   // смещение часового пояса от UTC, сек

    (* === КОРРЕКЦИЯ УХОДА ЧАСОВ === RTC уходит вперёд ~15с/сутки. *)
    (* Раз в сутки в заданный час вычитаем iTimeDriftCorrSec секунд  *)
    (* из RTC. Вся логика — в PRG_TimeCorrect. Все параметры RETAIN, *)
    (* правятся с экрана.                                            *)
    xTimeDriftCorrEnable : BOOL := TRUE;   // включить авто-коррекцию
    iTimeDriftCorrSec    : INT  := 15;     // на сколько секунд отвести RTC назад
    iTimeDriftCorrHour   : INT  := 3;      // в котором часу (местное) применять, 0..23
    xTimeDriftCorrNow    : BOOL := FALSE;  // ручной триггер "скорректировать сейчас"
    iTimeDriftCorrCount  : INT;            // счётчик выполненных коррекций (диагностика)
    sTimeDriftLast       : WSTRING(30);    // дата последней коррекции (для экрана)

    (* === ЖУРНАЛ АВАРИЙ НА SD-КАРТУ (PRG_AlarmLogSD) ============== *)
    (* SD на СПК монтируется в /mnt/ufs/media/mmcblk0p1/ (док ОВЕН    *)
    (* «Архивация — СПК»). Карта: FAT16/FAT32, стиль разделов MBR.    *)
    (* Требуется библиотека CAA File в дереве проекта.               *)
    (* По фронту каждой аварии дописывается строка                    *)
    (*   "чч:мм дд.мм.гггг - <название>" в файл на карте.             *)
    xAlarmLogSDEnable : BOOL := TRUE;                                         // вкл/выкл запись на SD (все 3 журнала)
    sAlarmLogPath     : STRING(80) := '/mnt/ufs/media/mmcblk0p1/alarms.log';      // журнал АВАРИЙ
    sPumpLogPath      : STRING(80) := '/mnt/ufs/media/mmcblk0p1/pump_changes.log'; // журнал изменений ПЧ
    sSetpointLogPath  : STRING(80) := '/mnt/ufs/media/mmcblk0p1/setpoints.log';   // журнал изменений уставок

    iUvNfMinRunMin : INT := 20;   // 60ЛО: не используется (выхода на УФ нет, был информационным и в ДДЮТ)

    (* 60ЛО: не используется — старая система попыток добора. *)
    tRefillDurHours     : INT := 2;
    tBetweenRefillHours : INT := 12;
    iRefillAttemptsMax  : INT := 5;

    (* 60ЛО: не используется — дозация на другом контроллере. Экраны pH/альгицид/биопаг скрыты из меню. *)
    iPhSelect : INT := 2;
    iAlgSelect        : INT := 2;
    rAlgDoseMlPerDay  : REAL := 66.0;
    rAlgFlowMlPerHour : REAL := 1125.0;
    iBioSelect        : INT := 2;
    rBioDoseMlPerDay  : REAL := 33.0;
    rBioFlowMlPerHour : REAL := 1154.0;

    (* ===== ОКНО ИСПРАВНОСТИ ФИЛЬТРАЦИИ — АКТИВНО, счётчик промывок сохранён === *)
    iFilterMinRunMin   : INT := 30;    // порог наработки НФ, мин
    iFilterWindowHours : INT := 12;    // 60ЛО: не используется (устар. ещё в ДДЮТ)
    iNfHealthyWindowMin : INT := 0;    // 60ЛО: не используется (устар. ещё в ДДЮТ)

    (* === СЧЁТЧИК ПРОМЫВОК НФ — АКТИВНО, БЕЗ ИЗМЕНЕНИЙ АЛГОРИТМА === *)
    iNfLastOnHour  : INT;
    iNfLastOnMin   : INT;
    iNfLastOnDay   : INT;
    iNfLastOnMonth : INT;
    iNfLastOnYear  : INT;
    iNfFlushStage  : INT;
    xNfFlushReady  : BOOL := TRUE;
    iNfFlushCount  : INT;
    iNfFlushHour   : INT;
    iNfFlushMin    : INT;
    iNfFlushDay    : INT;
    iNfFlushMonth  : INT;
    iNfFlushYear   : INT;

    iNfRunMinAccum    : INT;    // 60ЛО: не используется (устар. ещё в ДДЮТ)
    iNfRunSecAccum    : DINT;   // 60ЛО: не используется (устар. ещё в ДДЮТ)
    iNfHealthySecLeft : DINT;   // 60ЛО: не используется (устар. ещё в ДДЮТ)
    iNfHealthyHoursLeft : INT;  // 60ЛО: не используется (устар. ещё в ДДЮТ)
    iNfHealthyMinLeft   : INT;  // 60ЛО: не используется (устар. ещё в ДДЮТ)
    xNfProven         : BOOL;   // 60ЛО: не используется (устар. ещё в ДДЮТ)
    xNfWorkPrev       : BOOL;   // АКТИВНО — детект фронта для счётчика промывок
    iNfContinuousRunHour : INT;
    iNfContinuousRunMin  : INT;
    iNfContinuousRunSec  : INT;

    xNfFirstScanDone : BOOL;
    iNfJustEndedSec  : INT;

    xZapretDozacii : BOOL := TRUE;   // 60ЛО: не используется (дозация на другом контроллере)

    iDamperSelect : INT := 2;   // 60ЛО: не используется — заслонка теперь просто зеркало DI5→DO4

    (* ===== СВЕТ — АКТИВНО ==================================== *)
    iLightSelect : INT  := 2;       // свет: 0=ручной,1=выкл,2=авто(закат)
    iSoundMode   : INT  := 2;       // FUTURE_SOUND, не используется
    xSoundEnable : BOOL := TRUE;    // FUTURE_SOUND, не используется

    (* ===== РАСЧЁТ ЗАКАТА — АКТИВНО, БЕЗ ИЗМЕНЕНИЙ ============== *)
    rSunLatitude          : REAL := 44.578865;
    rSunLongitude         : REAL := 33.51621;
    rSunLongitudePrev     : REAL := 33.51621;
    iChoseTimeZone        : INT  := 14;
    iSunsetCorrectSigned  : INT  := 0;

    iOffHourWeekday    : INT := 23;
    iOffMinuteWeekday  : INT := 0;
    iOffHourWeekend    : INT := 23;
    iOffMinuteWeekend  : INT := 0;

    iLightScheduleMode : INT := 3;   // 0=Авто,1=Вкл,2=Выкл,3=Астро
    iPumpScheduleMode  : INT := 0;   // 0=Авто,1=Вкл,2=Выкл

    iLightOnHourWeekday   : INT := 18;
    iLightOnMinuteWeekday : INT := 0;
    iLightOnHourWeekend   : INT := 18;
    iLightOnMinuteWeekend : INT := 0;

    iPumpOnHourWeekday    : INT := 8;
    iPumpOnMinuteWeekday  : INT := 0;
    iPumpOnHourWeekend    : INT := 8;
    iPumpOnMinuteWeekend  : INT := 0;

    (* 60ЛО: не используется — накопители ручной наработки НФ/pH из ДДЮТ. *)
    iNfManualRunMinBuffer : INT;
    iNfManualRunMinToday  : INT;
    iNfManualRunHourTotal : INT;
    iPhManualRunMinBuffer : INT;
    iAlgManualRunMinBuffer : INT;
    iPhManualRunSecAccum : DINT;
    iPhManRunSec  : INT;
    iPhManRunHour : INT;
    iPhManRunMin  : INT;

    (* 60ЛО: не используется — накопленная наработка дозаторов, дозация не наша. *)
    iPhRunHourTotal : INT;
    iAlgRunHour : INT;
    iAlgRunMinBuffer2 : INT;
    iPhRunSecAccum : DINT;
    iPhRunSecDisp  : INT;
    iAlgRunSecAccum : DINT;
    iAlgRunSec  : INT;
    iPhStartCount  : INT;
    iAlgStartCount  : INT;

    (* 60ЛО: не используется — долговая система альгицида/биопага. *)
    rAlgDebtSec         : REAL := 0.0;
    udiAlgLastDebtStamp : UDINT := 0;
    xAlgDebtInitDone    : BOOL := FALSE;
    iAlgLastDoseDay     : INT := 0;
    iAlgLastDoseMonth   : INT := 0;
    iAlgLastDoseYear    : INT := 0;
    iAlgLastDoseHourR   : INT := 0;
    iAlgLastDoseMinR    : INT := 0;
    iAlgLastDoseSecR    : INT := 0;

    rBioDebtSec         : REAL := 0.0;
    udiBioLastDebtStamp : UDINT := 0;
    xBioDebtInitDone    : BOOL := FALSE;
    iBioLastDoseDay     : INT := 0;
    iBioLastDoseMonth   : INT := 0;
    iBioLastDoseYear    : INT := 0;
    iBioLastDoseHourR   : INT := 0;
    iBioLastDoseMinR    : INT := 0;
    iBioLastDoseSecR    : INT := 0;
    iBioRunSecAccum     : DINT;
    iBioRunSecDisp      : INT;
    iBioStartCount      : INT;
    iBioManSetMin    : INT := 10;
    iBioManRemMinRaw    : INT;
    iBioManRemSecRaw    : INT;
END_VAR


VAR_GLOBAL
    (* ===== ОЧЕРЕДИ SD-ЖУРНАЛОВ (ПЧ и уставки) ================== *)
    (* Наполняют F_PumpLogWrite / F_FountainLogWrite, забирает       *)
    (* PRG_AlarmLogSD (кольцевые буферы, 1 продюсер + 1 консьюмер,   *)
    (* всё в одной задаче — гонок нет). Журнал аварий у POU свой.    *)
    awsSdPumpQ    : ARRAY[1..20] OF WSTRING(120);
    iSdPumpQHead  : INT;
    iSdPumpQTail  : INT;
    iSdPumpQCount : INT;
    awsSdSetpQ    : ARRAY[1..20] OF WSTRING(120);
    iSdSetpQHead  : INT;
    iSdSetpQTail  : INT;
    iSdSetpQCount : INT;

    (* ===== ЖУРНАЛ ИЗМЕНЕНИЙ ФОНТАНА — АКТИВНО, БЕЗ ИЗМЕНЕНИЙ === *)
    xAskClearFountainLog     : BOOL;
    iFountainLogPinEntry     : INT;
    xFountainLogPinSubmit    : BOOL;
    xFountainLogClearedMsg   : BOOL;
    xFountainLogPassBadMsg   : BOOL;
    xFountainLogClear        : BOOL;

    iPumpLogPinEntry     : INT;
    xPumpLogPinSubmit    : BOOL;
    xPumpLogClearedMsg   : BOOL;
    xPumpLogPassBadMsg   : BOOL;

    xFountainLogInitialized : BOOL;

    (* "Тени" отслеживаемых параметров — те, что реально сравниваются в новой *)
    (* логике, помечены АКТИВНО, остальные (были в ДДЮТ) — не используются.  *)
    iLogPrevFilterMinRunMin  : INT;   // АКТИВНО
    iLogPrevUvNfMinRunMin    : INT;   // 60ЛО: не используется
    rLogPrevAlgDoseMlPerDay  : REAL;  // 60ЛО: не используется
    rLogPrevAlgFlowMlPerHour : REAL;  // 60ЛО: не используется
    rLogPrevBioDoseMlPerDay  : REAL;  // 60ЛО: не используется
    rLogPrevBioFlowMlPerHour : REAL;  // 60ЛО: не используется
    iLogPrevAlgManSetMin     : INT;   // 60ЛО: не используется
    iLogPrevBioManSetMin     : INT;   // 60ЛО: не используется
    iLogPrevPhSelect         : INT;   // 60ЛО: не используется
    iLogPrevAlgSelect        : INT;   // 60ЛО: не используется
    iLogPrevBioSelect        : INT;   // 60ЛО: не используется
    xLogPrevVseSist          : BOOL;  // АКТИВНО
    iLogPrevDamperSelect     : INT;   // 60ЛО: не используется
    iLogPrevLightSelect      : INT;   // АКТИВНО
    iLogPrevPumpSelect       : INT;   // АКТИВНО
    iLogPrevLevelSensorCount : INT;   // 60ЛО: не используется
    iLogPrevLightScheduleMode : INT;  // АКТИВНО
    iLogPrevPumpScheduleMode  : INT;  // АКТИВНО
    iLogPrevLightOnHourWeekday   : INT;   // АКТИВНО
    iLogPrevLightOnMinuteWeekday : INT;   // АКТИВНО
    iLogPrevLightOnHourWeekend   : INT;   // АКТИВНО
    iLogPrevLightOnMinuteWeekend : INT;   // АКТИВНО
    iLogPrevPumpOnHourWeekday    : INT;   // АКТИВНО
    iLogPrevPumpOnMinuteWeekday  : INT;   // АКТИВНО
    iLogPrevPumpOnHourWeekend    : INT;   // АКТИВНО
    iLogPrevPumpOnMinuteWeekend  : INT;   // АКТИВНО
    iLogPrevOffHourWeekday       : INT;   // АКТИВНО
    iLogPrevOffMinuteWeekday     : INT;   // АКТИВНО
    iLogPrevOffHourWeekend       : INT;   // АКТИВНО
    iLogPrevOffMinuteWeekend     : INT;   // АКТИВНО
    iLogPrevSunsetCorrectSigned  : INT;   // АКТИВНО
    iLogPrevChoseTimeZone        : INT;   // АКТИВНО
    rLogPrevSunLatitude          : REAL;  // АКТИВНО
    rLogPrevSunLongitude         : REAL;  // АКТИВНО
    xLogPrevAlarmReset       : BOOL;      // АКТИВНО
    iLogPrevLevel1DebounceSec   : INT;    // 60ЛО: не используется
    iLogPrevLevel2DebounceSec   : INT;    // 60ЛО: не используется
    iLogPrevLevel3DebounceSec   : INT;    // 60ЛО: не используется
    iLogPrevRefillOffDelayMin   : INT;    // 60ЛО: не используется
    iLogPrevRefillOffDelaySec   : INT;    // 60ЛО: не используется
    iLogPrevRefillDurHours      : INT;    // 60ЛО: не используется
    iLogPrevBetweenRefillHours  : INT;    // 60ЛО: не используется
    iLogPrevRefillAttemptsMax   : INT;    // 60ЛО: не используется

    rSlivRaw     : REAL;    // 60ЛО: не используется (был для PRG_PolivSPK.st)
    rSlivLevelCm : REAL;    // 60ЛО: не используется

    (* ===== СУХОЙ ХОД ============================================ *)
    xLevel1   : BOOL;   // 60ЛО: не используется — старая система 2/3 датчиков
    xLevel2   : BOOL;   // 60ЛО: не используется
    xLevel3   : BOOL;   // 60ЛО: не используется

    xPump1Work : BOOL;   // ← DI1, информационный
    xPump2Work : BOOL;   // ← DI2, информационный
    xPump3Work : BOOL;   // ← DI3, информационный, НОВЫЙ

    xDryRunOk    : BOOL;   // ← DI4, 1=норма (сигнал уже готов от Мусидоры)
    xDryRunAlarm : BOOL;   // = NOT xDryRunOk, ЖИВАЯ, САМАЯ ПЕРВАЯ авария в списке
    xDryRunRelayFb    : BOOL;   // ← DI8, подтверждение реле сухого хода
    xDryRunRelayAlarm : BOOL;   // авария: DO1 и DI8 разошлись >2с (ЖИВАЯ, самосброс)

    xLevel2LowConfirmed  : BOOL;  // 60ЛО: не используется
    xLevel2HighConfirmed : BOOL;  // 60ЛО: не используется
    xLevel3HighConfirmed : BOOL;  // 60ЛО: не используется
    xRefillStartConfirmed : BOOL; // 60ЛО: не используется
    xRefillEnoughConfirmed : BOOL; // 60ЛО: не используется
    xRefillOffConfirmed : BOOL;   // 60ЛО: не используется

    (* ===== КЛАПАН ДОБОРА — простое зеркало DI5→DO4 ============= *)
    xDamperCmdOpen    : BOOL;        // 60ЛО: не используется — старая логика управления клапаном
    xDamperCmdRaw     : BOOL;        // ← DI5, "пуск добора" от Мусидоры, копируется на DO4
    xDamperForceOpen   : BOOL;       // 60ЛО: не используется
    xDamperForceClose  : BOOL;       // 60ЛО: не используется
    xDamperZapretDobor : BOOL;       // 60ЛО: не используется
    xDamperRelayFb   : BOOL;         // ← DI6, подтверждение положения клапана
    xDamperRelayAlarm : BOOL;        // авария: DO4 и DI6 разошлись >20с (ЖИВАЯ, самосброс)
    sDamperPosition   : WSTRING(20); // "Открыт" / "Закрыт" (по DI6)
    sDamperFullStatus : WSTRING(50); // 60ЛО: не используется

    xOnlyTwoLevels : BOOL;   // 60ЛО: не используется
    iRefillAttempts   : INT;   // 60ЛО: не используется
    xRefillPauseRun   : BOOL;  // 60ЛО: не используется
    xRefillAttemptsAlarm : BOOL;  // 60ЛО: не используется

    (* ===== РАЗРЕШЕНИЯ И ФИЛЬТРАЦИЯ ======================= *)
    xPermissionToWork : BOOL;        // = xVseSist AND NOT xDryRunAlarm, общий статус для визуализации
    xNfWork           : BOOL;        // ← DI7, контактор фильтрации (НФ физически работает)
    xNfHealthy        : BOOL;        // непрерывная наработка НФ ≥ iFilterMinRunMin
    xNfPermission     : BOOL;        // 60ЛО: не используется
    xBlokDozacii      : BOOL;        // 60ЛО: не используется
    xFiltrationBlock  : BOOL;        // 60ЛО: не используется (всегда FALSE)

    xNfAutoSwitch    : BOOL;   // ← DI11, ручка режима фильтрации = АВТО
    xNfManualSwitch  : BOOL;   // ← DI12, ручка режима фильтрации = РУЧНОЙ
    xNfManualRelayAlarm : BOOL; // авария: ручной режим (DI12), а DI7=0 более 2с (ЖИВАЯ, самосброс)
    sNfModeStatus     : WSTRING(30);  // "Авто"/"Ручной"/"?" — текст режима по DI11/DI12

    (* ===== ОПАСНАЯ СИТУАЦИЯ: СУХОЙ ХОД + РУЧНАЯ ФИЛЬТРАЦИЯ ===== *)
    xDangerCondition       : BOOL;   // = xDryRunAlarm AND xNfManualSwitch, живая
    xDangerCondition_Prev  : BOOL;   // для детекта фронта появления
    xShowDangerDialog      : BOOL;   // видимость диалога — привязать к элементу экрана
    xConfirmDangerDialog   : BOOL;   // кнопка "ОК" пишет сюда := TRUE

    (* ===== ВЫХОДЫ-КОМАНДЫ ================================ *)
    xUvCmd    : BOOL;                // 60ЛО: не используется (выхода на УФ нет)
    xPumpsCmd : BOOL;                // → DO2
    xLightCmd : BOOL;                // → DO3

    (* ===== pH — 60ЛО: не используется целиком, дозация на другом контроллере === *)
    xPhEnable    : BOOL;
    xPhRunCmd    : BOOL;
    xPhOutput    : BOOL;
    xPhRelayFb   : BOOL;
    xPhManualRun : BOOL;
    iPhRunMinToday  : INT;
    iPhRunMinBuffer : INT;
    xPhRelayAlarm : BOOL;

    (* ===== АЛЬГИЦИД — 60ЛО: не используется целиком =========== *)
    xAlgEnable    : BOOL;
    xAlgRunCmd    : BOOL;
    xAlgOutput    : BOOL;
    iAlgAutoStartCount : INT;
    xAlgRelayFb   : BOOL;
    xAlgManualRun : BOOL;
    iAlgManRunSecAccum  : DINT;
    iAlgManRunHour : INT;
    iAlgManRunMin  : INT;
    iAlgManRunSec   : INT;
    xAlgManualTimeStart : BOOL;
    xAlgManualTimeStop  : BOOL;
    xAlgManualTimeRun   : BOOL;
    xAskAlgManualTimeStart : BOOL;
    iAlgManSetMin    : INT;
    iAlgManRemMinRaw    : INT;
    iAlgManRemSecRaw    : INT;
    iAlgManRemHour   : INT;
    iAlgManRemMin : INT;
    iAlgManRemSec : INT;
    rAlgRemainSec  : REAL;
    iAlgRemainHour : INT;
    iAlgRemainMin  : INT;
    iAlgRemainSec  : INT;
    rAlgNextDoseSec : REAL;
    iAlgNextHour : INT;
    iAlgNextMin  : INT;
    iAlgNextSec  : INT;
    rAlgDoseSecCalc : REAL;
    iAlgDoseHour : INT;
    iAlgDoseMin : INT;
    iAlgDoseSec : INT;
    iAlgRunMin  : INT;
    iAlgRunMinBuffer : INT;
    iAlgStartToday   : INT;
    xAlgAlarm        : BOOL;
    rAlgFlowLPerHour : REAL;
    xAlgDosing           : BOOL;
    sAlgDosingStatus     : WSTRING(10);
    iAlgDebtMin      : INT;
    iAlgDebtSec      : INT;
    iAlgDebtHour     : INT;
    sAlgLastDebtTime : WSTRING(30);
    iAlgLastDoseHour : INT;
    iAlgLastDoseMin  : INT;
    iAlgLastDoseSec  : INT;
    sAlgLastDoseTime : WSTRING(30);
    xAlgRelayAlarm : BOOL;

    (* ===== БИОПАГ — 60ЛО: не используется целиком ============== *)
    xBioRunCmd          : BOOL;
    xBioOutput          : BOOL;
    xBioRelayFb         : BOOL;
    xBioDosing          : BOOL;
    sBioDosingStatus    : WSTRING(10);
    rBioDoseSecCalc     : REAL;
    iBioDoseHour    : INT;
    iBioDoseMin     : INT;
    iBioDoseSec     : INT;
    iBioDebtHour        : INT;
    iBioDebtMin         : INT;
    iBioDebtSec         : INT;
    rBioNextDoseSec     : REAL;
    iBioNextHour    : INT;
    iBioNextMin     : INT;
    iBioNextSec     : INT;
    iBioRunHour : INT;
    iBioRunMin  : INT;
    iBioRunSec   : INT;
    iBioStartToday      : INT;
    iBioDebtDays        : INT;
    iAlgDebtDays        : INT;
    sBioLastDebtTime    : WSTRING(30);
    sBioLastDoseTime    : WSTRING(30);
    iBioLastDoseHour    : INT;
    iBioLastDoseMin     : INT;
    iBioLastDoseSec     : INT;
    xBioAlarm           : BOOL;
    rBioFlowLPerHour    : REAL;
    xBioEnable             : BOOL;
    xBioManualRun          : BOOL;
    iBioManRunSecAccum  : DINT;
    iBioManRunHour : INT;
    iBioManRunMin  : INT;
    iBioManRunSec   : INT;
    xBioManualTimeStart : BOOL;
    xBioManualTimeStop  : BOOL;
    xBioManualTimeRun   : BOOL;
    xAskBioManualTimeStart : BOOL;
    iBioManRemHour    : INT;
    iBioManRemMin : INT;
    iBioManRemSec : INT;
    xBioRelayAlarm : BOOL;

    (* ===== СВЕТ ========================================== *)
    xLightEnable     : BOOL;
    xLightForceOn    : BOOL;          // = "ручной пуск" (iLightSelect=0), OR-приоритет
    xLightFault      : BOOL;          // 60ЛО: не используется, всегда FALSE

    xLightRelayFb    : BOOL;   // ← DI10, подтверждение работы подсветки
    xLightRelayAlarm : BOOL;   // авария: DO3 и DI10 разошлись >2с (ЖИВАЯ, самосброс)

    (* ===== РАСЧЁТ ЗАКАТА — диагностика для экрана, АКТИВНО ===== *)
    rSunTimeZone       : REAL;
    iSunsetCorrectMin     : INT;
    xSunsetCorrectEarlier : BOOL;
    xSunsetActive      : BOOL;
    xSunsetCoordError  : BOOL;
    iSunsetHourCalc    : INT;
    iSunsetMinuteCalc  : INT;
    iSunsetTimeLeftH   : INT;
    iSunsetTimeLeftM   : INT;
    iSunsetDayOfYear   : INT;
    xIsWeekend         : BOOL;
    sCurrentDateStr    : WSTRING(12);

    xScheduleLightOut      : BOOL;
    xSchedulePumpOut       : BOOL;
    iScheduleLightOnHour   : INT;
    iScheduleLightOnMinute : INT;
    iScheduleOffHour       : INT;
    iScheduleOffMinute     : INT;
    iSchedulePumpOnHour    : INT;
    iSchedulePumpOnMinute  : INT;

    xLightShowInputFields   : BOOL;
    xLightShowComputedTime  : BOOL;
    xLightShowAlwaysOnText  : BOOL;
    xLightShowAlwaysOffText : BOOL;
    xPumpShowInputFields    : BOOL;
    xPumpShowComputedTime   : BOOL;
    xPumpShowAlwaysOnText   : BOOL;
    xPumpShowAlwaysOffText  : BOOL;
    xOffTimeVisible         : BOOL;

    xLightOuterForcedOn  : BOOL;
    xLightOuterForcedOff : BOOL;
    xPumpOuterForcedOn   : BOOL;
    xPumpOuterForcedOff  : BOOL;

    (* ===== НАСОСЫ ФОНТАНА ================================ *)
    xManualPermissionNasos : BOOL;
    xPumpsManualOn : BOOL;           // 60ЛО: не используется (устар.)
    xPumpsForceOn  : BOOL;           // = "ручной пуск" (iPumpSelect=0), OR-приоритет

    xPumpRelayFb    : BOOL;   // ← DI9, подтверждение работы насосов
    xPumpRelayAlarm : BOOL;   // авария: DO2 и DI9 разошлись >2с (ЖИВАЯ, самосброс)

    (* ===== ЗВУК (FUTURE_SOUND) — 60ЛО: не используется ========= *)
    xSoundOnSchedule : BOOL;
    xSoundOutput     : BOOL;
    xSoundManualOn   : BOOL;

    (* ===== ФИЛЬТРАЦИЯ (мониторинг) — 60ЛО: не используется ===== *)
    (* Старая карта ДДЮТ (DI1/DI2/DI3/DI4/DI5) не совпадает с новой *)
    (* картой 60ЛО — переменные оставлены объявленными, но не      *)
    (* присваиваются нигде в PRG_Fountain.st.                       *)
    xFilter1Drive     : BOOL;
    xFilter2Drive     : BOOL;
    xDriveStart       : BOOL;
    xUvContactor      : BOOL;
    xFilter1Contactor : BOOL;
    xManualFilter     : BOOL;

    (* ===== АВАРИИ ======================================== *)
    xAlarmFountain      : BOOL;      // общая авария
    xAlarmReset         : BOOL;

    (* ===== ФЛАГИ ПОДТВЕРЖДЕНИЯ СБРОСА ==================== *)
    xAskResetPh     : BOOL := FALSE;   // 60ЛО: не используется
    xAskResetAlg    : BOOL := FALSE;   // 60ЛО: не используется
    xAskResetBio    : BOOL := FALSE;   // 60ЛО: не используется
    xAskResetRefill : BOOL := FALSE;   // 60ЛО: не используется
    xAskResetNfFlush : BOOL := FALSE;  // АКТИВНО — диалог "Сбросить счётчик промывок?"
    xAskResetAll    : BOOL := FALSE;   // 60ЛО: не используется
    xAskResetAlarms : BOOL := FALSE;   // АКТИВНО — диалог сброса всех аварий
    xConfirmResetPh  : BOOL := FALSE;  // 60ЛО: не используется
    xConfirmResetAlg : BOOL := FALSE;  // 60ЛО: не используется
    xConfirmResetBio : BOOL := FALSE;  // 60ЛО: не используется
    xConfirmResetAll : BOOL := FALSE;  // 60ЛО: не используется
    xConfirmResetRefill  : BOOL := FALSE;  // 60ЛО: не используется
    xConfirmResetNfFlush : BOOL := FALSE;  // АКТИВНО — реальный ST-код в PRG_Fountain

    (* ===== МИГАНИЕ ====================================== *)
    xBlinkFast : BOOL;
    xBlinkSlow : BOOL;

    (* ===== СТРОКОВЫЕ СТАТУСЫ ============================= *)
    sVseSistStatus    : WSTRING(30);
    sPermissionStatus : WSTRING(30);   // насосы фонтана
    sNfEnableStatus   : WSTRING(30);   // 60ЛО: не используется
    sPhStatus         : WSTRING(30);   // 60ЛО: не используется
    sAlgStatus         : WSTRING(30);  // 60ЛО: не используется
    sBioStatus         : WSTRING(30);  // 60ЛО: не используется
    sLightStatus      : WSTRING(30);
    sSoundStatus      : WSTRING(30);   // 60ЛО: не используется
    sRefillStatus     : WSTRING(30);   // 60ЛО: не используется
    sAlarmStopStatus  : WSTRING(30);
    sAlarmCauses      : WSTRING(255);
    sNfStatus         : WSTRING(30);
    sNfHealthyStatus  : WSTRING(30);

    (* ===== ВРЕМЯ (RTC) ================================== *)
    iCurrentYear         : INT;
    iCurrentMonth        : INT;
    iCurrentDay          : INT;
    iCurrentHour         : INT;
    iCurrentMinute       : INT;
    iCurrentSecond       : INT;
    iCurrentTotalMinutes : INT;

    (* === 60ЛО:УДАЛИТЬ ЦЕЛИКОМ — ПР200 и резерв полива СПК ======= *)
    (* Файлы PRG_PR200.st и PRG_PolivSPK.st выводятся из проекта.  *)
    (* Все переменные ниже нужны были только для их компиляции.     *)
    (*
    wPr200SuhoyHod_Net, wPr200Podpitka_Net, wPr200Norma_Net,
    wPr200Pereliv_Net, wPr200Delay_Net, wPr200LevelRead, wPr200StatusRead,
    rPr200SuhoyHod_Cur, rPr200Podpitka_Cur, rPr200Norma_Cur, rPr200Pereliv_Cur,
    rPr200Delay_Cur, rPr200LevelCm, rPr200SuhoyHod_New, rPr200Podpitka_New,
    rPr200Norma_New, rPr200Pereliv_New, rPr200Delay_New,
    wPr200SuhoyHod_Write, wPr200Podpitka_Write, wPr200Norma_Write,
    wPr200Pereliv_Write, wPr200Delay_Write, wPr200ApplyCmd,
    xPr200Online, xPr200DoborActive, xPr200SlivActive, xPr200PolivActive,
    xPr200ErrDobor, xPr200ErrSliv, xPr200ErrPoliv, xApplyBtn,
    xSpkPolivMode, xSpkRawDI17, xSpkRawDI18, xSpkPolivMode_OLD,
    xPr200OnlineStable, iPr200CommFilterSec, xSpkLevelSensorOk,
    xMsgPr200Offline, xMsgSpkNoSensor, xSpkDI_Dobor, xSpkDI_Poliv,
    xSpkDO_Dobor, xSpkDO_Poliv, xSpkRuchDobor, xSpkRuchPoliv,
    xSpkZapDobor, xSpkZapPoliv, xSpkDoborOn, xSpkPolivOn, xSpkErrDobor,
    xSpkErrPoliv, xSpkErrPereliv, iSpkErrDelaySec, sSpkDoborStatus,
    sSpkPolivStatus, sSpkManualStatus, wSpkMV_Inputs, xSpkMV_Error,
    xSpkDI, wSpkMU_Outputs, wSpkMU_OutputsRead, xSpkMU_Error,
    wSpkMU_SafeOutputs, xSpkMU_WriteSafe, xSpkDO, rSpkLevelRaw, xSpkAI_Error
    *)
END_VAR
