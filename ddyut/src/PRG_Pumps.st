PROGRAM PRG_Pumps
(* ============================================================ *)
(* === ДДЮТ: БЕЗ ИЗМЕНЕНИЙ относительно Саки Пруд ===            *)
(* ПЧ на COM2 (адреса 41/42) теперь качают фонтан (клапаны/       *)
(* форсунки), а не фильтрацию — но вся механика отладки RS-485,   *)
(* чтения/записи параметров, журнала и разовой инициализации      *)
(* работает одинаково независимо от того, что именно крутит ПЧ.   *)
(* ============================================================ *)
VAR
    i                       : INT;
    xDebugForPump           : BOOL;
    wActualFaultReg         : WORD;
    iDebugPumpSelected_Prev : INT := 1;
    iPrevDebugMode          : INT := -1;
    tonApplyHold   : ARRAY[1..cPumpCount] OF TON;
    tonFactoryHold : ARRAY[1..cPumpCount] OF TON;
    tApplyHold     : TIME := T#5S;
    tonHoldRead     : ARRAY[1..cPumpCount] OF TON;
    tonHold_AccTime : ARRAY[1..cPumpCount] OF TON;
    tonHold_DecTime : ARRAY[1..cPumpCount] OF TON;
    tonHold_MaxFreq : ARRAY[1..cPumpCount] OF TON;
    tonHold_MinFreq : ARRAY[1..cPumpCount] OF TON;
    tonHold_MotorCur : ARRAY[1..cPumpCount] OF TON;
    tonHold_MotorVolt : ARRAY[1..cPumpCount] OF TON;
    tonHold_OCLevel : ARRAY[1..cPumpCount] OF TON;
    tonHold_OCTime  : ARRAY[1..cPumpCount] OF TON;
    tonHold_OVProt  : ARRAY[1..cPumpCount] OF TON;
    tonHold_Overheat : ARRAY[1..cPumpCount] OF TON;
    tonHold_OCAcc   : ARRAY[1..cPumpCount] OF TON;
    tonHold_F800    : ARRAY[1..cPumpCount] OF TON;
    tonHold_ParamLock : ARRAY[1..cPumpCount] OF TON;   // удержание снятия замка F1.18
    tonHold_Sources : ARRAY[1..cPumpCount] OF TON;
    tonHold_DispParam : ARRAY[1..cPumpCount] OF TON;
    tonHold_ErrDelay  : ARRAY[1..cPumpCount] OF TON;
    tonInitDelay      : TON;
    xInitDone         : BOOL := FALSE;
    tonStopWait     : ARRAY[1..cPumpCount] OF TON;
    tonStopWaitAll  : ARRAY[1..cPumpCount] OF TON;
    tStopWaitMax    : TIME := T#30S;
    rMaxDecTime     : REAL;
    tWriteHoldDyn   : TIME;
    xNeedStopWrite  : ARRAY[1..cPumpCount] OF BOOL;
    xNoStopWrite    : ARRAY[1..cPumpCount] OF BOOL;
END_VAR
(* ========================================================= *)
(* БЛОК 0а: СИНХРОНИЗАЦИЯ ФЛАГОВ ПРИ СМЕНЕ РЕЖИМА ОТЛАДКИ    *)
(* ========================================================= *)
IF iDebugMode <> iPrevDebugMode THEN
    FOR i := 1 TO cPumpCount DO
        xDebugModePump[i] := FALSE;
    END_FOR;
    xDebugModeAll := FALSE;

    CASE iDebugMode OF
        0: ;
        1: xDebugModePump[iDebugPumpSelected] := TRUE;
        2:
            FOR i := 1 TO cPumpCount DO
                xDebugModePump[i] := TRUE;
            END_FOR;
            xDebugModeAll := TRUE;
    END_CASE;
    iPrevDebugMode := iDebugMode;
END_IF;

(* ========================================================= *)
(* БЛОК 0б: СМЕНА ВЫБРАННОГО НАСОСА                          *)
(* ========================================================= *)
IF (iDebugMode = 1) AND (iDebugPumpSelected <> iDebugPumpSelected_Prev) THEN
    FOR i := 1 TO cPumpCount DO
        xDebugModePump[i] := (i = iDebugPumpSelected);
    END_FOR;
END_IF;
iDebugPumpSelected_Prev := iDebugPumpSelected;

(* ========================================================= *)
(* БЛОК 0в: ОКНО "ПРИМЕНИТЬ ПАРАМЕТРЫ"                       *)
(* ========================================================= *)
IF xDlgConfirmApply THEN
    CASE iDebugMode OF
        0: ;
        1:
            xApplyParamsPump[iDebugPumpSelected] := TRUE;
        2:
            FOR i := 1 TO cPumpCount DO
                rPumpFreqSetHz[i]             := rPumpFreqSetHz[iDebugPumpSelected];
                rPumpAccTime_Set[i]           := rPumpAccTime_Set[iDebugPumpSelected];
                rPumpDecTime_Set[i]           := rPumpDecTime_Set[iDebugPumpSelected];
                rPumpMaxFreq_Set[i]           := rPumpMaxFreq_Set[iDebugPumpSelected];
                rPumpMinFreq_Set[i]           := rPumpMinFreq_Set[iDebugPumpSelected];
                rPumpMotorRatedCurrent_Set[i] := rPumpMotorRatedCurrent_Set[iDebugPumpSelected];
                rPumpMotorRatedVoltage_Set[i] := rPumpMotorRatedVoltage_Set[iDebugPumpSelected];
                rPumpOverCurrentLevel_A_Set[i] := rPumpOverCurrentLevel_A_Set[iDebugPumpSelected];
                rPumpOverCurrentTime_Set[i]   := rPumpOverCurrentTime_Set[iDebugPumpSelected];
                xPumpOverVoltProtect_Set[i]   := xPumpOverVoltProtect_Set[iDebugPumpSelected];
                iPumpOverheatLevel_Set[i]     := iPumpOverheatLevel_Set[iDebugPumpSelected];
                iPumpOverCurAcc_Set[i]        := iPumpOverCurAcc_Set[iDebugPumpSelected];
                xApplyParamsPump[i] := TRUE;
            END_FOR;
    END_CASE;
    xDlgConfirmApply := FALSE;
    xAskApply        := FALSE;
END_IF;

(* ========================================================= *)
(* БЛОК 0г: ОКНО "СБРОС НА ЗАВОДСКИЕ"                        *)
(* ========================================================= *)
IF xDlgConfirmFactory THEN
    CASE iDebugMode OF
        0: ;
        1: xFactoryResetPump[iDebugPumpSelected] := TRUE;
        2: xFactoryResetAll := TRUE;
    END_CASE;
    xDlgConfirmFactory := FALSE;
    xAskFactory        := FALSE;
END_IF;

(* ========================================================= *)
(* БЛОК 0д: ГРУППОВЫЕ ПУСК/СТОП ИЗ visuDebug                 *)
(* ========================================================= *)
IF xDbgRunAll THEN
    FOR i := 1 TO cPumpCount DO
        xPumpRunCmd[i] := TRUE;
    END_FOR;
    xDbgRunAll := FALSE;
END_IF;
IF xDbgStopAll THEN
    FOR i := 1 TO cPumpCount DO
        xPumpRunCmd[i] := FALSE;
    END_FOR;
    xDbgStopAll := FALSE;
END_IF;

(* ========================================================= *)
(* БЛОК 0е: ЧТЕНИЕ ВСЕХ ПАРАМЕТРОВ (кнопка "Считать все")    *)
(* ========================================================= *)
IF xReadAllAsk THEN
    CASE iDebugMode OF
        0:  xReadAllPump[iDebugPumpSelected] := TRUE;
        1: xReadAllPump[iDebugPumpSelected] := TRUE;
        2:
            FOR i := 1 TO cPumpCount DO
                xReadAllPump[i] := TRUE;
            END_FOR;
    END_CASE;
    xReadAllAsk := FALSE;
END_IF;

(* ========================================================= *)
(* БЛОК 0ж: ЗАПИСЬ ВСЕХ ПАРАМЕТРОВ (кнопка "Записать все")    *)
(* ========================================================= *)
IF xWriteAllConfirm THEN
    CASE iDebugMode OF
        0: ;
        1: xWritePending[iDebugPumpSelected] := TRUE;
        2:
            FOR i := 1 TO cPumpCount DO
                xWritePending[i] := TRUE;
            END_FOR;
    END_CASE;
    xWriteAllConfirm := FALSE;
END_IF;

(* ============================================================ *)
(* ЗАПИСЬ ВСЕХ ПАРАМЕТРОВ — через Modbus-стоп (источник RS-485)*)
(* ============================================================ *)
FOR i := 1 TO cPumpCount DO
    IF xWritePending[i] THEN
        wCmdSourceWrite[i]  := WORD#2;   // команды RS-485 (F1.02/P0.02 = 2)
        (* Источник частоты RS-485: PUMP F1.01=5, VL P0.03=9 *)
        IF ePumpType[i] = E_PumpType.VL THEN
            wFreqSourceWrite[i] := WORD#9;
        ELSE
            wFreqSourceWrite[i] := WORD#5;
        END_IF;
        xWr_Sources[i]      := TRUE;

        xPumpRunCmd[i] := FALSE;
        tonStopWaitAll[i](IN := TRUE, PT := tStopWaitMax);

        IF xPumpFullyStopped[i] THEN
            tonStopWaitAll[i](IN := FALSE);
            (* Общие базовые уставки *)
            xWr_AccTime[i]      := TRUE;
            xWr_DecTime[i]      := TRUE;
            xWr_MaxFreq[i]      := TRUE;
            xWr_MinFreq[i]      := TRUE;
            xWr_MotorCurrent[i] := TRUE;
            xWr_MotorVoltage[i] := TRUE;
            IF ePumpType[i] = E_PumpType.PUMP THEN
                (* Только PUMP: разблокировка F8.00, снятие замка F1.18, защиты *)
                xWr_UnlockF800[i]   := TRUE;
                xWr_ParamLock[i]    := TRUE;
                xWr_OverCurLevel[i] := TRUE;
                xWr_OverCurTime[i]  := TRUE;
                xWr_OverVoltProt[i] := TRUE;
                xWr_Overheat[i]     := TRUE;
                xWr_OverCurAcc[i]   := TRUE;
            END_IF;
            xWritePending[i]    := FALSE;
        ELSIF tonStopWaitAll[i].Q THEN
            xWritePending[i] := FALSE;
            tonStopWaitAll[i](IN := FALSE);
        END_IF;
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 0з: ЗАПИСЬ ОДНОГО ПАРАМЕТРА (кнопки у строк)         *)
(* ========================================================= *)
rMaxDecTime := 0.0;
FOR i := 1 TO cPumpCount DO
    IF rPumpDecTime_Set[i] > rMaxDecTime THEN
        rMaxDecTime := rPumpDecTime_Set[i];
    END_IF;
END_FOR;
tWriteHoldDyn := REAL_TO_TIME((rMaxDecTime + 5.0) * 1000.0);

FOR i := 1 TO cPumpCount DO
    (* Классификация «нужен стоп» ЗАВИСИТ ОТ ТИПА (флаги X/O из РЭ):     *)
    (*  PUMP: стоп для макс/мин.частоты, двигателя и всех защит.         *)
    (*  VL:   стоп только для макс.частоты (P0.10=X) и двигателя         *)
    (*        (P1.02/03/05=X). Мин.частота (P0.14=O), разгон/торм (O) —  *)
    (*        на ходу. Защиты у VL не пишем (группа P8).                 *)
    IF ePumpType[i] = E_PumpType.VL THEN
        xNeedStopWrite[i] := xWr_MaxFreq[i] OR xWr_MotorCurrent[i] OR xWr_MotorVoltage[i];
        xNoStopWrite[i]   := xWr_AccTime[i] OR xWr_DecTime[i] OR xWr_MinFreq[i];
    ELSE
        xNeedStopWrite[i] := xWr_MaxFreq[i] OR xWr_MinFreq[i]
            OR xWr_MotorCurrent[i] OR xWr_MotorVoltage[i] OR xWr_OverCurLevel[i]
            OR xWr_OverCurTime[i] OR xWr_OverVoltProt[i] OR xWr_Overheat[i]
            OR xWr_OverCurAcc[i];
        xNoStopWrite[i]   := xWr_AccTime[i] OR xWr_DecTime[i];
    END_IF;

    (* Разблокировка перед записью — только PUMP (F8.00=1 + снятие F1.18). *)
    (* У VL этих регистров нет; пароль VL блокирует пульт, а не запись по  *)
    (* Modbus (проверить на объекте).                                     *)
    IF (xNeedStopWrite[i] OR xNoStopWrite[i]) AND (ePumpType[i] = E_PumpType.PUMP) THEN
        xWr_UnlockF800[i] := TRUE;
        xWr_ParamLock[i]  := TRUE;
    END_IF;

    IF xNeedStopWrite[i] THEN
        wCmdSourceWrite[i]  := WORD#2;
        IF ePumpType[i] = E_PumpType.VL THEN
            wFreqSourceWrite[i] := WORD#9;
        ELSE
            wFreqSourceWrite[i] := WORD#5;
        END_IF;
        xWr_Sources[i]      := TRUE;

        IF NOT xPumpFullyStopped[i] THEN
            xPumpRunCmd[i] := FALSE;
            xWaitStopForWrite[i] := TRUE;
			xAskDialogStopPch  := TRUE;
        ELSE
            xWaitStopForWrite[i] := FALSE;
			xAskDialogStopPch  := FALSE;
        END_IF;
    ELSE
        xWaitStopForWrite[i] := FALSE;
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 1: ГРУППОВОЙ ФЛАГ ОТЛАДКИ                            *)
(* ========================================================= *)
IF xDebugModeAll <> xDebugModeAll_Prev THEN
    FOR i := 1 TO cPumpCount DO
        xDebugModePump[i] := xDebugModeAll;
    END_FOR;
    xDebugModeAll_Prev := xDebugModeAll;
END_IF;

(* ========================================================= *)
(* БЛОК 2: ПЕРЕХВАТ СМЕНЫ РЕЖИМА ОТЛАДКИ — ИСТОЧНИК RS-485   *)
(* ========================================================= *)
FOR i := 1 TO cPumpCount DO
    IF xDebugModePump[i] <> xDebugModePump_Prev[i] THEN
        IF xDebugModePump[i] THEN
            (* Вход в отладку → управление по RS-485 *)
            wCmdSourceWrite[i]  := WORD#2;
            IF ePumpType[i] = E_PumpType.VL THEN
                wFreqSourceWrite[i] := WORD#9;   // VL P0.03=9
            ELSE
                wFreqSourceWrite[i] := WORD#5;   // PUMP F1.01=5
            END_IF;
        ELSE
            (* Выход → возврат на пульт/потенциометр *)
            IF ePumpType[i] = E_PumpType.VL THEN
                wCmdSourceWrite[i]  := WORD#0;   // VL P0.02=0 (пульт)
                wFreqSourceWrite[i] := WORD#2;   // VL P0.03=2 (потенциометр)
            ELSE
                wCmdSourceWrite[i]  := WORD#1;   // PUMP F1.02=1 (пульт)
                wFreqSourceWrite[i] := WORD#3;   // PUMP F1.01=3 (потенциометр)
            END_IF;
        END_IF;
        xWr_Sources[i] := TRUE;
        xDebugModePump_Prev[i] := xDebugModePump[i];
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 3: ГРУППОВОЙ ТРИГГЕР "ПРИМЕНИТЬ"                     *)
(* ========================================================= *)
IF xApplyParamsAll THEN
    FOR i := 1 TO cPumpCount DO
        xApplyParamsPump[i] := TRUE;
    END_FOR;
    xApplyParamsAll := FALSE;
END_IF;

(* ========================================================= *)
(* БЛОК 4: ГРУППОВОЙ ТРИГГЕР "СБРОС НА ЗАВОДСКИЕ"            *)
(* ========================================================= *)
IF xFactoryResetAll THEN
    FOR i := 1 TO cPumpCount DO
        xFactoryResetPump[i] := TRUE;
    END_FOR;
    xFactoryResetAll := FALSE;
END_IF;

FOR i := 1 TO cPumpCount DO
    IF xFactoryResetPump[i] THEN
        wPumpFactoryResetWrite[i] := WORD#8;
    ELSE
        wPumpFactoryResetWrite[i] := WORD#0;
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 4а: КОНТРОЛЬ СВЯЗИ — xError + ФИЛЬТР                  *)
(* ========================================================= *)
xPumpCommRaw[1] := EMD_PUMP_1.xError;
xPumpCommRaw[2] := EMD_PUMP_2.xError;

(* === ДДЮТ:ИСПРАВЛЕНО (баг: статус ПЧ прыгал каждые 3-5 сек) === *)
(* Раньше TON висел прямо на xError. TON — задержка ТОЛЬКО на     *)
(* включение: на спаде IN его Q сбрасывается МГНОВЕННО, а ET      *)
(* обнуляется. Драйвер Modbus при физически отсутствующем ПЧ не   *)
(* держит xError постоянно взведённым — между попытками опроса    *)
(* флаг коротко проваливается в FALSE. В этот скан оба флага —    *)
(* и сырой, и фильтрованный — были FALSE, защита в FB_Pump не     *)
(* срабатывала, и статус срывался на "Стоп" по нулевому wStatus.  *)
(* Затем TON набирал свои 3с с нуля — отсюда period 3-5 секунд.   *)
(* Побочно мигали iErrorsModules и sSystemStateText на главном.   *)
(* TOF перекрывает провалы, TON видит уже сплошной сигнал:        *)
(* подъём как был (3с непрерывной ошибки), спад теперь требует    *)
(* 10с непрерывно исправной связи.                                *)
(* Если мигание останется — пауза опроса драйвера длиннее уставки,*)
(* поднять PT у TOF. Зависит от таймаута/ретраев в дереве Modbus. *)
tofPumpCommHold[1](IN := EMD_PUMP_1.xError, PT := T#10S);
tonPumpCommFilter[1](IN := tofPumpCommHold[1].Q, PT := T#3S);
xPumpCommError[1] := tonPumpCommFilter[1].Q;

tofPumpCommHold[2](IN := EMD_PUMP_2.xError, PT := T#10S);
tonPumpCommFilter[2](IN := tofPumpCommHold[2].Q, PT := T#3S);
xPumpCommError[2] := tonPumpCommFilter[2].Q;

(* ========================================================= *)
(* БЛОК 5: ВЫЗОВ FB ДЛЯ ВСЕХ НАСОСОВ                         *)
(* ========================================================= *)
FOR i := 1 TO cPumpCount DO
    xDebugForPump   := xDebugModePump[i] OR xDebugModeAll;
    wActualFaultReg := wPumpFaultReg[i];

    Pump[i](
        eType                  := ePumpType[i],
        xDebugMode             := xDebugForPump,
        xCommError             := xPumpCommError[i],
        xCommUnstable          := xPumpCommRaw[i],

        xRunCmd                := xPumpRunCmd[i],
        rFreqSetHz             := rPumpFreqSetHz[i],

        wStatus                := wPumpStatus[i],
        wFaultReg              := wActualFaultReg,
        wFreqSetRead           := wPumpFreqSetRead[i],
        wFreqActual            := wPumpFreqActual[i],
        wCurrentActual         := wPumpCurrentActual[i],
        wSpeedActual           := wPumpSpeedActual[i],
        wDcVoltage             := wPumpDcVoltage[i],
        wTemperature           := wPumpTemperature[i],
        wVoltageActual         := wPumpVoltageActual[i],
        wRuntimeHoursRaw       := wPumpRuntimeHoursRaw[i],
        wAccTimeRawRead        := wPumpAccTimeRaw[i],
        wDecTimeRawRead        := wPumpDecTimeRaw[i],
        wMaxFreqRead           := wPumpMaxFreqRead[i],
        wMinFreqRead           := wPumpMinFreqRead[i],
        wMotorRatedCurrentRead := wPumpMotorRatedCurrentRead[i],
        wMotorRatedVoltageRead := wPumpMotorRatedVoltageRead[i],
        wOverCurrentLevelRead  := wPumpOverCurrentLevelRead[i],
        wOverheatLevelRead     := wPumpOverheatLevelRead[i],
        wOverCurAccRead        := wPumpOverCurAccRead[i],
        wOverCurrentTimeRead   := wPumpOverCurrentTimeRead[i],
        wOverVoltProtectRead   := wPumpOverVoltProtectRead[i],

        rAccTime_Set            := rPumpAccTime_Set[i],
        rDecTime_Set            := rPumpDecTime_Set[i],
        rMaxFreq_Set            := rPumpMaxFreq_Set[i],
        rMinFreq_Set            := rPumpMinFreq_Set[i],
        rMotorRatedCurrent_Set  := rPumpMotorRatedCurrent_Set[i],
        rMotorRatedVoltage_Set  := rPumpMotorRatedVoltage_Set[i],
        rOverCurrentLevel_A_Set := rPumpOverCurrentLevel_A_Set[i],
        rOverCurrentTime_Set    := rPumpOverCurrentTime_Set[i],
        xOverVoltProtect_Set    := xPumpOverVoltProtect_Set[i],
        iOverheatLevel_Set      := iPumpOverheatLevel_Set[i],
        iOverCurAcc_Set         := iPumpOverCurAcc_Set[i],

        wCmd                    => wPumpCmd[i],
        wFreq                   => wPumpFreq[i],
        wAccTimeRawWrite        => wPumpAccTimeWrite[i],
        wDecTimeRawWrite        => wPumpDecTimeWrite[i],
        wMaxFreqWrite           => wPumpMaxFreqWrite[i],
        wMinFreqWrite           => wPumpMinFreqWrite[i],
        wMotorRatedCurrentWrite => wPumpMotorRatedCurrentWrite[i],
        wMotorRatedVoltageWrite => wPumpMotorRatedVoltageWrite[i],
        wOverCurrentLevelWrite  => wPumpOverCurrentLevelWrite[i],
        wOverCurrentTimeWrite   => wPumpOverCurrentTimeWrite[i],
        wOverVoltProtectWrite   => wPumpOverVoltProtectWrite[i],
        wOverheatLevelWrite     => wPumpOverheatLevelWrite[i],
        wOverCurAccWrite        => wPumpOverCurAccWrite[i],

        xRun                    => xPumpWork[i],
        xStop                   => xPumpStop[i],
        xAlarm                  => xPumpAlarm[i],
        sState                  => sPumpState[i],
        sFaultText              => sPumpFaultText[i],
        sTypeText               => sPumpTypeText[i],
        xReverse                => xPumpReverse[i],

        rFreqSetActHz           => rPumpFreqSetActHz[i],
        rFreqActHz              => rPumpFreqActHz[i],
        rCurrentActA            => rPumpCurrentActA[i],
        rSpeedActRpm            => rPumpSpeedActRpm[i],
        rDcVoltageV             => rPumpDcVoltageV[i],
        iTemperatureC           => iPumpTemperatureC[i],
        xIsV12                  => xPumpIsV12[i],
        rVoltageActV            => rPumpVoltageActV[i],
        rRuntimeHours           => rPumpRuntimeHours[i],
        rAccTime_Disp            => rPumpAccTime_Disp[i],
        rDecTime_Disp            => rPumpDecTime_Disp[i],
        rMaxFreq_Disp            => rPumpMaxFreq_Disp[i],
        rMinFreq_Disp            => rPumpMinFreq_Disp[i],
        rMotorRatedCurrent_Disp  => rPumpMotorRatedCurrent_Disp[i],
        rMotorRatedVoltage_Disp  => rPumpMotorRatedVoltage_Disp[i],
        rOverCurrentLevel_A_Disp => rPumpOverCurrentLevel_A_Disp[i],
        iOverCurrentLevel_pct_Disp => iPumpOverCurrentLevel_pct_Disp[i],
        iOverheatLevel_Disp      => iPumpOverheatLevel_Disp[i],
        iOverCurAcc_Disp         => iPumpOverCurAcc_Disp[i],
        rOverCurrentTime_Disp    => rPumpOverCurrentTime_Disp[i],
        xOverVoltProtect_Disp    => xPumpOverVoltProtect_Disp[i]
    );

    IF xPumpCommError[i] OR xPumpCommRaw[i] THEN
        dwPumpLampColor[i] := OVD.COLORS.OwenKeyGrey;
    ELSIF xPumpAlarm[i] THEN
        dwPumpLampColor[i] := OVD.COLORS.Red;
    ELSIF xPumpWork[i] THEN
        dwPumpLampColor[i] := OVD.COLORS.Green;
    ELSE
        dwPumpLampColor[i] := OVD.COLORS.OwenKeyGrey;
    END_IF;
    rPumpFreqPresetHz[i] := WORD_TO_REAL(wPumpFreqPresetRead[i]) / 100.0;
    (* Текст версии прошивки (определена по температуре в FB_Pump) *)
    IF xPumpIsV12[i] THEN sPumpFwVerText[i] := "v1.2"; ELSE sPumpFwVerText[i] := "v2.0"; END_IF;
    (* Пересчёт «сырых» регистров для экрана:                                 *)
    (*  F0.07 ПИД — пульт "p000.0" → разрешение 0.1 → ÷10.                     *)
    (*  F2.02/F2.03 частоты пуска/останова — по факту приходят ×1000          *)
    (*  (0.5 Гц → регистр 500), хотя пульт показывает шаг 0.01 → ÷1000.       *)
    rPumpPidFeedbackDisp[i] := WORD_TO_REAL(wPumpPidFeedback[i]) / 10.0;
    rPumpStartFreqHz[i]     := WORD_TO_REAL(wPumpStartFreqRead[i]) / 1000.0;
    rPumpStopFreqHz[i]      := WORD_TO_REAL(wPumpStopFreqRead[i]) / 1000.0;
END_FOR;

(* ========================================================= *)
(* БЛОК 5_СТОП: ПРИЗНАК "ПЧ ПОЛНОСТЬЮ ОСТАНОВЛЕН"           *)
(* ========================================================= *)
FOR i := 1 TO cPumpCount DO
    IF xPumpCommError[i] THEN
        xPumpFullyStopped[i] := FALSE;
    ELSE
        xPumpFullyStopped[i] :=
            ((wPumpStatus[i] AND 16#0001) = WORD#0)
            AND (wPumpFreqActual[i] = WORD#0);
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 5а: РАСШИФРОВКА ИСТОРИИ АВАРИЙ                       *)
(* ========================================================= *)
FOR i := 1 TO cPumpCount DO
    IF xPumpCommError[i] THEN
        sPumpFaultText[i]     := "Задержка связи";
        sPumpFaultLastText[i] := "Задержка связи";
        sPumpFault2Text[i]    := "Задержка связи";
        sPumpFault3Text[i]    := "Задержка связи";
        sPumpFault4Text[i]    := "Задержка связи";
    ELSE
        IF (wPumpFaultLast[i] AND 16#7FFF) = WORD#0 THEN
            sPumpFaultLastText[i] := "Нет аварии";
        ELSE
            sPumpFaultLastText[i] := F_FaultCodeToText(ePumpType[i], wPumpFaultLast[i]);
        END_IF;
        IF (wPumpFault2[i] AND 16#7FFF) = WORD#0 THEN
            sPumpFault2Text[i] := "Нет аварии";
        ELSE
            sPumpFault2Text[i] := F_FaultCodeToText(ePumpType[i], wPumpFault2[i]);
        END_IF;
        IF (wPumpFault3[i] AND 16#7FFF) = WORD#0 THEN
            sPumpFault3Text[i] := "Нет аварии";
        ELSE
            sPumpFault3Text[i] := F_FaultCodeToText(ePumpType[i], wPumpFault3[i]);
        END_IF;
        IF (wPumpFault4[i] AND 16#7FFF) = WORD#0 THEN
            sPumpFault4Text[i] := "Нет аварии";
        ELSE
            sPumpFault4Text[i] := F_FaultCodeToText(ePumpType[i], wPumpFault4[i]);
        END_IF;
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 5б: ТЕКСТ СТАТУСА ЗАЩИТЫ ПЕРЕНАПРЯЖЕНИЯ              *)
(* ========================================================= *)
FOR i := 1 TO cPumpCount DO
    IF xPumpOverVoltProtect_Disp[i] THEN
        sPumpOverVoltProtect[i] := "Включена";
    ELSE
        sPumpOverVoltProtect[i] := "Выключена";
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 6: РАЗБЛОКИРОВКА РАСШИРЕННЫХ НАСТРОЕК (F800)         *)
(* ========================================================= *)
FOR i := 1 TO cPumpCount DO
    IF xWr_UnlockF800[i] THEN
        wPumpExtSettingsUnlockWrite[i] := WORD#1;
    ELSE
        wPumpExtSettingsUnlockWrite[i] := WORD#0;
    END_IF;
END_FOR;

(* ========================================================= *)
(* БЛОК 7: УДЕРЖАНИЕ ВСЕХ ТРИГГЕРОВ (таймаут tApplyHold)      *)
(* ========================================================= *)
FOR i := 1 TO cPumpCount DO
    tonHoldRead[i](IN := xReadAllPump[i], PT := tApplyHold);
    IF tonHoldRead[i].Q THEN xReadAllPump[i] := FALSE; tonHoldRead[i](IN := FALSE); END_IF;

    tonHold_AccTime[i](IN := xWr_AccTime[i], PT := tApplyHold);
    IF tonHold_AccTime[i].Q THEN xWr_AccTime[i] := FALSE; tonHold_AccTime[i](IN := FALSE); END_IF;

    tonHold_DecTime[i](IN := xWr_DecTime[i], PT := tApplyHold);
    IF tonHold_DecTime[i].Q THEN xWr_DecTime[i] := FALSE; tonHold_DecTime[i](IN := FALSE); END_IF;

    tonHold_MaxFreq[i](IN := xWr_MaxFreq[i], PT := tWriteHoldDyn);
    IF tonHold_MaxFreq[i].Q THEN xWr_MaxFreq[i] := FALSE; tonHold_MaxFreq[i](IN := FALSE); END_IF;

    tonHold_MinFreq[i](IN := xWr_MinFreq[i], PT := tWriteHoldDyn);
    IF tonHold_MinFreq[i].Q THEN xWr_MinFreq[i] := FALSE; tonHold_MinFreq[i](IN := FALSE); END_IF;

    tonHold_MotorCur[i](IN := xWr_MotorCurrent[i], PT := tWriteHoldDyn);
    IF tonHold_MotorCur[i].Q THEN xWr_MotorCurrent[i] := FALSE; tonHold_MotorCur[i](IN := FALSE); END_IF;

    tonHold_MotorVolt[i](IN := xWr_MotorVoltage[i], PT := tWriteHoldDyn);
    IF tonHold_MotorVolt[i].Q THEN xWr_MotorVoltage[i] := FALSE; tonHold_MotorVolt[i](IN := FALSE); END_IF;

    tonHold_OCLevel[i](IN := xWr_OverCurLevel[i], PT := tWriteHoldDyn);
    IF tonHold_OCLevel[i].Q THEN xWr_OverCurLevel[i] := FALSE; tonHold_OCLevel[i](IN := FALSE); END_IF;

    tonHold_OCTime[i](IN := xWr_OverCurTime[i], PT := tWriteHoldDyn);
    IF tonHold_OCTime[i].Q THEN xWr_OverCurTime[i] := FALSE; tonHold_OCTime[i](IN := FALSE); END_IF;

    tonHold_OVProt[i](IN := xWr_OverVoltProt[i], PT := tWriteHoldDyn);
    IF tonHold_OVProt[i].Q THEN xWr_OverVoltProt[i] := FALSE; tonHold_OVProt[i](IN := FALSE); END_IF;

    tonHold_Overheat[i](IN := xWr_Overheat[i], PT := tWriteHoldDyn);
    IF tonHold_Overheat[i].Q THEN xWr_Overheat[i] := FALSE; tonHold_Overheat[i](IN := FALSE); END_IF;

    tonHold_OCAcc[i](IN := xWr_OverCurAcc[i], PT := tWriteHoldDyn);
    IF tonHold_OCAcc[i].Q THEN xWr_OverCurAcc[i] := FALSE; tonHold_OCAcc[i](IN := FALSE); END_IF;

    tonHold_F800[i](IN := xWr_UnlockF800[i], PT := tWriteHoldDyn);
    IF tonHold_F800[i].Q THEN xWr_UnlockF800[i] := FALSE; tonHold_F800[i](IN := FALSE); END_IF;

    (* Снятие замка F1.18 (0x0076←0) — держим тот же интервал, что F800 *)
    tonHold_ParamLock[i](IN := xWr_ParamLock[i], PT := tWriteHoldDyn);
    IF tonHold_ParamLock[i].Q THEN xWr_ParamLock[i] := FALSE; tonHold_ParamLock[i](IN := FALSE); END_IF;

    tonHold_Sources[i](IN := xWr_Sources[i], PT := tApplyHold);
    IF tonHold_Sources[i].Q THEN xWr_Sources[i] := FALSE; tonHold_Sources[i](IN := FALSE); END_IF;

    tonHold_DispParam[i](IN := xWr_DispParam[i], PT := tApplyHold);
    IF tonHold_DispParam[i].Q THEN xWr_DispParam[i] := FALSE; tonHold_DispParam[i](IN := FALSE); END_IF;

    tonHold_ErrDelay[i](IN := xWr_ErrDelayInit[i], PT := tApplyHold);
    IF tonHold_ErrDelay[i].Q THEN xWr_ErrDelayInit[i] := FALSE; tonHold_ErrDelay[i](IN := FALSE); END_IF;

    tonFactoryHold[i](IN := xFactoryResetPump[i], PT := tApplyHold);
    IF tonFactoryHold[i].Q THEN xFactoryResetPump[i] := FALSE; tonFactoryHold[i](IN := FALSE); END_IF;

    tonApplyHold[i](IN := xApplyParamsPump[i], PT := tApplyHold);
    IF tonApplyHold[i].Q THEN xApplyParamsPump[i] := FALSE; tonApplyHold[i](IN := FALSE); END_IF;
END_FOR;


(* ========================================================= *)
(* БЛОК 8: ЖУРНАЛ ИЗМЕНЕНИЙ ПАРАМЕТРОВ ПЧ                    *)
(* ========================================================= *)
IF xLogClear THEN
    FOR i := 1 TO 30 DO
        aPumpLog[i] := "";
    END_FOR;
    iPumpLogCount  := 0;
    xLogClear      := FALSE;
    xAskClearLog   := FALSE;   (* === ДДЮТ:ИЗМЕНЕНО === PLC сам закрывает диалог. *)
    (* GVL.xLogClear теперь пишется ТОЛЬКО из PRG_Fountain.st (блок проверки  *)
    (* пароля через СВОЙ экран (не встроенный виджет OwenVisu) — см.        *)
    (* переменные xPumpLogPinEntry/xPumpLogPinSubmit там же, PRG_Fountain.st,*)
    (* блок 17а. Сама очистка и закрытие диалога остаются здесь.             *)
END_IF;

(* === ДДЮТ:ИСПРАВЛЕНО === Старая обрезка через WMID убрана — теперь      *)
(* обрезку делает сама F_PumpLogWrite (посимвольным сдвигом, см. там),    *)
(* заодно исправлен реальный баг переполнения WCONCAT (см. пояснение в    *)
(* F_PumpLogWrite.st) — из-за него журнал ПЧ фактически не рос нормально. *)

FOR i := 1 TO cPumpCount DO

    IF xPumpCommError[i] THEN
        xLog_Initialized[i] := FALSE;
    END_IF;

    IF rtrigReadAll_Prev[i] AND NOT xReadAllPump[i] AND NOT xPumpCommError[i] THEN
        rLog_AccTime_Prev[i]   := rPumpAccTime_Disp[i];
        rLog_DecTime_Prev[i]   := rPumpDecTime_Disp[i];
        rLog_MaxFreq_Prev[i]   := rPumpMaxFreq_Disp[i];
        rLog_MinFreq_Prev[i]   := rPumpMinFreq_Disp[i];
        rLog_MotorCur_Prev[i]  := rPumpMotorRatedCurrent_Disp[i];
        rLog_MotorVolt_Prev[i] := rPumpMotorRatedVoltage_Disp[i];
        rLog_OCLevel_Prev[i]   := rPumpOverCurrentLevel_A_Disp[i];
        rLog_OCTime_Prev[i]    := rPumpOverCurrentTime_Disp[i];
        xLog_OVProt_Prev[i]    := xPumpOverVoltProtect_Disp[i];
        iLog_Overheat_Prev[i]  := iPumpOverheatLevel_Disp[i];
        iLog_OCAcc_Prev[i]     := iPumpOverCurAcc_Disp[i];
        xLog_Initialized[i]    := TRUE;
    END_IF;
    rtrigReadAll_Prev[i] := xReadAllPump[i];

    IF NOT xPumpCommError[i] AND xLog_Initialized[i] THEN

        IF rPumpAccTime_Disp[i] <> rLog_AccTime_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Разгон: ", WCONCAT(REAL_TO_WSTRING(rLog_AccTime_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpAccTime_Disp[i]), "с$N"))))))));
            rLog_AccTime_Prev[i] := rPumpAccTime_Disp[i];
        END_IF;

        IF rPumpDecTime_Disp[i] <> rLog_DecTime_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Торможение: ", WCONCAT(REAL_TO_WSTRING(rLog_DecTime_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpDecTime_Disp[i]), "с$N"))))))));
            rLog_DecTime_Prev[i] := rPumpDecTime_Disp[i];
        END_IF;

        IF rPumpMaxFreq_Disp[i] <> rLog_MaxFreq_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Макс.част: ", WCONCAT(REAL_TO_WSTRING(rLog_MaxFreq_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpMaxFreq_Disp[i]), "Гц$N"))))))));
            rLog_MaxFreq_Prev[i] := rPumpMaxFreq_Disp[i];
        END_IF;

        IF rPumpMinFreq_Disp[i] <> rLog_MinFreq_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Мин.част: ", WCONCAT(REAL_TO_WSTRING(rLog_MinFreq_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpMinFreq_Disp[i]), "Гц$N"))))))));
            rLog_MinFreq_Prev[i] := rPumpMinFreq_Disp[i];
        END_IF;

        IF rPumpMotorRatedCurrent_Disp[i] <> rLog_MotorCur_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Ном.ток: ", WCONCAT(REAL_TO_WSTRING(rLog_MotorCur_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpMotorRatedCurrent_Disp[i]), "А$N"))))))));
            rLog_MotorCur_Prev[i] := rPumpMotorRatedCurrent_Disp[i];
        END_IF;

        IF rPumpMotorRatedVoltage_Disp[i] <> rLog_MotorVolt_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Ном.напр: ", WCONCAT(REAL_TO_WSTRING(rLog_MotorVolt_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpMotorRatedVoltage_Disp[i]), "В$N"))))))));
            rLog_MotorVolt_Prev[i] := rPumpMotorRatedVoltage_Disp[i];
        END_IF;

        IF rPumpOverCurrentLevel_A_Disp[i] <> rLog_OCLevel_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Ур.тока: ", WCONCAT(REAL_TO_WSTRING(rLog_OCLevel_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpOverCurrentLevel_A_Disp[i]), "А$N"))))))));
            rLog_OCLevel_Prev[i] := rPumpOverCurrentLevel_A_Disp[i];
        END_IF;

        IF rPumpOverCurrentTime_Disp[i] <> rLog_OCTime_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Вр.тока: ", WCONCAT(REAL_TO_WSTRING(rLog_OCTime_Prev[i]),
                WCONCAT("→", WCONCAT(REAL_TO_WSTRING(rPumpOverCurrentTime_Disp[i]), "с$N"))))))));
            rLog_OCTime_Prev[i] := rPumpOverCurrentTime_Disp[i];
        END_IF;

        IF xPumpOverVoltProtect_Disp[i] <> xLog_OVProt_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Зщт.перенапр: ", WCONCAT(SEL(xLog_OVProt_Prev[i], "Выкл", "Вкл"),
                WCONCAT("→", WCONCAT(SEL(xPumpOverVoltProtect_Disp[i], "Выкл", "Вкл"), "$N"))))))));
            xLog_OVProt_Prev[i] := xPumpOverVoltProtect_Disp[i];
        END_IF;

        IF iPumpOverheatLevel_Disp[i] <> iLog_Overheat_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Перегрев: ", WCONCAT(INT_TO_WSTRING(iLog_Overheat_Prev[i]),
                WCONCAT("→", WCONCAT(INT_TO_WSTRING(iPumpOverheatLevel_Disp[i]), "°C$N"))))))));
            iLog_Overheat_Prev[i] := iPumpOverheatLevel_Disp[i];
        END_IF;

        IF iPumpOverCurAcc_Disp[i] <> iLog_OCAcc_Prev[i] THEN
            F_PumpLogWrite(WCONCAT(F_FormatLogTimestamp(),
                WCONCAT(" | ПЧ", WCONCAT(INT_TO_WSTRING(i),
                WCONCAT(" | Огр.тока.разг: ", WCONCAT(INT_TO_WSTRING(iLog_OCAcc_Prev[i]),
                WCONCAT("→", WCONCAT(INT_TO_WSTRING(iPumpOverCurAcc_Disp[i]), "%$N"))))))));
            iLog_OCAcc_Prev[i] := iPumpOverCurAcc_Disp[i];
        END_IF;

    END_IF;
END_FOR;


(* ========================================================= *)
(* БЛОК 9: РАЗОВАЯ ИНИЦИАЛИЗАЦИЯ ПАРАМЕТРОВ ПЧ ПРИ СТАРТЕ    *)
(* ========================================================= *)
tonInitDelay(IN := TRUE, PT := T#5S);

IF tonInitDelay.Q AND NOT xInitDone THEN
    FOR i := 1 TO cPumpCount DO
        IF NOT xErrDelayWritten[i] AND NOT xPumpCommError[i] THEN
            wPumpRS_ErrDelayWrite[i] := WORD#5;
            xWr_ErrDelayInit[i]      := TRUE;
            xErrDelayWritten[i]      := TRUE;
        END_IF;

        IF NOT xDispParamWritten[i] AND NOT xPumpCommError[i] THEN
            wPumpDispParamWrite[i] := WORD#1;
            xWr_DispParam[i]       := TRUE;
            xDispParamWritten[i]   := TRUE;
        END_IF;
    END_FOR;
    xInitDone := TRUE;
END_IF;
