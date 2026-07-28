PROGRAM PRG_Fountain
(* ============================================================ *)
(* PRG_Fountain — автоматика фонтана ДДЮТ                       *)
(* (на основе Fontan_V1 / Саки Пруд)                             *)
(* ============================================================ *)
VAR
    (* RTC *)
    dwUtcTime : DWORD;
    sysTime   : SYSTIMEDATE;
    rtcResult : DWORD;

    (* Расчёт заката — NOAA (порт с ПР200) *)
    fbTimeZone : FB_TimeZoneSelect;     // === ДДЮТ:НОВОЕ === выбор часового пояса комбобоксом
    fbSunset : FB_SunsetRelay;
    fbSchedule : FB_FountainSchedule;   // === ДДЮТ:НОВОЕ === пока только считается,
                                        // выходы не подключены к реальным DO
                                        // (см. блоки 11а, 12, 14 ниже)

    (* Мигание ламп *)
    tonBlinkFastOff : TON;
    tonBlinkSlowOff : TON;

    (* Исправность НФ — простая непрерывная наработка *)
    tonNfContinuous : TON;
    tonSecTick   : TON;

    (* Наработка в ручном режиме *)
    tonNfManualTick : TON;
    tonPhManualTick : TON;
    tonAlgManualTick : TON;

    (* Счётчик пусков и наработка pH *)
    rtrigPhStart : R_TRIG;
    tonPhRunTick : TON;

    (* Наработка альгицида *)
    tonAlgRunTick : TON;
    tonAlgManualSecTick : TON;
    tonAlgDebtTick : TON;
    tonUvNfRun : TON;

    iPrevDay     : INT;

    (* === ДДЮТ (round 3) — гистерезис по трём датчикам уровня === *)
    tonLevel1Debounce : TON;   // антидребезг Уровня1 (сухой ход, DI7=0)
    tonLevel2Low      : TON;   // антидребезг Уровня2=0 (старт добора)
    tonLevel2High     : TON;   // антидребезг Уровня2=1 (стоп, режим 2 датчика)
    tonLevel3High     : TON;   // антидребезг Уровня3=1 (стоп, режим 3 датчика)
    tonRefillOffDelay : TON;   // доп. задержка выключения добора после "хватит"
    tLevel1Debounce   : TIME;  // = tLevel1DebounceSec (с экрана)
    tLevel2Debounce   : TIME;  // = tLevel2DebounceSec (с экрана)
    tLevel3Debounce   : TIME;  // = tLevel3DebounceSec (с экрана)
    tRefillOffDelay   : TIME;  // = iRefillOffDelayMin/Sec (с экрана)

    (* === ДДЮТ:ВОЗВРАЩЕНО (было в Саки) — система попыток добора === *)
    tonRefillTry   : TON;   // отсчёт длительности одной попытки (tRefillDurHours)
    tonRefillPause : TON;   // пауза между неудачными попытками (tBetweenRefillHours)
    tRefillDur     : TIME;  // = tRefillDurHours (с экрана)
    tBetweenRefill : TIME;  // = tBetweenRefillHours (с экрана)
    xRefillTryingAuto : BOOL; // клапан был открыт автоматикой (не форс-кнопкой) на прошлом цикле
    iClearIdx : INT;   // === ДДЮТ:НОВОЕ === рабочая переменная цикла очистки aFountainLog

    (* === ДДЮТ:НОВОЕ — таймеры автоскрытия сообщений о вводе пароля === *)
    tonFountainLogClearedMsg : TON;  // "Журнал фонтана сброшен", 3 сек
    tonFountainLogPassBadMsg : TON;  // "Пароль не подошёл" (фонтан), 3 сек
    tonPumpLogClearedMsg     : TON;  // "Журнал ПЧ сброшен", 3 сек
    tonPumpLogPassBadMsg     : TON;  // "Пароль не подошёл" (ПЧ), 3 сек

    (* === ДДЮТ:НОВОЕ — авария реле обратной связи дозаторов === *)
    tonPhRelayAlarm  : TON;   // pH: команда есть, DI9 молчит 10с
    tonAlgRelayAlarm : TON;   // альгицид: команда есть, DI11 молчит 10с
    tonBioRelayAlarm : TON;   // биопаг: команда есть, DI10 молчит 10с
    tonDryRunRelayAlarm : TON; // DO13 vs DI6: расхождение 10с

    iAlgDebtDays     : INT;
END_VAR


(* ============================================================ *)
(* 1. ЧТЕНИЕ СИСТЕМНОГО ВРЕМЕНИ (RTC)                          *)
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

(* Дата "дд.мм.гггг" для экрана астрореле (и не только) *)
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
(* 2. РАСПАКОВКА ВХОДОВ DI — КАРТА ДДЮТ                         *)
(* ============================================================ *)
xFilter1Drive     := xDI[1];    // ПЧ1 насос фонтана (работа)
xFilter2Drive     := xDI[2];    // ПЧ2 насос фонтана (работа)
xDriveStart       := xDI[3];    // разрешение работы частотников
xUvContactor      := xDI[4];    // контактор УФ (мониторинг)
xFilter1Contactor := xDI[5];    // контактор фильтр.насоса → наработка НФ
xDryRunRelayFb    := xDI[6];    // обратная связь DO13 (подтверждение факта срабатывания)
xLevel1           := xDI[7];    // УРОВЕНЬ 1 (везде: 0=сухой ход)
xLevel2           := xDI[8];    // УРОВЕНЬ 2 (везде: 0=старт добора; режим 2 датчика: 1=стоп)
xPhRelayFb        := xDI[9];    // подтверждение работы pH
xBioRelayFb       := xDI[10];   // подтверждение работы биопаг
xAlgRelayFb       := xDI[11];   // подтверждение работы альгицид
xLevel3           := xDI[12];   // УРОВЕНЬ 3 (ТОЛЬКО режим 3 датчика: 1=стоп добора)
(* DI13..DI16 — свободны *)


(* ============================================================ *)
(* 2а. РЕЖИМЫ — ЕДИНЫЙ 3-ПОЗИЦИОННЫЙ СЕЛЕКТОР НА УЗЕЛ            *)
(* ============================================================ *)
(* === ДДЮТ:НОВОЕ === Вместо двух раздельных элементов на экране *)
(* (тумблер "разрешение" + отдельная кнопка "ручной пуск") —      *)
(* один выбор из трёх значений, который сам раскладывается на    *)
(* пару (Enable, ManualForce). Дальше по коду (блоки pH/альгицид/*)
(* биопаг/свет/насосы) НИЧЕГО НЕ МЕНЯЛОСЬ — они как читали        *)
(* xPhEnable/xPhManualRun и т.п., так и читают, просто теперь     *)
(* источник этих переменных — здесь, а не прямые тумблеры.        *)
(*   0 = Ручной пуск (принудительно вкл, минуя автоматику)        *)
(*   1 = Выкл (запрет) — и ЛЮБОЕ некорректное значение тоже       *)
(*   2 = Авто (штатная логика)                                    *)

(* pH *)
IF iPhSelect = 0 THEN
    xPhEnable    := FALSE;
    xPhManualRun := TRUE;
ELSIF iPhSelect = 2 THEN
    xPhEnable    := TRUE;
    xPhManualRun := FALSE;
ELSE
    xPhEnable    := FALSE;
    xPhManualRun := FALSE;
END_IF;

(* Альгицид *)
IF iAlgSelect = 0 THEN
    xAlgEnable    := FALSE;
    xAlgManualRun := TRUE;
ELSIF iAlgSelect = 2 THEN
    xAlgEnable    := TRUE;
    xAlgManualRun := FALSE;
ELSE
    xAlgEnable    := FALSE;
    xAlgManualRun := FALSE;
END_IF;

(* Биопаг *)
IF iBioSelect = 0 THEN
    xBioEnable    := FALSE;
    xBioManualRun := TRUE;
ELSIF iBioSelect = 2 THEN
    xBioEnable    := TRUE;
    xBioManualRun := FALSE;
ELSE
    xBioEnable    := FALSE;
    xBioManualRun := FALSE;
END_IF;

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

(* === ДДЮТ:НОВОЕ === Та же пара флагов, что и у насосов ниже. *)
xLightOuterForcedOn  := (iLightSelect = 0);  // "Ручной" — свет ВСЕГДА вкл, расписание не участвует
xLightOuterForcedOff := (iLightSelect = 1);  // "Выкл"   — свет ВСЕГДА выкл, расписание не участвует

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

(* === ДДЮТ:НОВОЕ === Флаги "внешний селектор перебивает расписание" *)
(* для экрана отладки/графика — чтобы оператор видел, что итоговое   *)
(* время из FB_FountainSchedule СЕЙЧАС НЕ ДЕЙСТВУЕТ, потому что        *)
(* iPumpSelect/iLightSelect стоит не в "Авто". Считаем прямо здесь,    *)
(* НЕ на экране (после истории с опечаткой в самодельном выражении     *)
(* на визуализации — простые готовые булевы, без сравнений на экране). *)
xPumpOuterForcedOn  := (iPumpSelect = 0);  // "Ручной" — насосы ВСЕГДА вкл, расписание не участвует
xPumpOuterForcedOff := (iPumpSelect = 1);  // "Выкл"   — насосы ВСЕГДА выкл, расписание не участвует

(* Заслонка добора — === ДДЮТ:НОВОЕ ===                            *)
(* 0=Ручной: открыто несмотря ни на что (даже при сухом ходе — как  *)
(*   и у остальных узлов, форс-кнопки работают через OR).           *)
(* 1=Выкл: закрыта принудительно И запрет нового автоматического    *)
(*   добора (обе переменные вместе — заслонка не откроется, пока     *)
(*   явно не переключат на Авто).                                    *)
(* 2=Авто: обе форс-переменные и запрет сняты — обычная логика по    *)
(*   датчикам (гистерезис + система попыток из блока 6/6а).          *)
IF iDamperSelect = 0 THEN
    xDamperForceOpen   := TRUE;
    xDamperForceClose  := FALSE;
    xDamperZapretDobor := FALSE;
ELSIF iDamperSelect = 1 THEN
    xDamperForceOpen   := FALSE;
    xDamperForceClose  := TRUE;
    xDamperZapretDobor := TRUE;
ELSE
    xDamperForceOpen   := FALSE;
    xDamperForceClose  := FALSE;
    xDamperZapretDobor := FALSE;
END_IF;

(* === ДДЮТ:ИЗМЕНЕНО (уточнение после второго разбора) ===          *)
(* У альгицида и биопага, кроме простого ручного пуска (xAlgManualRun*)
(* /xBioManualRun, уже покрыт селектором), есть ОТДЕЛЬНАЯ функция —  *)
(* "ручной пуск ПО ТАЙМЕРУ" (xAlgManualTimeRun/xBioManualTimeRun,     *)
(* кнопки старт/стоп с обратным отсчётом). РАНЬШЕ здесь стояла        *)
(* страховочная принудительная остановка при выходе из "Авто" —      *)
(* УБРАНА: она прямо конфликтует с новым сценарием калибровочной      *)
(* дозы (см. блоки обработки xAlgManualTimeStart/xBioManualTimeStart  *)
(* ниже по файлу) — там подтверждение диалога НАМЕРЕННО переводит     *)
(* iAlgSelect/iBioSelect в "Выкл" (=1) КАК РАЗ для того, чтобы доза    *)
(* работала изолированно от авто-дозации и от постоянного ручного      *)
(* пуска одновременно — эта страховка тут же убила бы только что      *)
(* запущенную дозу. Теперь однажды запущенная (через диалог) доза      *)
(* докручивается до конца безусловно, независимо от смены режима.      *)


(* ============================================================ *)
(* 2б. РЕЖИМ 2/3 ДАТЧИКА — ПИШЕТСЯ С ЭКРАНА НАПРЯМУЮ              *)
(* ============================================================ *)
(* === ДДЮТ:ИЗМЕНЕНО === Раньше здесь была диалоговая PIN-защита  *)
(* (буфер + подтверждение + проверка кода в ST). Убрано по твоей  *)
(* просьбе — GVL_Fountain.iLevelSensorCountPending пишется прямо  *)
(* с экрана (кнопки "2 датчика"/"3 датчика" или поле ввода),      *)
(* защита от случайной/неавторизованной записи — штатными          *)
(* средствами CODESYS (права доступа на элемент визуализации),    *)
(* отдельного кода для этого не нужно.                            *)
(* ВАЖНО: это не отменяет опасность "выбрали 3 датчика, а           *)
(* физически 2" — см. блок 6а (детект аварии добора по попыткам).  *)
(* Это ДРУГАЯ защита, чем была раньше (аварийный потолок) — теперь  *)
(* это чисто СЧЁТЧИК-НАБЛЮДАТЕЛЬ (как в Саки), сам клапан не         *)
(* закрывает. См. предупреждение в конце ответа в чате про этот     *)
(* конкретный сценарий — стоит обсудить отдельно.                   *)
xOnlyTwoLevels := (iLevelSensorCountPending = 2);


(* ============================================================ *)
(* 3. СУХОЙ ХОД (ВЫЧИСЛЯЕТСЯ) + ГЛАВНОЕ РАЗРЕШЕНИЕ               *)
(* ============================================================ *)
(* Сухой ход — НЕ отдельный физический вход, а вычисленное        *)
(* состояние: Уровень1=0 держится дольше гистерезиса              *)
(* tLevel1DebounceSec (по умолч. 20с, с экрана). НЕ защёлка —      *)
(* снимается автоматически, как только Уровень1 снова стал 1 и    *)
(* продержался гистерезис.                                       *)
tonSecTick(IN := NOT tonSecTick.Q, PT := T#1S);   // общий тик 1с для долговой системы

tLevel1Debounce := DINT_TO_TIME(INT_TO_DINT(tLevel1DebounceSec) * 1000);
tonLevel1Debounce(IN := NOT xLevel1, PT := tLevel1Debounce);
xDryRunAlarm := tonLevel1Debounce.Q;

(* DI6 теперь — ОБРАТНАЯ СВЯЗЬ по DO13, а не отдельный сухой ход.  *)
(* DO13 = NOT xDryRunAlarm (см. блок записи выходов). DI6 должен    *)
(* подтверждать ЭТО ЖЕ состояние (факт правильного срабатывания).  *)
(* Расхождение дольше 10с — авария (тот же паттерн, что и у реле    *)
(* обратной связи pH/альгицида/биопага).                           *)
tonDryRunRelayAlarm(IN := (NOT xDryRunAlarm) <> xDryRunRelayFb, PT := T#10S);
IF tonDryRunRelayAlarm.Q THEN
    xDryRunRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xDryRunRelayAlarm := FALSE;
    tonDryRunRelayAlarm(IN := FALSE, PT := T#10S);
END_IF;

xFiltrationBlock := FALSE;   // ДДЮТ: нет аварийных уровней по см, дозация
                             // блокируется через xPermissionToWork (сухой ход)

xPermissionToWork    := xVseSist AND NOT xDryRunAlarm;   // главное разрешение
(* Разрешение для насосов (блок 12) и света (блок 14) считается   *)
(* там же напрямую как xVseSist AND NOT xDryRunAlarm — отдельной   *)
(* переменной не заводим, чтобы не плодить дублирующиеся имена.   *)


(* ============================================================ *)
(* 4. ФИЛЬТРАЦИЯ: работа сейчас + разрешение НФ                *)
(* ============================================================ *)
xNfWork := xFilter1Contactor;    // ДДЮТ: контактор фильтр.насоса (DI5)

xNfPermission := xVseSist AND xNfEnable AND NOT xFiltrationBlock;
xBlokDozacii  := xManualFilter AND xZapretDozacii;


(* ============================================================ *)
(* 4а. СЧЁТЧИК ПРОМЫВОК НФ — двухстадийный алгоритм (новое)      *)
(* ============================================================ *)
(* === ДДЮТ:НОВОЕ === Промывка = ДВЕ последовательные короткие    *)
(* ручные включения НФ подряд, каждое строго дольше 1 минуты и     *)
(* строго короче iFilterMinRunMin (иначе это не промывка, а         *)
(* обычный подтверждённый режим работы — если между "частями"       *)
(* случился полноценный запуск на подтверждённый режим              *)
(* (xNfHealthy), незавершённая "часть 1" аннулируется, счёт          *)
(* начинается заново). Логика — по образцу присланного FB_NFConfirm,*)
(* адаптирована под уже существующий tonNfContinuous (отдельный      *)
(* счётчик секунд заводить не стал — используем ET уже имеющегося    *)
(* таймера, читаем его ЗДЕСЬ, ДО того как блок 5 ниже обновит его    *)
(* новым состоянием xNfWork — иначе длительность уже сброшенного     *)
(* интервала будет потеряна).                                        *)

IF NOT xNfFirstScanDone THEN
    xNfFirstScanDone := TRUE;
    xNfWorkPrev := xNfWork;   (* без ложного фронта на первом скане *)
END_IF;

(* НФ вышел на подтверждённый режим — аннулируем незавершённую       *)
(* "часть 1" и разрешаем следующую попытку промывки заново.          *)
IF xNfHealthy THEN
    iNfFlushStage := 0;
    xNfFlushReady := TRUE;
END_IF;

(* Фронт 0→1 — фиксируем время последнего включения НФ. *)
IF xNfWork AND NOT xNfWorkPrev THEN
    iNfLastOnHour  := iCurrentHour;
    iNfLastOnMin   := iCurrentMinute;
    iNfLastOnDay   := iCurrentDay;
    iNfLastOnMonth := iCurrentMonth;
    iNfLastOnYear  := iCurrentYear;
END_IF;

(* Фронт 1→0 — проверка стадии промывки. *)
IF (NOT xNfWork) AND xNfWorkPrev THEN
    iNfJustEndedSec := DINT_TO_INT(TIME_TO_DINT(tonNfContinuous.ET) / 1000);

    IF xNfFlushReady THEN
        IF (iNfJustEndedSec > 60) AND (iNfJustEndedSec < (iFilterMinRunMin * 60)) THEN
            (* Интервал в диапазоне 1..iFilterMinRunMin мин — кандидат  *)
            (* на часть промывки.                                       *)
            IF iNfFlushStage = 0 THEN
                iNfFlushStage := 1;   (* часть 1 выполнена, ждём часть 2 *)
            ELSE
                (* iNfFlushStage = 1 → это часть 2 — промывка завершена! *)
                iNfFlushCount  := iNfFlushCount + 1;
                iNfFlushHour   := iCurrentHour;
                iNfFlushMin    := iCurrentMinute;
                iNfFlushDay    := iCurrentDay;
                iNfFlushMonth  := iCurrentMonth;
                iNfFlushYear   := iCurrentYear;
                iNfFlushStage  := 0;     (* готовы к следующей промывке с начала *)
                xNfFlushReady  := FALSE; (* блокируем повторный счёт до xNfHealthy *)
            END_IF;
        END_IF;
    END_IF;
END_IF;

xNfWorkPrev := xNfWork;

(* === ДДЮТ:ИСПРАВЛЕНО === Раньше здесь ошибочно стоял сброс          *)
(* счётчика промывок через ОБЩУЮ кнопку сброса аварий (xAlarmReset) — *)
(* это была моя ошибка: сброс аварий (устранение неисправностей)      *)
(* концептуально НЕ должен трогать статистический счётчик обслуживания*)
(* (кол-во промывок — это история/учёт, а не индикатор проблемы).     *)
(* === ДДЮТ:ИЗМЕНЕНО === Раньше сброс делался ЦЕЛИКОМ на кнопке        *)
(* визуализации (без ST-кода). Теперь возвращена настоящая обработка   *)
(* — понадобилась для журнала изменений (см. блок в конце файла):      *)
(* если код не выполняется, событие невозможно залогировать.           *)
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
(* Кнопки на экране: "Сбросить" → xAskResetNfFlush:=TRUE (показать      *)
(* окно); "Подтвердить" → ТОЛЬКО xConfirmResetNfFlush:=TRUE (одно        *)
(* присвоение, остальное делает код выше); "Отмена" →                   *)
(* xAskResetNfFlush:=FALSE.                                              *)
(* Также сбрасывается общей кнопкой "Сбросить ВСЕ параметры"            *)
(* (xConfirmResetAll, блок дальше по файлу).                             *)


(* ============================================================ *)
(* 5. ИСПРАВНОСТЬ НФ — БЕЗ ИЗМЕНЕНИЙ (непрерывная наработка)    *)
(* ============================================================ *)
tonNfContinuous(IN := xNfWork,
    PT := DINT_TO_TIME(INT_TO_DINT(iFilterMinRunMin) * 60000));
xNfHealthy := tonNfContinuous.Q;

iNfContinuousRunHour := DINT_TO_INT(TIME_TO_DINT(tonNfContinuous.ET) / 3600000);
iNfContinuousRunMin  := DINT_TO_INT((TIME_TO_DINT(tonNfContinuous.ET) MOD 3600000) / 60000);
iNfContinuousRunSec  := DINT_TO_INT((TIME_TO_DINT(tonNfContinuous.ET) MOD 60000) / 1000);


(* ============================================================ *)
(* 6. ЗАСЛОНКА ДОБОРА — ГИСТЕРЕЗИС + СИСТЕМА ПОПЫТОК (Саки, доработано)*)
(* ============================================================ *)
(* Логика (единая для обоих режимов, iLevelSensorCountPending=2 или 3): *)
(*  - Уровень1=0 (подтверждено) → СУХОЙ ХОД. Обрабатывается в     *)
(*    блоке 3 (xDryRunAlarm) — блокирует АВТОМАТИКУ ВЕЗДЕ, включая  *)
(*    клапан (см. блок 6б — окончательное решение и обоснование,    *)
(*    почему это осознанный выбор, а не забытая старая логика).     *)
(*  - Уровень2=0 (подтверждено) → СТАРТ добора. Одинаково в обоих  *)
(*    режимах.                                                    *)
(*  - "Хватит" (сигнал на закрытие): в режиме 2 датчиков — снова   *)
(*    Уровень2=1 (подтверждено); в режиме 3 датчиков — Уровень3=1  *)
(*    (подтверждено). ПОСЛЕ подтверждения — ДОПОЛНИТЕЛЬНАЯ         *)
(*    задержка iRefillOffDelayMin/Sec (по умолч. 2 мин), и ТОЛЬКО  *)
(*    потом клапан реально закрывается. Если задержка = 0 —        *)
(*    закрытие происходит сразу (TON с PT=0 не ждёт).              *)
(*                                                                 *)
(*  === ДДЮТ:ИЗМЕНЕНО (уточнение после Саки) === В отличие от      *)
(*  оригинала Саки (где счётчик попыток был чистым наблюдателем    *)
(*  и НЕ управлял клапаном), здесь попытки ТЕПЕРЬ РЕАЛЬНО           *)
(*  управляют клапаном — иначе при ошибке конфигурации (например,  *)
(*  выбран режим "3 датчика", а физически подключено 2 — Уровень3  *)
(*  всегда 0, стоп-сигнал никогда не придёт) клапан остался бы      *)
(*  открыт НАВСЕГДА, что и обсуждали отдельно. Теперь:              *)
(*    - Пытаемся добраться не дольше tRefillDurHours (по умолч.    *)
(*      2ч). Не вышло — клапан ЗАКРЫВАЕТСЯ на паузу                *)
(*      tBetweenRefillHours (по умолч. 12ч), +1 к счётчику неудач. *)
(*    - После паузы — новая попытка (если лимит ещё не исчерпан).  *)
(*    - После iRefillAttemptsMax неудач подряд (по умолч. 5) —      *)
(*      клапан ЗАКРЫВАЕТСЯ ОКОНЧАТЕЛЬНО, авария                    *)
(*      xRefillAttemptsAlarm, до РУЧНОГО сброса оператором.        *)
(*    - Успешный добор (в любой момент, в т.ч. на последней         *)
(*      попытке) — счётчик неудач автоматически обнуляется.        *)
(*  - Форс-кнопки (наладка) — приоритет через OR, даже во время      *)
(*    паузы/аварии попыток (оператор сознательно берёт управление). *)
(*    Ручное открытие НЕ засчитывается как "попытка" — таймер        *)
(*    попытки считает только автоматические открытия.               *)
(* ============================================================ *)

tLevel2Debounce := DINT_TO_TIME(INT_TO_DINT(tLevel2DebounceSec) * 1000);
tLevel3Debounce := DINT_TO_TIME(INT_TO_DINT(tLevel3DebounceSec) * 1000);
tRefillOffDelay := DINT_TO_TIME(INT_TO_DINT(iRefillOffDelayMin) * 60000
                     + INT_TO_DINT(iRefillOffDelaySec) * 1000);
tRefillDur     := DINT_TO_TIME(INT_TO_DINT(tRefillDurHours) * 3600 * 1000);
tBetweenRefill := DINT_TO_TIME(INT_TO_DINT(tBetweenRefillHours) * 3600 * 1000);

tonLevel2Low(IN := NOT xLevel2, PT := tLevel2Debounce);
tonLevel2High(IN := xLevel2, PT := tLevel2Debounce);
xLevel2LowConfirmed  := tonLevel2Low.Q;
xLevel2HighConfirmed := tonLevel2High.Q;

tonLevel3High(IN := xLevel3, PT := tLevel3Debounce);
xLevel3HighConfirmed := tonLevel3High.Q;

xRefillStartConfirmed := xLevel2LowConfirmed;   // одинаково в обоих режимах

IF iLevelSensorCountPending = 3 THEN
    xRefillEnoughConfirmed := xLevel3HighConfirmed;   // отдельный верхний датчик
ELSE
    xRefillEnoughConfirmed := xLevel2HighConfirmed;   // тот же Уровень2, теперь =1
END_IF;

(* Доп. задержка выключения — таймер сбрасывается, если "хватит"   *)
(* пропало до истечения выдержки (вода снова просела) — защита от  *)
(* преждевременного закрытия. *)
tonRefillOffDelay(IN := xRefillEnoughConfirmed, PT := tRefillOffDelay);
xRefillOffConfirmed := tonRefillOffDelay.Q;


(* ============================================================ *)
(* 6а. СЧЁТЧИК ПОПЫТОК — считаем по СОСТОЯНИЮ КЛАПАНА С ПРОШЛОГО  *)
(* ЦИКЛА (xDamperCmdOpen ещё не пересчитан на этот цикл — держит  *)
(* итог предыдущего). Порядок важен: сначала считаем попытки по    *)
(* тому, что БЫЛО, потом (ниже) решаем, каким клапану быть ТЕПЕРЬ. *)
(* ============================================================ *)
(* xRefillTryingAuto = TRUE, если клапан был открыт именно          *)
(* автоматикой (не форс-кнопкой) — ручное открытие в счётчик         *)
(* попыток не идёт, там предполагается, что оператор сам следит.    *)
xRefillTryingAuto := xDamperCmdOpen AND NOT xDamperForceOpen;

(* tonRefillTry просто кормим текущим "пытаемся ли" — стандартное    *)
(* поведение TON само сбрасывает отсчёт в 0, когда IN=FALSE, и        *)
(* начинает считать заново, когда IN снова становится TRUE.          *)
(* Отдельно перезапускать вручную не нужно.                          *)
tonRefillTry(IN := xRefillTryingAuto, PT := tRefillDur);

IF xRefillTryingAuto AND xRefillOffConfirmed THEN
    (* Добрались во время автоматической попытки — УСПЕХ. *)
    iRefillAttempts := 0;
ELSIF xRefillTryingAuto AND tonRefillTry.Q THEN
    (* Время попытки вышло, "хватит" так и не пришло — НЕУДАЧА. *)
    iRefillAttempts := iRefillAttempts + 1;
    xRefillPauseRun := TRUE;
ELSIF NOT xRefillTryingAuto AND xRefillOffConfirmed THEN
    (* "Хватит" пришло, пока клапан и так был закрыт — тоже успех    *)
    (* (например, вода сама поднялась) — сброс на всякий случай.     *)
    iRefillAttempts := 0;
END_IF;

IF xRefillPauseRun THEN
    tonRefillPause(IN := TRUE, PT := tBetweenRefill);
    IF tonRefillPause.Q THEN
        xRefillPauseRun := FALSE;   // пауза кончилась, можно пробовать снова
        tonRefillPause(IN := FALSE, PT := tBetweenRefill);
    END_IF;
ELSE
    tonRefillPause(IN := FALSE, PT := tBetweenRefill);
END_IF;

(* Авария: все попытки израсходованы — клапан закроется ниже       *)
(* окончательно, до ручного сброса.                                *)
xRefillAttemptsAlarm := (iRefillAttempts >= iRefillAttemptsMax);

(* === ДДЮТ:ИСПРАВЛЕНО (тот же принцип, что и у промывок НФ) ===    *)
(* Раньше здесь ошибочно стоял сброс попыток добора ЧЕРЕЗ ОБЩУЮ      *)
(* кнопку сброса аварий (xAlarmReset) — убрано. Сброс аварий должен  *)
(* сбрасывать ТОЛЬКО запомненные состояния аварий; если условие      *)
(* аварии (iRefillAttempts >= iRefillAttemptsMax) всё ещё истинно —  *)
(* xRefillAttemptsAlarm выше и так тут же пересчитается обратно в    *)
(* TRUE на этом же цикле (она вычисляется КАЖДЫЙ цикл заново, не      *)
(* защёлка) — значит авария действительно не пропала, и это           *)
(* правильное поведение.                                              *)
(* === ДДЮТ:ИЗМЕНЕНО === Раньше сброс делался ЦЕЛИКОМ на кнопке        *)
(* визуализации (три присвоения прямо в скрипте кнопки, без ST-кода).  *)
(* Теперь возвращена настоящая обработка — понадобилась для журнала    *)
(* изменений (см. блок в конце файла): если код не выполняется,        *)
(* событие невозможно залогировать.                                    *)
IF xConfirmResetRefill THEN
    iRefillAttempts     := 0;
    xRefillPauseRun     := FALSE;
    xAskResetRefill      := FALSE;
    xConfirmResetRefill := FALSE;
    F_FountainLogWrite("Сброс попыток добора");
END_IF;
(* Кнопки на экране: "Сбросить" → xAskResetRefill:=TRUE (показать       *)
(* окно "Сбросить попытки добора"); "Подтвердить" → ТОЛЬКО               *)
(* xConfirmResetRefill:=TRUE (одно присвоение вместо трёх, остальное    *)
(* делает код выше); "Отмена" → xAskResetRefill:=FALSE.                  *)


(* ============================================================ *)
(* 6б. ИТОГОВАЯ КОМАНДА КЛАПАНА (ЭТОТ цикл)                       *)
(* ============================================================ *)
(* === ДДЮТ:ИЗМЕНЕНО (пересмотрено ещё раз, окончательное решение) ===*)
(* Сухой ход СНОВА блокирует клапан, но это НЕ откат к исходной        *)
(* ошибке ("не может восстановиться после старта с пустой системы") — *)
(* это другой, осознанно принятый сценарий: если клапан УЖЕ был       *)
(* открыт (шла попытка добора по Уровню2), а уровень несмотря на это  *)
(* всё равно упал до сухого хода — воду льём "непонятно куда"          *)
(* (протечка/неисправность), и продолжать автоматически лить          *)
(* бессмысленно и небезопасно. Это АВАРИЙНАЯ ситуация, которая не      *)
(* должна возникать в норме — если возникла, решает оператор вручную   *)
(* (форс-кнопка "Ручной" в iDamperSelect, xDamperForceOpen работает    *)
(* через OR ниже НЕЗАВИСИМО от сухого хода — оператор не заблокирован, *)
(* заблокирована только АВТОМАТИКА). При старте с пустой системы       *)
(* (оба уровня на 0 одновременно, добор ещё не начинался) — по той же  *)
(* причине автоматика тоже не откроет клапан сама; первый залив после  *)
(* полного опустошения система — это тоже требует подтверждения        *)
(* оператора (форс-кнопка), а не слепой автоматики.                    *)
IF xDryRunAlarm THEN
    xDamperCmdOpen := FALSE;
ELSIF xRefillAttemptsAlarm THEN
    (* Все попытки исчерпаны — держим закрытым до ручного сброса.   *)
    xDamperCmdOpen := FALSE;
ELSIF xRefillPauseRun THEN
    (* Идёт пауза между попытками — клапан закрыт, ждём.            *)
    xDamperCmdOpen := FALSE;
ELSIF NOT xVseSist OR xDamperZapretDobor THEN
    xDamperCmdOpen := FALSE;
ELSIF xRefillOffConfirmed THEN
    (* "Хватит" подтверждено и выдержана доп.задержка → закрыть.   *)
    xDamperCmdOpen := FALSE;
ELSIF xRefillStartConfirmed THEN
    xDamperCmdOpen := TRUE;
END_IF;
(* Иначе (между старт и хватит, вне паузы/аварии) — держим          *)
(* предыдущее состояние. *)

(* ПРИНУДИТЕЛЬНОЕ управление заслонкой (наладка). Работает через   *)
(* OR независимо от автоматики (в т.ч. при сухом ходе, паузе и       *)
(* аварии попыток) — оператор сознательно берёт управление на себя.*)
IF xDamperForceOpen THEN
    xDamperCmdOpen := TRUE;
END_IF;
IF xDamperForceClose THEN
    xDamperCmdOpen := FALSE;
END_IF;

(* Статус для экрана *)
IF xDamperCmdOpen THEN
    sDamperPosition := "Добор ВКЛ";
ELSE
    sDamperPosition := "Добор ВЫКЛ";
END_IF;
sDamperFullStatus := sDamperPosition;


(* ============================================================ *)
(* 7. pH — ТОЛЬКО РАЗРЕШЕНИЕ (без изменений в механике)          *)
(* ============================================================ *)
xPhRunCmd := xPermissionToWork
             AND xPhEnable
             AND ( (xNfHealthy AND NOT xBlokDozacii) OR xPhManualRun );

xPhOutput := (xPhRunCmd OR xPhManualRun) AND NOT xFiltrationBlock;

rtrigPhStart(CLK := xPhRunCmd AND NOT xPhManualRun);
IF rtrigPhStart.Q THEN
    iPhStartCount := iPhStartCount + 1;
END_IF;

tonPhRunTick(IN := xPhRelayFb AND NOT xPhManualRun AND NOT tonPhRunTick.Q, PT := T#1S);
IF tonPhRunTick.Q THEN
    iPhRunSecAccum := iPhRunSecAccum + 1;
END_IF;
iPhRunHourTotal := DINT_TO_INT(iPhRunSecAccum / 3600);
iPhRunMinToday  := DINT_TO_INT((iPhRunSecAccum MOD 3600) / 60);
iPhRunSecDisp   := DINT_TO_INT(iPhRunSecAccum MOD 60);

(* === ДДЮТ:ИСПРАВЛЕНО (баг) === Раньше здесь не было ELSE-ветки —  *)
(* счётчик тикал только при xPhManualRun, но при выходе из "Ручного" *)
(* НЕ обнулялся (в отличие от альгицида/биопага, где сброс уже был).*)
(* Теперь ровно тот же паттерн, что и у остальных двух дозаторов.   *)
IF xPhManualRun THEN
    tonPhManualTick(IN := NOT tonPhManualTick.Q, PT := T#1S);
    IF tonPhManualTick.Q THEN
        iPhManualRunSecAccum := iPhManualRunSecAccum + 1;
    END_IF;
    iPhManRunHour := DINT_TO_INT(iPhManualRunSecAccum / 3600);
    iPhManRunMin  := DINT_TO_INT((iPhManualRunSecAccum MOD 3600) / 60);
    iPhManRunSec   := DINT_TO_INT(iPhManualRunSecAccum MOD 60);
ELSE
    tonPhManualTick(IN := FALSE, PT := T#1S);
    iPhManualRunSecAccum := 0;
    iPhManRunHour        := 0;
    iPhManRunMin         := 0;
    iPhManRunSec         := 0;
END_IF;

(* === ДДЮТ:НОВОЕ — авария реле pH: команда есть, DI9 молчит 10с *)
tonPhRelayAlarm(IN := xPhOutput AND NOT xPhRelayFb, PT := T#10S);
IF tonPhRelayAlarm.Q THEN
    xPhRelayAlarm := TRUE;
END_IF;
(* === ДДЮТ:ИСПРАВЛЕНО (баг) === xAlarmReset обнулял только защёлку, *)
(* но НЕ сам таймер — если условие (команда есть, реле молчит) всё   *)
(* ещё истинно в момент сброса, tonPhRelayAlarm.Q оставался TRUE, и  *)
(* на следующем же цикле защёлка снова становилась TRUE — сброс      *)
(* выглядел так, будто не сработал. Теперь обнуляем и таймер тоже —  *)
(* после сброса требуется заново выдержать полные 10с.               *)
IF xAlarmReset THEN
    xPhRelayAlarm := FALSE;
    tonPhRelayAlarm(IN := FALSE, PT := T#10S);
END_IF;


(* ============================================================ *)
(* 8. АЛЬГИЦИД — ДОЛГОВАЯ СИСТЕМА ДОЗАЦИИ (без изменений)        *)
(* ============================================================ *)
IF rAlgFlowMlPerHour > 0.0 THEN
    rAlgDoseSecCalc := rAlgDoseMlPerDay * 3600.0 / rAlgFlowMlPerHour;
ELSE
    rAlgDoseSecCalc := 0.0;
END_IF;
IF rAlgDoseSecCalc > 7200.0 THEN rAlgDoseSecCalc := 7200.0; END_IF;
IF rAlgDoseSecCalc < 0.0 THEN rAlgDoseSecCalc := 0.0; END_IF;

IF NOT xAlgDebtInitDone AND (DWORD_TO_UDINT(dwUtcTime) > 0) THEN
    xAlgDebtInitDone    := TRUE;
    udiAlgLastDebtStamp := DWORD_TO_UDINT(dwUtcTime);
    rAlgDebtSec         := rAlgDoseSecCalc;
    iAlgLastDoseDay     := 0;
    iAlgLastDoseMonth   := 0;
    iAlgLastDoseYear    := 0;
    iAlgLastDoseHourR   := 0;
    iAlgLastDoseMinR    := 0;
    iAlgLastDoseSecR    := 0;
    sAlgLastDebtTime    := F_FormatLogTimestamp();
    sAlgLastDoseTime    := "Дозаций не было";
END_IF;

IF xAlgDebtInitDone AND (DWORD_TO_UDINT(dwUtcTime) > udiAlgLastDebtStamp) THEN
    IF (DWORD_TO_UDINT(dwUtcTime) - udiAlgLastDebtStamp) >= UDINT#86400 THEN
        iAlgDebtDays := UDINT_TO_INT(
            (DWORD_TO_UDINT(dwUtcTime) - udiAlgLastDebtStamp) / UDINT#86400);
        udiAlgLastDebtStamp := udiAlgLastDebtStamp
            + (UDINT#86400 * INT_TO_UDINT(iAlgDebtDays));
        rAlgDebtSec := rAlgDebtSec + rAlgDoseSecCalc * INT_TO_REAL(iAlgDebtDays);
        IF rAlgDebtSec > (rAlgDoseSecCalc * 3.0) THEN
            rAlgDebtSec := rAlgDoseSecCalc * 3.0;
        END_IF;
        sAlgLastDebtTime := F_FormatLogTimestamp();
    END_IF;
END_IF;

IF xAlarmReset THEN
    xAlgAlarm := FALSE;
END_IF;

xAlgDosing := (rAlgDebtSec > 0.0)
    AND xNfHealthy
    AND xAlgEnable
    AND xPermissionToWork
    AND NOT xFiltrationBlock
    AND NOT xBlokDozacii
    AND NOT xAlgAlarm;

xAlgRunCmd := xAlgDosing;

IF xAlgDosing THEN
    tonAlgDebtTick(IN := NOT tonAlgDebtTick.Q, PT := T#1S);
    IF tonAlgDebtTick.Q THEN
        rAlgDebtSec := rAlgDebtSec - 1.0;
        IF rAlgDebtSec <= 0.0 THEN
            rAlgDebtSec := 0.0;
            iAlgStartCount    := iAlgStartCount + 1;
            iAlgLastDoseDay   := iCurrentDay;
            iAlgLastDoseMonth := iCurrentMonth;
            iAlgLastDoseYear  := iCurrentYear;
            iAlgLastDoseHourR := iCurrentHour;
            iAlgLastDoseMinR  := iCurrentMinute;
            iAlgLastDoseSecR  := iCurrentSecond;
            sAlgLastDoseTime  := F_FormatLogTimestamp();
        END_IF;
    END_IF;
ELSE
    tonAlgDebtTick(IN := FALSE, PT := T#1S);
END_IF;

tonAlgRunTick(IN := xAlgRunCmd AND NOT tonAlgRunTick.Q, PT := T#1S);
IF tonAlgRunTick.Q THEN
    iAlgRunSecAccum := iAlgRunSecAccum + 1;
END_IF;
iAlgRunHour := DINT_TO_INT(iAlgRunSecAccum / 3600);
iAlgRunMin  := DINT_TO_INT((iAlgRunSecAccum MOD 3600) / 60);
iAlgRunSec   := DINT_TO_INT(iAlgRunSecAccum MOD 60);

IF xAlgManualRun THEN
    tonAlgManualTick(IN := NOT tonAlgManualTick.Q, PT := T#1S);
    IF tonAlgManualTick.Q THEN
        iAlgManRunSecAccum := iAlgManRunSecAccum + 1;
    END_IF;
    iAlgManRunHour := DINT_TO_INT(iAlgManRunSecAccum / 3600);
    iAlgManRunMin  := DINT_TO_INT((iAlgManRunSecAccum MOD 3600) / 60);
    iAlgManRunSec   := DINT_TO_INT(iAlgManRunSecAccum MOD 60);
ELSE
    tonAlgManualTick(IN := FALSE, PT := T#1S);
    iAlgManRunSecAccum  := 0;
    iAlgManRunHour := 0;
    iAlgManRunMin  := 0;
    iAlgManRunSec   := 0;
END_IF;


(* ============================================================ *)
(* 8б. РУЧНОЙ АЛЬГИЦИД ПО ВРЕМЕНИ — без изменений                *)
(* ============================================================ *)
IF iAlgManSetMin <= 0 THEN
    iAlgManSetMin := 10;
END_IF;

(* === ДДЮТ:ИСПРАВЛЕНО === Таймерный пуск теперь СТАРТУЕТ только в  *)
(* режиме "Авто" (iAlgSelect=2). В "Ручном" запуск бессмысленен —    *)
(* xAlgManualRun и так держит выход постоянно включённым, автостоп   *)
(* по истечении времени таймера физически ни на что не влияет. Кнопка*)
(* "Старт", нажатая не в "Авто", просто гасится без эффекта.        *)
(* === ДДЮТ:ИЗМЕНЕНО (диалог калибровочной дозы) === Раньше старт     *)
(* был разрешён только в "Авто" — неудобно для калибровки (отмерить   *)
(* дозу в стакан): в "Авто" могла параллельно сработать автодозация   *)
(* по долгу и испортить замер. Теперь защита — через ОТДЕЛЬНЫЙ         *)
(* диалог подтверждения на экране (не в этом коде): кнопка "Старт"    *)
(* показывает окно с предупреждением, кнопка "Подтвердить" делает      *)
(* ДВА действия разом — iAlgSelect:=1 (Выкл, изолирует от авто-        *)
(* дозации И от постоянного ручного пуска одновременно) И             *)
(* xAlgManualTimeStart:=TRUE. С этого момента доза должна докрутиться  *)
(* до конца БЕЗУСЛОВНО, несмотря на что угодно — поэтому здесь больше  *)
(* НЕТ проверки текущего режима, и НИГДЕ дальше по файлу нет          *)
(* принудительной остановки по смене iAlgSelect (раньше была,          *)
(* убрана — искала конфликт именно с этим сценарием).                 *)
(* === ДДЮТ:ИСПРАВЛЕНО (найдена коллизия переменной) === Раньше здесь *)
(* по ошибке использовалась iAlgManRunSecAccum — ТА ЖЕ переменная,     *)
(* что и у счётчика наработки ПРОСТОГО ручного пуска (xAlgManualRun,   *)
(* блок выше). Из-за этого: (1) кнопка "Стоп" таймерной дозы обнуляла  *)
(* заодно и наработку простого ручного пуска, хотя это два разных,     *)
(* независимых действия; (2) если запустить ОБА одновременно —         *)
(* счётчик тикал дважды в секунду (инкремент шёл из обоих блоков       *)
(* сразу). У биопага такой коллизии никогда не было — там таймерная    *)
(* доза с самого начала использует только свои переменные остатка      *)
(* времени (iBioManRemMinRaw/SecRaw), не трогая счётчик простого       *)
(* ручного пуска вообще. Убрал все обращения к iAlgManRunSecAccum      *)
(* из этого блока — структура теперь точно как у биопага.              *)
IF xAlgManualTimeStart THEN
    xAlgManualTimeStart  := FALSE;
    xAlgManualTimeRun    := TRUE;
    iAlgManRemMinRaw     := iAlgManSetMin;
    iAlgManRemSecRaw     := 0;
    F_FountainLogWrite(WCONCAT("Запуск калибровочной дозы альгицида: ", WCONCAT(INT_TO_WSTRING(iAlgManSetMin), ", минут")));
END_IF;

IF xAlgManualTimeStop THEN
    xAlgManualTimeStop   := FALSE;
    xAlgManualTimeRun    := FALSE;
    iAlgManRemMinRaw     := iAlgManSetMin;
    iAlgManRemSecRaw     := 0;
END_IF;

IF xAlgManualTimeRun THEN
    tonAlgManualSecTick(IN := NOT tonAlgManualSecTick.Q, PT := T#1S);
    IF tonAlgManualSecTick.Q THEN
        IF iAlgManRemSecRaw > 0 THEN
            iAlgManRemSecRaw := iAlgManRemSecRaw - 1;
        ELSE
            IF iAlgManRemMinRaw > 0 THEN
                iAlgManRemMinRaw := iAlgManRemMinRaw - 1;
                iAlgManRemSecRaw := 59;
            ELSE
                xAlgManualTimeRun := FALSE;
                iAlgManRemMinRaw  := iAlgManSetMin;
                iAlgManRemSecRaw  := 0;
            END_IF;
        END_IF;
    END_IF;
ELSE
    tonAlgManualSecTick(IN := FALSE, PT := T#1S);
END_IF;

IF xAlgManualTimeRun THEN
    iAlgManRemHour    := iAlgManRemMinRaw / 60;
    iAlgManRemMin := iAlgManRemMinRaw MOD 60;
    iAlgManRemSec := iAlgManRemSecRaw;
ELSE
    iAlgManRemHour    := iAlgManSetMin / 60;
    iAlgManRemMin := iAlgManSetMin MOD 60;
    iAlgManRemSec := 0;
END_IF;

(* === ДДЮТ:НОВОЕ — авария реле альгицида: команда есть, DI11 молчит 10с *)
(* (xAlgOutput формируется чуть ниже, в блоке 13 — сравнение     *)
(* делаем там же, сразу после его вычисления.)                  *)


(* ============================================================ *)
(* 9. БИОПАГ — ДОЛГОВАЯ СИСТЕМА ДОЗАЦИИ (без изменений)          *)
(* ============================================================ *)
IF rBioFlowMlPerHour > 0.0 THEN
    rBioDoseSecCalc := rBioDoseMlPerDay * 3600.0 / rBioFlowMlPerHour;
ELSE
    rBioDoseSecCalc := 0.0;
END_IF;
IF rBioDoseSecCalc > 7200.0 THEN rBioDoseSecCalc := 7200.0; END_IF;
IF rBioDoseSecCalc < 0.0    THEN rBioDoseSecCalc := 0.0;    END_IF;

IF NOT xBioDebtInitDone AND (DWORD_TO_UDINT(dwUtcTime) > 0) THEN
    xBioDebtInitDone    := TRUE;
    udiBioLastDebtStamp := DWORD_TO_UDINT(dwUtcTime);
    rBioDebtSec         := rBioDoseSecCalc;
    iBioLastDoseDay     := 0;
    iBioLastDoseMonth   := 0;
    iBioLastDoseYear    := 0;
    iBioLastDoseHourR   := 0;
    iBioLastDoseMinR    := 0;
    iBioLastDoseSecR    := 0;
    sBioLastDebtTime    := F_FormatLogTimestamp();
    sBioLastDoseTime    := "Дозаций не было";
END_IF;

IF xBioDebtInitDone AND (DWORD_TO_UDINT(dwUtcTime) > udiBioLastDebtStamp) THEN
    IF (DWORD_TO_UDINT(dwUtcTime) - udiBioLastDebtStamp) >= UDINT#86400 THEN
        iBioDebtDays := UDINT_TO_INT(
            (DWORD_TO_UDINT(dwUtcTime) - udiBioLastDebtStamp) / UDINT#86400);
        udiBioLastDebtStamp := udiBioLastDebtStamp
            + (UDINT#86400 * INT_TO_UDINT(iBioDebtDays));
        rBioDebtSec := rBioDebtSec + rBioDoseSecCalc * INT_TO_REAL(iBioDebtDays);
        IF rBioDebtSec > (rBioDoseSecCalc * 3.0) THEN
            rBioDebtSec := rBioDoseSecCalc * 3.0;
        END_IF;
        sBioLastDebtTime := F_FormatLogTimestamp();
    END_IF;
END_IF;

IF xAlarmReset THEN xBioAlarm := FALSE; END_IF;

xBioDosing := (rBioDebtSec > 0.0)
    AND xNfHealthy
    AND xBioEnable
    AND xPermissionToWork
    AND NOT xFiltrationBlock
    AND NOT xBlokDozacii
    AND NOT xBioAlarm;

xBioRunCmd := xBioDosing;

IF xBioDosing THEN
    tonBioDebtTick(IN := NOT tonBioDebtTick.Q, PT := T#1S);
    IF tonBioDebtTick.Q THEN
        rBioDebtSec := rBioDebtSec - 1.0;
        IF rBioDebtSec <= 0.0 THEN
            rBioDebtSec := 0.0;
            iBioStartCount    := iBioStartCount + 1;
            iBioLastDoseDay   := iCurrentDay;
            iBioLastDoseMonth := iCurrentMonth;
            iBioLastDoseYear  := iCurrentYear;
            iBioLastDoseHourR := iCurrentHour;
            iBioLastDoseMinR  := iCurrentMinute;
            iBioLastDoseSecR  := iCurrentSecond;
            sBioLastDoseTime  := F_FormatLogTimestamp();
        END_IF;
    END_IF;
ELSE
    tonBioDebtTick(IN := FALSE, PT := T#1S);
END_IF;

tonBioRunTick(IN := xBioRunCmd AND NOT tonBioRunTick.Q, PT := T#1S);
IF tonBioRunTick.Q THEN
    iBioRunSecAccum := iBioRunSecAccum + 1;
END_IF;
iBioRunHour := DINT_TO_INT(iBioRunSecAccum / 3600);
iBioRunMin  := DINT_TO_INT((iBioRunSecAccum MOD 3600) / 60);
iBioRunSec   := DINT_TO_INT(iBioRunSecAccum MOD 60);

IF xBioManualRun THEN
    tonBioManualTick(IN := NOT tonBioManualTick.Q, PT := T#1S);
    IF tonBioManualTick.Q THEN
        iBioManRunSecAccum := iBioManRunSecAccum + 1;
    END_IF;
    iBioManRunHour := DINT_TO_INT(iBioManRunSecAccum / 3600);
    iBioManRunMin  := DINT_TO_INT((iBioManRunSecAccum MOD 3600) / 60);
    iBioManRunSec   := DINT_TO_INT(iBioManRunSecAccum MOD 60);
ELSE
    tonBioManualTick(IN := FALSE, PT := T#1S);
    iBioManRunSecAccum  := 0;
    iBioManRunHour := 0;
    iBioManRunMin  := 0;
    iBioManRunSec   := 0;
END_IF;

IF iBioManSetMin <= 0 THEN iBioManSetMin := 10; END_IF;

(* === ДДЮТ:ИСПРАВЛЕНО === Тот же принцип, что и у альгицида — старт*)
(* только в "Авто" (iBioSelect=2), в "Ручном" бессмысленен.         *)
IF xBioManualTimeStart THEN
    xBioManualTimeStart  := FALSE;
    xBioManualTimeRun    := TRUE;
    iBioManRemMinRaw     := iBioManSetMin;
    iBioManRemSecRaw     := 0;
    F_FountainLogWrite(WCONCAT("Запуск калибровочной дозы биопага: ", WCONCAT(INT_TO_WSTRING(iBioManSetMin), ", минут")));
END_IF;

IF xBioManualTimeStop THEN
    xBioManualTimeStop   := FALSE;
    xBioManualTimeRun    := FALSE;
    iBioManRemMinRaw     := iBioManSetMin;
    iBioManRemSecRaw     := 0;
END_IF;

IF xBioManualTimeRun THEN
    tonBioManualSecTick(IN := NOT tonBioManualSecTick.Q, PT := T#1S);
    IF tonBioManualSecTick.Q THEN
        IF iBioManRemSecRaw > 0 THEN
            iBioManRemSecRaw := iBioManRemSecRaw - 1;
        ELSE
            IF iBioManRemMinRaw > 0 THEN
                iBioManRemMinRaw := iBioManRemMinRaw - 1;
                iBioManRemSecRaw := 59;
            ELSE
                xBioManualTimeRun := FALSE;
                iBioManRemMinRaw  := iBioManSetMin;
                iBioManRemSecRaw  := 0;
            END_IF;
        END_IF;
    END_IF;
ELSE
    tonBioManualSecTick(IN := FALSE, PT := T#1S);
END_IF;

IF xBioManualTimeRun THEN
    iBioManRemHour    := iBioManRemMinRaw / 60;
    iBioManRemMin := iBioManRemMinRaw MOD 60;
    iBioManRemSec := iBioManRemSecRaw;
ELSE
    iBioManRemHour    := iBioManSetMin / 60;
    iBioManRemMin := iBioManSetMin MOD 60;
    iBioManRemSec := 0;
END_IF;

xBioOutput := (xBioRunCmd OR xBioManualTimeRun OR xBioManualRun) AND NOT xFiltrationBlock;
IF xBioDosing THEN sBioDosingStatus := "ДА"; ELSE sBioDosingStatus := "НЕТ"; END_IF;

iBioDebtHour := REAL_TO_INT(rBioDebtSec) / 3600;
iBioDebtMin  := (REAL_TO_INT(rBioDebtSec) MOD 3600) / 60;
iBioDebtSec  := REAL_TO_INT(rBioDebtSec) MOD 60;

IF DWORD_TO_UDINT(dwUtcTime) > udiBioLastDebtStamp THEN
    rBioNextDoseSec := UDINT_TO_REAL(UDINT#86400 - (DWORD_TO_UDINT(dwUtcTime) - udiBioLastDebtStamp));
    IF rBioNextDoseSec < 0.0 THEN rBioNextDoseSec := 0.0; END_IF;
ELSE
    rBioNextDoseSec := 0.0;
END_IF;
iBioNextHour := DINT_TO_INT(REAL_TO_DINT(rBioNextDoseSec) / 3600);
iBioNextMin  := DINT_TO_INT((REAL_TO_DINT(rBioNextDoseSec) MOD 3600) / 60);
iBioNextSec  := DINT_TO_INT(REAL_TO_DINT(rBioNextDoseSec) MOD 60);

iBioDoseHour := DINT_TO_INT(REAL_TO_DINT(rBioDoseSecCalc) / 3600);
iBioDoseMin  := DINT_TO_INT((REAL_TO_DINT(rBioDoseSecCalc) MOD 3600) / 60);
iBioDoseSec  := DINT_TO_INT(REAL_TO_DINT(rBioDoseSecCalc) MOD 60);

rBioFlowLPerHour := rBioFlowMlPerHour / 1000.0;

IF iCurrentDay <> iPrevDay THEN
    iBioStartToday := 0;
END_IF;

(* === ДДЮТ:НОВОЕ — авария реле биопага: команда есть, DI10 молчит 10с *)
tonBioRelayAlarm(IN := xBioOutput AND NOT xBioRelayFb, PT := T#10S);
IF tonBioRelayAlarm.Q THEN
    xBioRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xBioRelayAlarm := FALSE;
    tonBioRelayAlarm(IN := FALSE, PT := T#10S);
END_IF;


(* ============================================================ *)
(* 10. НАРАБОТКА НФ В РУЧНОМ РЕЖИМЕ — без изменений              *)
(* ============================================================ *)
tonNfManualTick(IN := xManualFilter AND NOT tonNfManualTick.Q, PT := T#60S);
IF tonNfManualTick.Q THEN
    iNfManualRunMinBuffer := iNfManualRunMinBuffer + 1;
END_IF;
IF iNfManualRunMinBuffer >= 60 THEN
    iNfManualRunHourTotal := iNfManualRunHourTotal + 1;
    iNfManualRunMinBuffer := iNfManualRunMinBuffer - 60;
    iNfManualRunMinToday  := iNfManualRunMinBuffer;
END_IF;


(* ============================================================ *)
(* 11. РАСЧЁТ ЗАКАТА — NOAA v2 (рефракция + будни/выходные)      *)
(* ============================================================ *)
(* === ДДЮТ:НОВОЕ — автоподбор часового пояса по долготе === *)
(* Срабатывает ОДИН РАЗ на КАЖДОЕ реальное изменение rSunLongitude *)
(* (не каждый цикл!) — если долгота не менялась с прошлого скана,   *)
(* условие ложно, iChoseTimeZone не трогаем, даже если оператор     *)
(* его только что вручную поправил (это и есть требуемое поведение: *)
(* ручная правка запоминается и не затирается повторно, пока        *)
(* долгота снова не изменится).                                     *)
(* === ДДЮТ:ИЗМЕНЕНО === Порог 0.01° вместо точного сравнения <> —  *)
(* защита от дребезга REAL (по твоему образцу из FB_TimeZoneSelect).*)
(* Формула НЕ содержит "+0.5" из твоего образца — там она нужна      *)
(* была ПОД ПРЕДПОЛОЖЕНИЕ, что REAL_TO_UDINT ОТБРАСЫВАЕТ дробную     *)
(* часть (классический трюк "прибавить 0.5 и усечь = округлить").    *)
(* Но в CODESYS REAL_TO_INT/REAL_TO_UDINT УЖЕ округляют сами (это    *)
(* железно доказано в истории с багом заката 20:33→22:00) — если     *)
(* добавить туда ещё и "+0.5" поверх уже работающего округления,     *)
(* получится систематический сдвиг на ЦЕЛУЮ зону восточнее почти на  *)
(* всех долготах (проверено расчётом: не только для Крыма — это не   *)
(* совпадение, а системная ошибка при переносе трюка на платформу,   *)
(* где округление уже встроено). Оставлена простая формула           *)
(* ROUND(долгота/15)+11 без искусственного сдвига.                   *)
(* ВАЖНО: это ГРУБАЯ астрономическая оценка (долгота/15°, округление*)
(* до ближайшего часа), НЕ авторитетная — реальные административные *)
(* часовые пояса (особенно у России) часто НЕ совпадают с чисто      *)
(* географической долготой (пример: Крым 33.5° в.д. географически    *)
(* тянет на +2, а реально там +3 = Москва). Это только стартовая     *)
(* подсказка — оператор всегда может поправить вручную после.        *)
IF (rSunLongitude > rSunLongitudePrev + 0.01) OR (rSunLongitude < rSunLongitudePrev - 0.01) THEN
    rSunLongitudePrev := rSunLongitude;
    iChoseTimeZone := REAL_TO_INT(rSunLongitude / 15.0) + 11;
    IF iChoseTimeZone > 23 THEN
        iChoseTimeZone := 23;
    ELSIF iChoseTimeZone < 0 THEN
        iChoseTimeZone := 0;
    END_IF;
END_IF;

(* === ДДЮТ:НОВОЕ === Часовой пояс — комбобокс (0-23 → -11..+12) *)
fbTimeZone(ChoseTimeZone := INT_TO_UDINT(iChoseTimeZone));
rSunTimeZone := fbTimeZone.TimeZone;

(* === ДДЮТ:ИЗМЕНЕНО (по макету экрана) === Одно знаковое поле     *)
(* iSunsetCorrectSigned ("+00мин"/"-00мин") раскладывается на пару  *)
(* (Sunset_Correct=модуль, Sunset_Earlier=знак), которую реально     *)
(* ждёт FB_SunsetRelay — тем же приёмом, что и 3-позиционные        *)
(* селекторы в блоке 2а.                                            *)
IF iSunsetCorrectSigned < 0 THEN
    xSunsetCorrectEarlier := TRUE;
    iSunsetCorrectMin     := -iSunsetCorrectSigned;
ELSE
    xSunsetCorrectEarlier := FALSE;
    iSunsetCorrectMin     := iSunsetCorrectSigned;
END_IF;

(* === ДДЮТ:ИЗМЕНЕНО === новый интерфейс FB_SunsetRelay:         *)
(* TimeZone теперь REAL (знаковый, из fbTimeZone выше),           *)
(* Off_Hour/Minute разделены на будни/выходные, выход переименован*)
(* Sunset → Sunset_Auto, добавлен IsWeekend (алгоритм Зеллера).   *)
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
(* 11а. РАСПИСАНИЕ СВЕТА/НАСОСОВ — FB_FountainSchedule           *)
(* ============================================================ *)
(* === ДДЮТ:ИЗМЕНЕНО === Теперь 4-позиционный режим СИММЕТРИЧНО   *)
(* для света И насосов (Light_Mode/Pump_Mode: 0=Астро,1=Авто,      *)
(* 2=Вкл,3=Выкл) вместо старого двухпозиционного только у света.  *)
(* Реально управляет DO1/DO9 через xScheduleLightOut/               *)
(* xSchedulePumpOut — но ТОЛЬКО когда внешний селектор узла          *)
(* (iLightSelect/iPumpSelect, экран "Свет/Насосы") стоит в           *)
(* положении "Авто" (=2), см. блоки 12/14 ниже.                      *)
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

(* Флаги видимости элементов на экране "График Фонтана" — просто    *)
(* привязывай "Видимость" элементов к этим переменным напрямую.     *)
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
(* 12. НАСОСЫ ФОНТАНА (шоу) — DO9                                *)
(* ============================================================ *)
(* === ДДЮТ:ПОДКЛЮЧЕНО === расписание fbSchedule.Pump_Out теперь  *)
(* реально управляет выходом (было "только считается", ждало       *)
(* подтверждения). xManualPermissionNasos=TRUE только при           *)
(* iPumpSelect=2 ("Авто") — значит расписание участвует ТОЛЬКО в    *)
(* авто-режиме, как и было задумано.                                *)
xPumpsCmd := xVseSist AND NOT xDryRunAlarm AND xManualPermissionNasos AND xSchedulePumpOut;
IF xPumpsForceOn THEN
    xPumpsCmd := TRUE;   // "Ручной пуск" (iPumpSelect=0) — всегда 1, форс-кнопка перекрывает всё через OR
END_IF;


(* ============================================================ *)
(* 13. ГЕНЕРАТОРЫ МИГАНИЯ — без изменений                        *)
(* ============================================================ *)
tonBlinkFastOff(IN := xBlinkFast, PT := T#20MS);
IF tonBlinkFastOff.Q THEN xBlinkFast := FALSE; END_IF;
IF NOT xBlinkFast AND NOT tonBlinkFastOff.IN THEN xBlinkFast := TRUE; END_IF;

tonBlinkSlowOff(IN := xBlinkSlow, PT := T#100MS);
IF tonBlinkSlowOff.Q THEN xBlinkSlow := FALSE; END_IF;
IF NOT xBlinkSlow AND NOT tonBlinkSlowOff.IN THEN xBlinkSlow := TRUE; END_IF;


(* ============================================================ *)
(* 14. УФ (мониторинг) / СВЕТ (по закату NOAA)                   *)
(* ============================================================ *)
(* УФ: наработка фильтрации (DI5) ≥ iUvNfMinRunMin. Выхода на УФ *)
(* нет — xUvCmd считается только для мониторинга/будущего.       *)
tonUvNfRun(IN := xNfWork, PT := DINT_TO_TIME(INT_TO_DINT(iUvNfMinRunMin) * 60000));
xUvCmd := xPermissionToWork AND xNfWork AND tonUvNfRun.Q AND NOT xFiltrationBlock;

(* СВЕТ DO1: расписание fbSchedule.Light_Out (4-позиционный режим   *)
(* Астро/Авто/Вкл/Выкл внутри fbSchedule через iLightScheduleMode)   *)
(* реально управляет выходом.                                       *)
(* xLightEnable=TRUE только при iLightSelect=2 ("Авто") — значит     *)
(* расписание участвует ТОЛЬКО в авто-режиме. xLightForceOn=TRUE     *)
(* при iLightSelect=0 ("Ручной пуск") — ВСЕГДА перекрывает через OR, *)
(* даже во время сухого хода (осознанно, как и у остальных узлов).  *)
(* iLightSelect=1 ("Выкл") → xLightEnable=FALSE И xLightForceOn=     *)
(* FALSE → xLightCmd=FALSE независимо от остальных условий.          *)
xLightCmd := NOT xDryRunAlarm AND xVseSist AND xLightEnable AND xScheduleLightOut;
IF xLightForceOn THEN
    xLightCmd := TRUE;
END_IF;

xLightFault := FALSE;   (* диагностика несовпадения выключена — новый алгоритм (NOAA) *)


(* ============================================================ *)
(* 15. ОБЩАЯ АВАРИЯ + СТРОКА ПРИЧИН                             *)
(* ============================================================ *)
xAlarmFountain := xDryRunAlarm
              OR xDryRunRelayAlarm
              OR xRefillAttemptsAlarm
              OR xAlgAlarm
              OR xBioAlarm
              OR xPhRelayAlarm
              OR xAlgRelayAlarm
              OR xBioRelayAlarm;

sAlarmCauses := "";
IF xDryRunAlarm         THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Сухой ход, ");          END_IF;
IF xDryRunRelayAlarm    THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Сухой ход реле, ");      END_IF;
IF xRefillAttemptsAlarm THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Добор — исчерпаны попытки, "); END_IF;
IF xAlgAlarm            THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Альгицид (защ.таймер), "); END_IF;
IF xBioAlarm            THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Биопаг (защ.таймер), ");   END_IF;
IF xPhRelayAlarm       THEN sAlarmCauses := WCONCAT(sAlarmCauses, "pH реле, ");             END_IF;
IF xAlgRelayAlarm      THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Альгицид реле, ");        END_IF;
IF xBioRelayAlarm      THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Биопаг реле, ");          END_IF;
IF xPumpCommError[1]   THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь ПЧ1, ");           END_IF;
IF xPumpCommError[2]   THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь ПЧ2, ");           END_IF;
IF xMV110_Error        THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь МВ-Д, ");          END_IF;
IF xMU110_Error        THEN sAlarmCauses := WCONCAT(sAlarmCauses, "Связь МУ, ");            END_IF;
IF sAlarmCauses = ""   THEN sAlarmCauses := "Нет аварий";                                  END_IF;

IF xAlarmReset THEN
    xAlarmReset := FALSE;
END_IF;


(* ============================================================ *)
(* 15б. ОПАСНАЯ СИТУАЦИЯ: СУХОЙ ХОД + РУЧНАЯ ФИЛЬТРАЦИЯ          *)
(* ============================================================ *)
(* Перенесено из «60 лет». Ничего не блокируем — только            *)
(* напоминание. Показ по фронту появления, кнопка "ОК" на          *)
(* диалоге выполняет ОДНУ строку:                                  *)
(*   GVL_Fountain.xConfirmDangerDialog := TRUE;                     *)
(* В ДДЮТ ручной режим фильтрации — экранный xManualFilter          *)
(* (в 60ЛО был физический тумблер DI12 xNfManualSwitch).            *)
xDangerCondition := xDryRunAlarm AND xManualFilter;

IF xDangerCondition AND NOT xDangerCondition_Prev THEN
    xShowDangerDialog := TRUE;
END_IF;
IF xConfirmDangerDialog THEN
    xShowDangerDialog    := FALSE;
    xConfirmDangerDialog := FALSE;
END_IF;
xDangerCondition_Prev := xDangerCondition;


(* ============================================================ *)
(* 16. ИТОГОВЫЙ СИГНАЛ АЛЬГИЦИДА (DO14) + авария реле            *)
(* ============================================================ *)
xAlgOutput := (xAlgRunCmd OR xAlgManualTimeRun OR xAlgManualRun) AND NOT xFiltrationBlock;

IF xAlgDosing THEN sAlgDosingStatus := "ДА"; ELSE sAlgDosingStatus := "НЕТ"; END_IF;

iAlgDebtHour := REAL_TO_INT(rAlgDebtSec) / 3600;
iAlgDebtMin  := (REAL_TO_INT(rAlgDebtSec) MOD 3600) / 60;
iAlgDebtSec  := REAL_TO_INT(rAlgDebtSec) MOD 60;

IF DWORD_TO_UDINT(dwUtcTime) > udiAlgLastDebtStamp THEN
    rAlgNextDoseSec := UDINT_TO_REAL(UDINT#86400 - (DWORD_TO_UDINT(dwUtcTime) - udiAlgLastDebtStamp));
    IF rAlgNextDoseSec < 0.0 THEN rAlgNextDoseSec := 0.0; END_IF;
ELSE
    rAlgNextDoseSec := 0.0;
END_IF;
iAlgNextHour := DINT_TO_INT(REAL_TO_DINT(rAlgNextDoseSec) / 3600);
iAlgNextMin  := DINT_TO_INT((REAL_TO_DINT(rAlgNextDoseSec) MOD 3600) / 60);
iAlgNextSec  := DINT_TO_INT(REAL_TO_DINT(rAlgNextDoseSec) MOD 60);

iAlgDoseHour := DINT_TO_INT(REAL_TO_DINT(rAlgDoseSecCalc) / 3600);
iAlgDoseMin  := DINT_TO_INT((REAL_TO_DINT(rAlgDoseSecCalc) MOD 3600) / 60);
iAlgDoseSec  := DINT_TO_INT(REAL_TO_DINT(rAlgDoseSecCalc) MOD 60);

IF iCurrentDay <> iPrevDay THEN
    iAlgStartToday := 0;
    iPrevDay := iCurrentDay;
END_IF;

(* === ДДЮТ:НОВОЕ — авария реле альгицида (xAlgOutput уже посчитан) *)
tonAlgRelayAlarm(IN := xAlgOutput AND NOT xAlgRelayFb, PT := T#10S);
IF tonAlgRelayAlarm.Q THEN
    xAlgRelayAlarm := TRUE;
END_IF;
IF xAlarmReset THEN
    xAlgRelayAlarm := FALSE;
    tonAlgRelayAlarm(IN := FALSE, PT := T#10S);
END_IF;


(* ============================================================ *)
(* 17. СБРОС СЧЁТЧИКОВ ДОЗАЦИИ — без изменений                   *)
(* ============================================================ *)
IF xConfirmResetPh THEN
    iPhStartCount        := 0;
    iPhRunSecAccum       := 0;
    iPhRunHourTotal      := 0;
    iPhRunMinToday       := 0;
    iPhRunSecDisp        := 0;
    (* === ДДЮТ:УБРАНО (по запросу) === Сброс ручных счётчиков          *)
    (* (iPhManualRunSecAccum, iPhManRunHour/Min/Sec) убран — они и так   *)
    (* сами обнуляются при выходе из ручного режима (см. блок наработки  *)
    (* ручного пуска pH выше), сбрасывать их кнопкой избыточно.          *)
    xConfirmResetPh      := FALSE;
    xAskResetPh          := FALSE;
    F_FountainLogWrite("Сброс счётчика pH");
END_IF;

IF xConfirmResetAlg THEN
    iAlgStartCount       := 0;
    iAlgStartToday       := 0;
    iAlgRunSecAccum      := 0;
    iAlgRunHour          := 0;
    iAlgRunMin           := 0;
    iAlgRunSec           := 0;
    (* === ДДЮТ:УБРАНО (по запросу) === Сброс ручных счётчиков          *)
    (* (iAlgManRunSecAccum, iAlgManRunHour/Min/Sec) убран — сами         *)
    (* обнуляются при выходе из ручного режима.                          *)
    xConfirmResetAlg     := FALSE;
    xAskResetAlg         := FALSE;
    F_FountainLogWrite("Сброс счётчика альгицида");
END_IF;

IF xConfirmResetBio THEN
    iBioStartCount       := 0;
    iBioStartToday       := 0;
    iBioRunSecAccum      := 0;
    iBioRunHour          := 0;
    iBioRunMin           := 0;
    iBioRunSec           := 0;
    (* === ДДЮТ:УБРАНО (по запросу) === Сброс ручных счётчиков          *)
    (* (iBioManRunSecAccum, iBioManRunHour/Min/Sec) убран — сами         *)
    (* обнуляются при выходе из ручного режима.                          *)
    xConfirmResetBio     := FALSE;
    xAskResetBio         := FALSE;
    F_FountainLogWrite("Сброс счётчика биопага");
END_IF;

IF xConfirmResetAll THEN
    (* === ДДЮТ:УБРАНО (по запросу, согласовано с точечными сбросами   *)
    (* pH/альгицид/биопаг выше) === Ручные счётчики (ManRunSecAccum/   *)
    (* Hour/Min/Sec) больше не сбрасываются — сами обнуляются при      *)
    (* выходе из ручного режима.                                        *)
    iPhStartCount        := 0;
    iPhRunSecAccum       := 0;
    iPhRunHourTotal      := 0;
    iPhRunMinToday       := 0;
    iPhRunSecDisp        := 0;
    iAlgStartCount       := 0;
    iAlgStartToday       := 0;
    iAlgRunSecAccum      := 0;
    iAlgRunHour          := 0;
    iAlgRunMin           := 0;
    iAlgRunSec           := 0;
    iBioStartCount       := 0;
    iBioStartToday       := 0;
    iBioRunSecAccum      := 0;
    iBioRunHour          := 0;
    iBioRunMin           := 0;
    iBioRunSec           := 0;
    (* === ДДЮТ:НОВОЕ === промывки НФ — тоже часть "сбросить всё",     *)
    (* по твоей просьбе. История последней промывки чистится тоже —   *)
    (* раз это "сброс ВСЕХ параметров", а не точечный сброс счётчика. *)
    iNfFlushCount        := 0;
    iNfFlushStage        := 0;
    xNfFlushReady        := TRUE;
    iNfFlushHour         := 0;
    iNfFlushMin          := 0;
    iNfFlushDay          := 0;
    iNfFlushMonth        := 0;
    iNfFlushYear         := 0;
    xConfirmResetAll     := FALSE;
    xAskResetAll         := FALSE;
    F_FountainLogWrite("Сброс всех параметров дозации");
END_IF;


(* ============================================================ *)
(* 17а. ЖУРНАЛ ИЗМЕНЕНИЙ ПАРАМЕТРОВ ФОНТАНА                      *)
(* ============================================================ *)
(* === ДДЮТ:НОВОЕ === Второй журнал, по аналогии с GVL.sParamLog  *)
(* (журнал ПЧ) — отслеживает изменения параметров дозации/         *)
(* разрешений/уставок с экранов ДДЮТ. Схема: у каждого параметра   *)
(* есть "тень" (iLogPrevXxx) — запомненное предыдущее значение;    *)
(* если текущее значение отличается — пишем строку в журнал и       *)
(* обновляем "тень". F_FountainLogWrite сама нумерует строки,       *)
(* ставит время/дату и делает самоочистку при разрастании.          *)

(* === ДДЮТ:ИЗМЕНЕНО (round 3) === Свой экран пароля (не встроенный    *)
(* виджет), без промежуточного диалога "Вы уверены?" — кнопка          *)
(* "Очистить журнал" сразу показывает экран ввода пароля напрямую:     *)
(*   Кнопка "Очистить журнал" → xAskClearFountainLog := TRUE;           *)
(*   (эта же переменная = видимость экрана пароля, второй переменной   *)
(*   для этого больше нет — раньше была xShowFountainLogPassword,       *)
(*   убрана как избыточная).                                            *)
(*   На экране пароля: поле ввода → iFountainLogPinEntry; кнопка        *)
(*   "Войти"/"Подтвердить" → xFountainLogPinSubmit := TRUE;             *)
(*   кнопка "Отмена" → xAskClearFountainLog := FALSE;                   *)
(* Верно → очищаем журнал, закрываем экран пароля, на 3с показываем     *)
(* "Журнал сброшен". Неверно → НИЧЕГО не закрываем (экран пароля        *)
(* остаётся, можно вводить заново), на 3с показываем "Пароль не         *)
(* подошёл".                                                             *)
(* === ДДЮТ:ИСПРАВЛЕНО (баг с таймером) === Раньше tonFountainLogXxxMsg  *)
(* вызывался ОДИН РАЗ внутри одноразового блока IF xFountainLogPinSubmit*)
(* THEN — который сам гасит себя в этом же цикле. TON в CODESYS считает *)
(* время ТОЛЬКО пока его вызывают КАЖДЫЙ цикл — вызванный один раз и    *)
(* забытый таймер просто замирает, .Q никогда не станет TRUE сам.       *)
(* ПРАВИЛЬНЫЙ паттерн: кормить таймер САМИМ ФЛАГОМ сообщения БЕЗУСЛОВНО *)
(* каждый цикл (вне одноразовых блоков) — ниже.                         *)
IF xFountainLogPinSubmit THEN
    xFountainLogPinSubmit := FALSE;
    IF iFountainLogPinEntry = iAdminPassCorrect THEN
        xFountainLogClear      := TRUE;
        xAskClearFountainLog   := FALSE;
        xFountainLogClearedMsg := TRUE;
    ELSE
        xFountainLogPassBadMsg := TRUE;
    END_IF;
    iFountainLogPinEntry := 0;   (* не хранить введённый пароль на экране *)
END_IF;

(* Таймеры сообщений — вызываются КАЖДЫЙ цикл, IN = сам флаг сообщения. *)
(* Пока флаг TRUE — таймер копит время; как только накопит 3с — сам     *)
(* сбрасывает флаг в FALSE, что на СЛЕДУЮЩЕМ же цикле подаст на таймер  *)
(* IN=FALSE и корректно обнулит его ET, готовя к следующему разу.       *)
tonFountainLogClearedMsg(IN := xFountainLogClearedMsg, PT := T#3S);
IF tonFountainLogClearedMsg.Q THEN
    xFountainLogClearedMsg := FALSE;
END_IF;

tonFountainLogPassBadMsg(IN := xFountainLogPassBadMsg, PT := T#3S);
IF tonFountainLogPassBadMsg.Q THEN
    xFountainLogPassBadMsg := FALSE;
END_IF;

(* Сама очистка — срабатывает ТОЛЬКО из блока проверки пароля выше,    *)
(* больше никто в это не пишет.                                         *)
IF xFountainLogClear THEN
    FOR iClearIdx := 1 TO 60 DO
        aFountainLog[iClearIdx] := "";
    END_FOR;
    iFountainLogCount    := 0;
    xFountainLogClear     := FALSE;
    xAskClearFountainLog  := FALSE;   (* на всякий случай, если экран ещё открыт *)
END_IF;

(* === ДДЮТ:ИЗМЕНЕНО (round 3) === Тот же самый механизм — ЖУРНАЛ ПЧ    *)
(* (GVL.sParamLog, GVL.xLogClear). Это твой скриншот, теперь БЕЗ         *)
(* промежуточного диалога — GVL.xAskClearLog сразу = видимость экрана   *)
(* пароля (xShowPumpLogPassword убрана как избыточная, аналогично        *)
(* фонтанному журналу выше). Проверка того же общего пароля              *)
(* iAdminPassCorrect. Тот же исправленный паттерн таймера.               *)
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
IF tonPumpLogClearedMsg.Q THEN
    xPumpLogClearedMsg := FALSE;
END_IF;

tonPumpLogPassBadMsg(IN := xPumpLogPassBadMsg, PT := T#3S);
IF tonPumpLogPassBadMsg.Q THEN
    xPumpLogPassBadMsg := FALSE;
END_IF;
(* Саму очистку (GVL.xLogClear → "") делает существующий код в           *)
(* PRG_Pumps.st (блок 8) — не дублируем здесь.                           *)


(* Первый скан после заливки/рестарта — просто снимаем снимок         *)
(* текущих значений БЕЗ сравнения (иначе "изменилось с 0 на дефолт"   *)
(* залогировалось бы как ложное первое изменение).                    *)
IF NOT xFountainLogInitialized THEN
    iLogPrevFilterMinRunMin  := iFilterMinRunMin;
    iLogPrevUvNfMinRunMin    := iUvNfMinRunMin;
    rLogPrevAlgDoseMlPerDay  := rAlgDoseMlPerDay;
    rLogPrevAlgFlowMlPerHour := rAlgFlowMlPerHour;
    rLogPrevBioDoseMlPerDay  := rBioDoseMlPerDay;
    rLogPrevBioFlowMlPerHour := rBioFlowMlPerHour;
    iLogPrevAlgManSetMin     := iAlgManSetMin;
    iLogPrevBioManSetMin     := iBioManSetMin;
    iLogPrevPhSelect         := iPhSelect;
    iLogPrevAlgSelect        := iAlgSelect;
    iLogPrevBioSelect        := iBioSelect;
    xLogPrevVseSist          := xVseSist;
    (* === ДДЮТ:НОВОЕ (расширение списка) === *)
    iLogPrevDamperSelect        := iDamperSelect;
    iLogPrevLightSelect         := iLightSelect;
    iLogPrevPumpSelect          := iPumpSelect;
    iLogPrevLevelSensorCount    := iLevelSensorCountPending;
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
    xLogPrevAlarmReset           := xAlarmReset;
    (* === ДДЮТ:НОВОЕ (второе расширение) === *)
    iLogPrevLevel1DebounceSec  := tLevel1DebounceSec;
    iLogPrevLevel2DebounceSec  := tLevel2DebounceSec;
    iLogPrevLevel3DebounceSec  := tLevel3DebounceSec;
    iLogPrevRefillOffDelayMin  := iRefillOffDelayMin;
    iLogPrevRefillOffDelaySec  := iRefillOffDelaySec;
    iLogPrevRefillDurHours     := tRefillDurHours;
    iLogPrevBetweenRefillHours := tBetweenRefillHours;
    iLogPrevRefillAttemptsMax  := iRefillAttemptsMax;
    xFountainLogInitialized  := TRUE;
END_IF;

IF iFilterMinRunMin <> iLogPrevFilterMinRunMin THEN
    F_FountainLogWrite(WCONCAT("Порог подтв.режима НФ: ", WCONCAT(INT_TO_WSTRING(iLogPrevFilterMinRunMin), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iFilterMinRunMin), ", мин")))));
    iLogPrevFilterMinRunMin := iFilterMinRunMin;
END_IF;

IF iUvNfMinRunMin <> iLogPrevUvNfMinRunMin THEN
    F_FountainLogWrite(WCONCAT("Порог НФ для УФ: ", WCONCAT(INT_TO_WSTRING(iLogPrevUvNfMinRunMin), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iUvNfMinRunMin), ", мин")))));
    iLogPrevUvNfMinRunMin := iUvNfMinRunMin;
END_IF;

IF rAlgDoseMlPerDay <> rLogPrevAlgDoseMlPerDay THEN
    F_FountainLogWrite(WCONCAT("Доза альгицида в сутки: ", WCONCAT(REAL_TO_WSTRING(rLogPrevAlgDoseMlPerDay), WCONCAT(" → ", WCONCAT(REAL_TO_WSTRING(rAlgDoseMlPerDay), ", мл/сут")))));
    rLogPrevAlgDoseMlPerDay := rAlgDoseMlPerDay;
END_IF;

IF rAlgFlowMlPerHour <> rLogPrevAlgFlowMlPerHour THEN
    F_FountainLogWrite(WCONCAT("Расход насоса альгицида: ", WCONCAT(REAL_TO_WSTRING(rLogPrevAlgFlowMlPerHour), WCONCAT(" → ", WCONCAT(REAL_TO_WSTRING(rAlgFlowMlPerHour), ", мл/ч")))));
    rLogPrevAlgFlowMlPerHour := rAlgFlowMlPerHour;
END_IF;

IF rBioDoseMlPerDay <> rLogPrevBioDoseMlPerDay THEN
    F_FountainLogWrite(WCONCAT("Доза биопага в сутки: ", WCONCAT(REAL_TO_WSTRING(rLogPrevBioDoseMlPerDay), WCONCAT(" → ", WCONCAT(REAL_TO_WSTRING(rBioDoseMlPerDay), ", мл/сут")))));
    rLogPrevBioDoseMlPerDay := rBioDoseMlPerDay;
END_IF;

IF rBioFlowMlPerHour <> rLogPrevBioFlowMlPerHour THEN
    F_FountainLogWrite(WCONCAT("Расход насоса биопага: ", WCONCAT(REAL_TO_WSTRING(rLogPrevBioFlowMlPerHour), WCONCAT(" → ", WCONCAT(REAL_TO_WSTRING(rBioFlowMlPerHour), ", мл/ч")))));
    rLogPrevBioFlowMlPerHour := rBioFlowMlPerHour;
END_IF;

IF iAlgManSetMin <> iLogPrevAlgManSetMin THEN
    F_FountainLogWrite(WCONCAT("Таймер дозы альгицида: ", WCONCAT(INT_TO_WSTRING(iLogPrevAlgManSetMin), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iAlgManSetMin), ", мин")))));
    iLogPrevAlgManSetMin := iAlgManSetMin;
END_IF;

IF iBioManSetMin <> iLogPrevBioManSetMin THEN
    F_FountainLogWrite(WCONCAT("Таймер дозы биопага: ", WCONCAT(INT_TO_WSTRING(iLogPrevBioManSetMin), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iBioManSetMin), ", мин")))));
    iLogPrevBioManSetMin := iBioManSetMin;
END_IF;

IF iPhSelect <> iLogPrevPhSelect THEN
    F_FountainLogWrite(WCONCAT("Режим pH: ", WCONCAT(F_SelectModeText(iLogPrevPhSelect), WCONCAT(" → ", F_SelectModeText(iPhSelect)))));
    iLogPrevPhSelect := iPhSelect;
END_IF;

IF iAlgSelect <> iLogPrevAlgSelect THEN
    F_FountainLogWrite(WCONCAT("Режим альгицида: ", WCONCAT(F_SelectModeText(iLogPrevAlgSelect), WCONCAT(" → ", F_SelectModeText(iAlgSelect)))));
    iLogPrevAlgSelect := iAlgSelect;
END_IF;

IF iBioSelect <> iLogPrevBioSelect THEN
    F_FountainLogWrite(WCONCAT("Режим биопага: ", WCONCAT(F_SelectModeText(iLogPrevBioSelect), WCONCAT(" → ", F_SelectModeText(iBioSelect)))));
    iLogPrevBioSelect := iBioSelect;
END_IF;

IF xVseSist <> xLogPrevVseSist THEN
    F_FountainLogWrite(WCONCAT("Общее разрешение: ", WCONCAT(SEL(xLogPrevVseSist, "Запрещено", "Разрешено"), WCONCAT(" → ", SEL(xVseSist, "Запрещено", "Разрешено")))));
    xLogPrevVseSist := xVseSist;
END_IF;

(* === ДДЮТ:НОВОЕ (расширение списка) — ещё три тройных селектора === *)
IF iDamperSelect <> iLogPrevDamperSelect THEN
    F_FountainLogWrite(WCONCAT("Режим заслонки: ", WCONCAT(F_SelectModeText(iLogPrevDamperSelect), WCONCAT(" → ", F_SelectModeText(iDamperSelect)))));
    iLogPrevDamperSelect := iDamperSelect;
END_IF;

IF iLightSelect <> iLogPrevLightSelect THEN
    F_FountainLogWrite(WCONCAT("Режим света: ", WCONCAT(F_SelectModeText(iLogPrevLightSelect), WCONCAT(" → ", F_SelectModeText(iLightSelect)))));
    iLogPrevLightSelect := iLightSelect;
END_IF;

IF iPumpSelect <> iLogPrevPumpSelect THEN
    F_FountainLogWrite(WCONCAT("Режим насосов: ", WCONCAT(F_SelectModeText(iLogPrevPumpSelect), WCONCAT(" → ", F_SelectModeText(iPumpSelect)))));
    iLogPrevPumpSelect := iPumpSelect;
END_IF;

(* --- Кол-во датчиков уровня --- *)
IF iLevelSensorCountPending <> iLogPrevLevelSensorCount THEN
    F_FountainLogWrite(WCONCAT("Кол-во датчиков уровня: ", WCONCAT(INT_TO_WSTRING(iLogPrevLevelSensorCount), WCONCAT(" → ", INT_TO_WSTRING(iLevelSensorCountPending)))));
    iLogPrevLevelSensorCount := iLevelSensorCountPending;
END_IF;

(* --- Режимы расписания (СВОИ, разные кодировки — см. функции) --- *)
IF iLightScheduleMode <> iLogPrevLightScheduleMode THEN
    F_FountainLogWrite(WCONCAT("Расписание света: ", WCONCAT(F_LightScheduleModeText(iLogPrevLightScheduleMode), WCONCAT(" → ", F_LightScheduleModeText(iLightScheduleMode)))));
    iLogPrevLightScheduleMode := iLightScheduleMode;
END_IF;

IF iPumpScheduleMode <> iLogPrevPumpScheduleMode THEN
    F_FountainLogWrite(WCONCAT("Расписание насосов: ", WCONCAT(F_PumpScheduleModeText(iLogPrevPumpScheduleMode), WCONCAT(" → ", F_PumpScheduleModeText(iPumpScheduleMode)))));
    iLogPrevPumpScheduleMode := iPumpScheduleMode;
END_IF;

(* --- Времена расписания "Авто" (будни/выходные) — свет, насосы,     *)
(* общее выключение. Каждое поле — отдельная запись (час и минута     *)
(* порознь), для точной сверки по переменным. Единицу не дублируем —  *)
(* она уже есть в самом названии ("час"/"мин").                        *)
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

(* --- Астрореле: коррекция, часовой пояс, широта, долгота --- *)
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

(* --- Сброс ВСЕХ аварий (xAlarmReset) — фиксируем каждое нажатие как  *)
(* действие (не значение), детект по фронту FALSE→TRUE. *)
IF xAlarmReset AND NOT xLogPrevAlarmReset THEN
    F_FountainLogWrite("Сброс всех аварий");
END_IF;
xLogPrevAlarmReset := xAlarmReset;

(* === ДДЮТ:НОВОЕ (второе расширение) — гистерезисы уровня, задержка  *)
(* выключения добора, уставки попыток добора. *)
IF tLevel1DebounceSec <> iLogPrevLevel1DebounceSec THEN
    F_FountainLogWrite(WCONCAT("Гистерезис Уровень1: ", WCONCAT(INT_TO_WSTRING(iLogPrevLevel1DebounceSec), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(tLevel1DebounceSec), ", с")))));
    iLogPrevLevel1DebounceSec := tLevel1DebounceSec;
END_IF;

IF tLevel2DebounceSec <> iLogPrevLevel2DebounceSec THEN
    F_FountainLogWrite(WCONCAT("Гистерезис Уровень2: ", WCONCAT(INT_TO_WSTRING(iLogPrevLevel2DebounceSec), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(tLevel2DebounceSec), ", с")))));
    iLogPrevLevel2DebounceSec := tLevel2DebounceSec;
END_IF;

IF tLevel3DebounceSec <> iLogPrevLevel3DebounceSec THEN
    F_FountainLogWrite(WCONCAT("Гистерезис Уровень3: ", WCONCAT(INT_TO_WSTRING(iLogPrevLevel3DebounceSec), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(tLevel3DebounceSec), ", с")))));
    iLogPrevLevel3DebounceSec := tLevel3DebounceSec;
END_IF;

IF iRefillOffDelayMin <> iLogPrevRefillOffDelayMin THEN
    F_FountainLogWrite(WCONCAT("Задержка выкл. добора: ", WCONCAT(INT_TO_WSTRING(iLogPrevRefillOffDelayMin), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iRefillOffDelayMin), ", мин")))));
    iLogPrevRefillOffDelayMin := iRefillOffDelayMin;
END_IF;

IF iRefillOffDelaySec <> iLogPrevRefillOffDelaySec THEN
    F_FountainLogWrite(WCONCAT("Задержка выкл. добора: ", WCONCAT(INT_TO_WSTRING(iLogPrevRefillOffDelaySec), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(iRefillOffDelaySec), ", сек")))));
    iLogPrevRefillOffDelaySec := iRefillOffDelaySec;
END_IF;

IF tRefillDurHours <> iLogPrevRefillDurHours THEN
    F_FountainLogWrite(WCONCAT("Время на попытку добора: ", WCONCAT(INT_TO_WSTRING(iLogPrevRefillDurHours), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(tRefillDurHours), ", ч")))));
    iLogPrevRefillDurHours := tRefillDurHours;
END_IF;

IF tBetweenRefillHours <> iLogPrevBetweenRefillHours THEN
    F_FountainLogWrite(WCONCAT("Пауза между попытками: ", WCONCAT(INT_TO_WSTRING(iLogPrevBetweenRefillHours), WCONCAT(" → ", WCONCAT(INT_TO_WSTRING(tBetweenRefillHours), ", ч")))));
    iLogPrevBetweenRefillHours := tBetweenRefillHours;
END_IF;

IF iRefillAttemptsMax <> iLogPrevRefillAttemptsMax THEN
    F_FountainLogWrite(WCONCAT("Макс. число попыток добора: ", WCONCAT(INT_TO_WSTRING(iLogPrevRefillAttemptsMax), WCONCAT(" → ", INT_TO_WSTRING(iRefillAttemptsMax)))));
    iLogPrevRefillAttemptsMax := iRefillAttemptsMax;
END_IF;


(* ============================================================ *)
(* 18. СТРОКОВЫЕ СТАТУСЫ                                        *)
(* ============================================================ *)
(* Статусы теперь показывают сам выбранный режим (Ручной/Выкл/    *)
(* Авто), а не только производную Enable — так понятнее на едином *)
(* экране с одним селектором на узел (см. блок 2а).               *)
IF xVseSist               THEN sVseSistStatus    := "Разрешен"; ELSE sVseSistStatus    := "Запрещен"; END_IF;
IF xNfEnable              THEN sNfEnableStatus   := "Разрешен"; ELSE sNfEnableStatus   := "Запрещен"; END_IF;

CASE iPumpSelect OF
    0: sPermissionStatus := "Ручной пуск";
    2: sPermissionStatus := "Авто";
ELSE
    sPermissionStatus := "Выкл";
END_CASE;

CASE iPhSelect OF
    0: sPhStatus := "Ручной пуск";
    2: sPhStatus := "Авто";
ELSE
    sPhStatus := "Выкл";
END_CASE;

CASE iAlgSelect OF
    0: sAlgStatus := "Ручной пуск";
    2: sAlgStatus := "Авто";
ELSE
    sAlgStatus := "Выкл";
END_CASE;

CASE iBioSelect OF
    0: sBioStatus := "Ручной пуск";
    2: sBioStatus := "Авто";
ELSE
    sBioStatus := "Выкл";
END_CASE;

CASE iLightSelect OF
    0: sLightStatus := "Ручной пуск";
    2: sLightStatus := "Авто (закат)";
ELSE
    sLightStatus := "Выкл";
END_CASE;

CASE iSoundMode OF
    0: sSoundStatus := "Выкл_вручную";
    1: sSoundStatus := "Вкл_вручную";
    2: sSoundStatus := "По расписанию";
END_CASE;

IF xAlarmFountain      THEN sAlarmStopStatus := "Да";           ELSE sAlarmStopStatus := "Нет";      END_IF;
(* === ДДЮТ:ИСПРАВЛЕНО (баг) === было ошибочно привязано к          *)
(* xDryRunAlarm (дублировало то, что и так видно по лампе сухого     *)
(* хода) — теперь корректно отражает то, что и должно по названию:   *)
(* аварию ПОПЫТОК ДОБОРА (xRefillAttemptsAlarm).                     *)
IF xRefillAttemptsAlarm THEN sRefillStatus := "Авария добора"; ELSE sRefillStatus := "Исправен"; END_IF;
IF xNfWork             THEN sNfStatus        := "Работает";     ELSE sNfStatus        := "Стоп";     END_IF;
IF xNfHealthy THEN
    sNfHealthyStatus := "Исправен";
ELSE
    sNfHealthyStatus := "Нет наработки НФ";
END_IF;

rAlgFlowLPerHour := rAlgFlowMlPerHour / 1000.0;


(* ============================================================ *)
(* 19. ЗАПИСЬ ВЫХОДОВ DO — КАРТА ДДЮТ                            *)
(* ============================================================ *)
(* Про сухой ход: АВТОМАТИКА уже заблокирована через             *)
(* xPermissionToWork/условия выше (NOT xDryRunAlarm встроено в    *)
(* формулы xPumpsCmd/xLightCmd/xAlgDosing/xBioDosing/xPhRunCmd/    *)
(* xDamperCmdOpen). РУЧНОЕ управление (форс-кнопки, xAlgManualRun  *)
(* и т.п.) работает НЕЗАВИСИМО через OR и сухим ходом НЕ           *)
(* перекрывается — оператор может вручную включить нужный узел    *)
(* даже во время сухого хода, если это осознанное решение.        *)
xDO[1]  := xLightCmd;                        // DO1  СВЕТ
(* === ИЗМЕНЕНО === Лампа аварии больше НЕ мигает — горит ровно     *)
(* при наличии аварии. Мигание (AND xBlinkFast) закомментировано:   *)
(* частое переключение выхода ломало лампу/реле. Вернуть мигание —  *)
(* раскомментировать нижнюю строку и убрать верхнюю.                 *)
xDO[2]  := xAlarmFountain;                   // DO2  ЛАМПА АВАРИИ (горит ровно)
// xDO[2]  := xAlarmFountain AND xBlinkFast;    // DO2  ЛАМПА АВАРИИ (мигала — отключено)
xDO[3]  := FALSE;                            // DO3  свободен
xDO[4]  := FALSE;                            // DO4  свободен
xDO[5]  := FALSE;                            // DO5  свободен
xDO[6]  := FALSE;                            // DO6  свободен
xDO[7]  := FALSE;                            // DO7  свободен
xDO[8]  := FALSE;                            // DO8  свободен
xDO[9]  := xPumpsCmd;                         // DO9  НАСОСЫ ФОНТАНА
xDO[10] := FALSE;                            // DO10 свободен
xDO[11] := xDamperCmdOpen;                    // DO11 КЛАПАН ДОБОРА (1=открыть)
xDO[12] := FALSE;                            // DO12 свободен (УФ — только мониторинг)
(* DO13: 1=норма/разрешение, 0=сухой ход (подтверждено по Уровню1).*)
xDO[13] := NOT xDryRunAlarm;                  // DO13 сухой ход/разрешение
xDO[14] := xAlgOutput;                        // DO14 АЛЬГИЦИД
xDO[15] := xBioOutput;                        // DO15 БИОПАГ / ОБЕЗЗАРАЖИВАТЕЛЬ
xDO[16] := xPhOutput;                         // DO16 pH
