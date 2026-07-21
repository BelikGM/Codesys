(* ============================================================ *)
(* FB_Pump — управление одним ПЧ ELHART (PUMP/MINI) по Modbus  *)
(* Проект ДДЮТ (на основе Fontan_V1 / Саки Пруд).               *)
(* === ДДЮТ:ИЗМЕНЕНО === Температура (блок 6) — без деления на  *)
(* 10 (регистр 0x0006 на ДДЮТ отдаёт целые °C). См. комментарий  *)
(* в блоке 6 ниже.                                               *)
(* ============================================================ *)

FUNCTION_BLOCK FB_Pump
VAR_INPUT
    eType      : E_PumpType;
    xDebugMode : BOOL;
    xCommError : BOOL;
    xCommUnstable : BOOL;

    xRunCmd      : BOOL;
    rFreqSetHz   : REAL;

    wStatus          : WORD;
    wFaultReg        : WORD;
    wFreqSetRead     : WORD;
    wFreqActual      : WORD;
    wCurrentActual   : WORD;
    wSpeedActual     : WORD;
    wDcVoltage       : WORD;
    wTemperature     : WORD;
    wVoltageActual   : WORD;
    wRuntimeHoursRaw : WORD;
    wAccTimeRawRead        : WORD;
    wDecTimeRawRead        : WORD;
    wMaxFreqRead           : WORD;
    wMinFreqRead           : WORD;
    wMotorRatedCurrentRead : WORD;
    wMotorRatedVoltageRead : WORD;
    wOverCurrentLevelRead  : WORD;
    wOverheatLevelRead     : WORD;
    wOverCurAccRead        : WORD;
    wOverCurrentTimeRead   : WORD;
    wOverVoltProtectRead   : WORD;

    rAccTime_Set            : REAL;
    rDecTime_Set            : REAL;
    rMaxFreq_Set            : REAL;
    rMinFreq_Set            : REAL;
    rMotorRatedCurrent_Set  : REAL;
    rMotorRatedVoltage_Set  : REAL;
    rOverCurrentLevel_A_Set : REAL;
    rOverCurrentTime_Set    : REAL;
    xOverVoltProtect_Set    : BOOL;
    iOverheatLevel_Set      : INT;
    iOverCurAcc_Set         : INT;
END_VAR
VAR_OUTPUT
    wCmd  : WORD;
    wFreq : WORD;
    wAccTimeRawWrite        : WORD;
    wDecTimeRawWrite        : WORD;
    wMaxFreqWrite           : WORD;
    wMinFreqWrite           : WORD;
    wMotorRatedCurrentWrite : WORD;
    wMotorRatedVoltageWrite : WORD;
    wOverCurrentLevelWrite  : WORD;
    wOverCurrentTimeWrite   : WORD;
    wOverVoltProtectWrite   : WORD;
    wOverheatLevelWrite     : WORD;
    wOverCurAccWrite        : WORD;

    xRun       : BOOL;
    xStop      : BOOL;
    xAlarm     : BOOL;
    sState     : WSTRING(50);
    sFaultText : WSTRING(100);
    sTypeText  : WSTRING(20);
    xReverse   : BOOL;

    rFreqSetActHz : REAL;
    rFreqActHz    : REAL;
    rCurrentActA  : REAL;
    rSpeedActRpm  : REAL;
    rDcVoltageV   : REAL;
    iTemperatureC : INT;
    rVoltageActV  : REAL;
    rRuntimeHours : REAL;
    rAccTime_Disp            : REAL;
    rDecTime_Disp            : REAL;
    rMaxFreq_Disp            : REAL;
    rMinFreq_Disp            : REAL;
    rMotorRatedCurrent_Disp  : REAL;
    rMotorRatedVoltage_Disp  : REAL;
    rOverCurrentLevel_A_Disp : REAL;
    iOverCurrentLevel_pct_Disp : INT;
    iOverheatLevel_Disp      : INT;
    iOverCurAcc_Disp         : INT;
    rOverCurrentTime_Disp    : REAL;
    xOverVoltProtect_Disp    : BOOL;
END_VAR
VAR
    rK_Freq         : REAL;
    rFreqLim        : REAL;
    xFaultActive    : BOOL;
    wCleanFaultCode : WORD;
    iFaultCode      : INT;
    rTmp : REAL;
    iTmp : INT;
END_VAR


(* ========================================================= *)
(* 1. Коэффициент пересчёта частоты                          *)
(* PUMP: 0,01 Гц → k=100 | MINI: 0,1 Гц → k=10               *)
(* ========================================================= *)
IF eType = E_PumpType.PUMP THEN
    rK_Freq   := 100.0;
    sTypeText := "EMD-PUMP";
ELSE
    rK_Freq   := 10.0;
    sTypeText := "EMD-MINI v2.1";
END_IF;


(* ========================================================= *)
(* 2. Команда управления и задание частоты (0x2000 / 0x2001) *)
(* ========================================================= *)
rFreqLim := rFreqSetHz;
IF rFreqLim < cMinFreq THEN rFreqLim := cMinFreq; END_IF;
IF rFreqLim > cMaxFreq THEN rFreqLim := cMaxFreq; END_IF;

IF xRunCmd THEN
    wCmd  := 16#000A;
    wFreq := REAL_TO_WORD(rFreqLim * rK_Freq);
ELSE
    wCmd  := 16#0009;
    wFreq := REAL_TO_WORD(rFreqLim * rK_Freq);
END_IF;


(* ========================================================= *)
(* 3. Нет связи → показать и выйти                           *)
(* ========================================================= *)
xStop := FALSE; xRun := FALSE; xAlarm := FALSE;
xReverse := FALSE; xFaultActive := FALSE;

IF xCommError OR xCommUnstable THEN
    xAlarm     := FALSE;
    xStop      := FALSE;
    xRun       := FALSE;
    sState     := "Нет связи с ПЧ";
    sFaultText := "Проверьте RS-485 / адрес / питание ПЧ";
    RETURN;
END_IF;


(* ========================================================= *)
(* 4. Состояние ПЧ по 0x001C                                *)
(* ========================================================= *)
CASE eType OF
    E_PumpType.PUMP:
        xReverse := (wStatus AND 16#0004) <> 0;
        IF (wStatus AND 16#0008) <> 0 THEN
            xAlarm := TRUE; xFaultActive := TRUE; sState := "Авария";
        ELSIF (wStatus AND 16#0001) <> 0 THEN
            xRun := TRUE;
            IF xReverse THEN sState := "Работа (реверс)"; ELSE sState := "Работа"; END_IF;
        ELSE
            xStop := TRUE; sState := "Стоп";
        END_IF;
    E_PumpType.MINI:
        xReverse := (wStatus AND 16#0001) <> 0;
        IF (wStatus AND 16#0002) <> 0 THEN
            xRun := TRUE;
            IF xReverse THEN sState := "Работа (реверс)"; ELSE sState := "Работа"; END_IF;
        ELSE
            xStop := TRUE; sState := "Стоп";
        END_IF;
END_CASE;


(* ========================================================= *)
(* 5. Разбор аварий                                         *)
(* ========================================================= *)
CASE eType OF
    E_PumpType.PUMP:
        IF (wFaultReg AND 16#8000) <> 0 THEN
            xAlarm := TRUE; xRun := FALSE; xStop := FALSE; sState := "Авария";
            wCleanFaultCode := wFaultReg AND 16#7FFF;
            sFaultText := F_FaultCodeToText(eType, wCleanFaultCode);
        ELSE
            sFaultText := "Нет ошибок";
        END_IF;
    E_PumpType.MINI:
        iFaultCode := WORD_TO_INT(wFaultReg);
        IF (iFaultCode > 63) AND ((iFaultCode < 88) OR (iFaultCode > 91)) THEN
            xAlarm := TRUE; xRun := FALSE; xStop := FALSE; sState := "Авария";
            sFaultText := F_FaultCodeToText(eType, wFaultReg);
        ELSE
            sFaultText := "Нет ошибок";
        END_IF;
END_CASE;


(* ========================================================= *)
(* 6. ЧТЕНИЕ реальных значений из ПЧ → _Disp (для показа)    *)
(* ========================================================= *)
rFreqSetActHz := WORD_TO_REAL(wFreqSetRead) / rK_Freq;
rFreqActHz    := WORD_TO_REAL(wFreqActual)  / rK_Freq;
rCurrentActA  := WORD_TO_REAL(wCurrentActual) / 10.0;
rSpeedActRpm  := WORD_TO_REAL(wSpeedActual);
rDcVoltageV   := WORD_TO_REAL(wDcVoltage) / 10.0;

(* === ДДЮТ:ИЗМЕНЕНО === Температура: БЕЗ деления на 10.       *)
(* На Саки регистр 0x0006 отдавал ×10 (0.1°C), на ДДЮТ — уже    *)
(* целые °C (та же марка ПЧ, но другая дискретность регистра —  *)
(* сверено на объекте: /10.0 давало 4°C вместо реальных 40°C).  *)
(* Если на твоём ПЧ регистр всё-таки ×10 — верни /10.0 обратно. *)
iTemperatureC := WORD_TO_INT(wTemperature);

rVoltageActV  := WORD_TO_REAL(wVoltageActual) / 10.0;
rRuntimeHours := WORD_TO_REAL(wRuntimeHoursRaw);

rAccTime_Disp           := WORD_TO_REAL(wAccTimeRawRead) / 10.0;
rDecTime_Disp           := WORD_TO_REAL(wDecTimeRawRead) / 10.0;
rMaxFreq_Disp           := WORD_TO_REAL(wMaxFreqRead) / rK_Freq;
rMinFreq_Disp           := WORD_TO_REAL(wMinFreqRead) / rK_Freq;
rMotorRatedCurrent_Disp := WORD_TO_REAL(wMotorRatedCurrentRead) / 10.0;
rMotorRatedVoltage_Disp := WORD_TO_REAL(wMotorRatedVoltageRead) / 10.0;
iOverCurrentLevel_pct_Disp := WORD_TO_INT(wOverCurrentLevelRead);
IF rMotorRatedCurrent_Disp > 0.0 THEN
    rOverCurrentLevel_A_Disp := (INT_TO_REAL(iOverCurrentLevel_pct_Disp) / 100.0)
                                 * rMotorRatedCurrent_Disp;
ELSE
    rOverCurrentLevel_A_Disp := 0.0;
END_IF;
iOverheatLevel_Disp := WORD_TO_INT(wOverheatLevelRead);
iOverCurAcc_Disp    := WORD_TO_INT(wOverCurAccRead);
rOverCurrentTime_Disp := WORD_TO_REAL(wOverCurrentTimeRead) / 10.0;
xOverVoltProtect_Disp := (wOverVoltProtectRead <> WORD#0);


(* ========================================================= *)
(* 7. ЗАДАНИЕ оператора → регистры ЗАПИСИ (_Set, с валидацией)*)
(* ========================================================= *)
rTmp := rAccTime_Set;
IF rTmp < cMinTime THEN rTmp := cMinTime; ELSIF rTmp > cMaxTime THEN rTmp := cMaxTime; END_IF;
wAccTimeRawWrite := REAL_TO_WORD(rTmp * 10.0);

rTmp := rDecTime_Set;
IF rTmp < cMinTime THEN rTmp := cMinTime; ELSIF rTmp > cMaxTime THEN rTmp := cMaxTime; END_IF;
wDecTimeRawWrite := REAL_TO_WORD(rTmp * 10.0);

rTmp := rMaxFreq_Set;
IF rTmp < 1.0 THEN rTmp := 1.0; ELSIF rTmp > cMaxFreq THEN rTmp := cMaxFreq; END_IF;
wMaxFreqWrite := REAL_TO_WORD(rTmp * rK_Freq);
rTmp := rMinFreq_Set;
IF rTmp < 0.0 THEN rTmp := 0.0; ELSIF rTmp > rMaxFreq_Set THEN rTmp := rMaxFreq_Set; END_IF;
wMinFreqWrite := REAL_TO_WORD(rTmp * rK_Freq);

rTmp := rMotorRatedVoltage_Set;
IF rTmp < 0.0 THEN rTmp := 0.0; ELSIF rTmp > cMaxVoltage THEN rTmp := cMaxVoltage; END_IF;
wMotorRatedVoltageWrite := REAL_TO_WORD(rTmp * 10.0);
rTmp := rMotorRatedCurrent_Set;
IF rTmp < 0.1 THEN rTmp := 0.1; ELSIF rTmp > cMaxCurrent THEN rTmp := cMaxCurrent; END_IF;
wMotorRatedCurrentWrite := REAL_TO_WORD(rTmp * 10.0);

IF rMotorRatedCurrent_Set > 0.0 THEN
    iTmp := REAL_TO_INT((rOverCurrentLevel_A_Set / rMotorRatedCurrent_Set) * 100.0);
ELSE
    iTmp := 0;
END_IF;
IF iTmp < 0 THEN iTmp := 0; ELSIF iTmp > 200 THEN iTmp := 200; END_IF;
wOverCurrentLevelWrite := INT_TO_WORD(iTmp);

rTmp := rOverCurrentTime_Set;
IF rTmp < 0.0 THEN rTmp := 0.0; END_IF;
CASE eType OF
    E_PumpType.PUMP: IF rTmp > 999.9 THEN rTmp := 999.9; END_IF;
    E_PumpType.MINI: IF rTmp > 5.0 THEN rTmp := 5.0; END_IF;
END_CASE;
wOverCurrentTimeWrite := REAL_TO_WORD(rTmp * 10.0);

IF xOverVoltProtect_Set THEN wOverVoltProtectWrite := 1; ELSE wOverVoltProtectWrite := 0; END_IF;

iTmp := iOverheatLevel_Set;
IF iTmp < cMinOverheat THEN iTmp := cMinOverheat; ELSIF iTmp > cMaxOverheat THEN iTmp := cMaxOverheat; END_IF;
wOverheatLevelWrite := INT_TO_WORD(iTmp);

iTmp := iOverCurAcc_Set;
IF iTmp < 0 THEN iTmp := 0; ELSIF iTmp > 200 THEN iTmp := 200; END_IF;
wOverCurAccWrite := INT_TO_WORD(iTmp);
