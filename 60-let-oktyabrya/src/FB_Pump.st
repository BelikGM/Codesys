(* ============================================================ *)
(* FB_Pump — управление одним ПЧ ELHART (PUMP или VL) по Modbus *)
(* ============================================================ *)
(* === ИЗМЕНЕНО (температура + автоопределение версии) ===       *)
(* По РЭ EMD-PUMP температура (F0.06 = рег 0x0006) имеет          *)
(* разрешение 0.1°C (на дисплее "0028.1"=28.1), т.е. регистр      *)
(* отдаёт значение ×10. НО у разных прошивок по-разному:          *)
(*   • «v1.2»: T ×10 (раб. T>10°C → регистр ≥100, напр. 314=31.4) *)
(*   • «v2.0»: T целым (регистр <100, напр. 31)                   *)
(* Версию определяем АВТОМАТИЧЕСКИ по регистру температуры:       *)
(*   регистр ≥100 → v1.2 (делим на 10), иначе v2.0 (как есть).    *)
(* Флаг xIsV12 выводим наружу (для экрана/диагностики и как       *)
(* «переключатель масштаба» для БУДУЩИХ параметров, если          *)
(* подтвердится, что и они расходятся между версиями).            *)
(* ⚠️ Пока по версии масштабируется ТОЛЬКО температура — это       *)
(* единственное подтверждённое расхождение. Ток/DC/напряжение     *)
(* сейчас корректны на обеих версиях (общий /10), их НЕ трогаем,  *)
(* чтобы не сломать рабочее. Если подтвердится расхождение ещё    *)
(* какого-то параметра — заводим его на xIsV12 одной строкой.     *)
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
    xIsV12        : BOOL;   // TRUE = прошивка «v1.2» (T ×10), определено по температуре
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

(* === ТИП ПЧ === PUMP (EMD-PUMP) или VL (EMD-VL/VH, векторный).      *)
(* rK_Freq — делитель частоты мониторинга (÷100 у обоих: PUMP F0.01/02 *)
(* и VL D0.00/01 имеют разрешение 0.01 Гц). MINI удалён (не было).     *)
IF eType = E_PumpType.PUMP THEN
    rK_Freq   := 100.0;
    sTypeText := "EMD-PUMP";
ELSE
    rK_Freq   := 100.0;
    sTypeText := "EMD-VL";
END_IF;

rFreqLim := rFreqSetHz;
IF rFreqLim < cMinFreq THEN rFreqLim := cMinFreq; END_IF;
IF rFreqLim > cMaxFreq THEN rFreqLim := cMaxFreq; END_IF;

(* === КОМАНДА + ЗАДАНИЕ ЧАСТОТЫ === Регистры/коды разные:            *)
(*  PUMP: команда 000A пуск/0009 стоп → 0x2000; частота Гц×100 → 0x2001.*)
(*  VL:   команда 0001 вперёд/0005 стоп выбегом → 0x2000;              *)
(*        задание в % от макс.частоты → 0x1000 (0x2710=100%).          *)
(* В дереве Modbus для VL-узла wFreq привязывается к 0x1000, wCmd к    *)
(* 0x2000 (см. таблицу привязок).                                     *)
IF eType = E_PumpType.PUMP THEN
    IF xRunCmd THEN wCmd := 16#000A; ELSE wCmd := 16#0009; END_IF;
    wFreq := REAL_TO_WORD(rFreqLim * rK_Freq);
ELSE  // VL
    IF xRunCmd THEN wCmd := 16#0001; ELSE wCmd := 16#0005; END_IF;
    IF rMaxFreq_Set > 0.0 THEN
        wFreq := REAL_TO_WORD(rFreqLim / rMaxFreq_Set * 10000.0);   // % ×100
    ELSE
        wFreq := 0;
    END_IF;
END_IF;

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
    E_PumpType.VL:
        (* Статус из регистра 0x3000: 1 вперёд, 2 назад, 3 стоп *)
        xReverse := (wStatus = 2);
        IF (wStatus = 1) OR (wStatus = 2) THEN
            xRun := TRUE;
            IF xReverse THEN sState := "Работа (реверс)"; ELSE sState := "Работа"; END_IF;
        ELSE
            xStop := TRUE; sState := "Стоп";
        END_IF;
END_CASE;

CASE eType OF
    E_PumpType.PUMP:
        IF (wFaultReg AND 16#8000) <> 0 THEN
            xAlarm := TRUE; xRun := FALSE; xStop := FALSE; sState := "Авария";
            wCleanFaultCode := wFaultReg AND 16#7FFF;
            sFaultText := F_FaultCodeToText(eType, wCleanFaultCode);
        ELSE
            sFaultText := "Нет ошибок";
        END_IF;
    E_PumpType.VL:
        (* Код ошибки из регистра 0x8000: 0 = нет ошибок *)
        IF wFaultReg <> 0 THEN
            xAlarm := TRUE; xRun := FALSE; xStop := FALSE; sState := "Авария";
            sFaultText := F_FaultCodeToText(eType, wFaultReg);
        ELSE
            sFaultText := "Нет ошибок";
        END_IF;
END_CASE;

rFreqSetActHz := WORD_TO_REAL(wFreqSetRead) / rK_Freq;   // ÷100 у обоих
rFreqActHz    := WORD_TO_REAL(wFreqActual)  / rK_Freq;
rSpeedActRpm  := WORD_TO_REAL(wSpeedActual);
rDcVoltageV   := WORD_TO_REAL(wDcVoltage) / 10.0;         // ÷10 у обоих

(* Ток и выходное напряжение масштабируются ПО-РАЗНОМУ:              *)
(*  PUMP: ток F0.03 ÷10, вых.напряж F0.09 ÷10.                       *)
(*  VL:   ток D0.04 ÷100 (модели <55 кВт), вых.напряж D0.03 ЦЕЛЫЕ В. *)
IF eType = E_PumpType.VL THEN
    rCurrentActA := WORD_TO_REAL(wCurrentActual) / 100.0;
    rVoltageActV := WORD_TO_REAL(wVoltageActual);
ELSE
    rCurrentActA := WORD_TO_REAL(wCurrentActual) / 10.0;
    rVoltageActV := WORD_TO_REAL(wVoltageActual) / 10.0;
END_IF;

(* Температура: только у PUMP (F0.06). У VL в группе D0 температуры    *)
(* нет — оставляем 0. Автоопределение версии v1.2/v2.0 — только PUMP. *)
IF eType = E_PumpType.PUMP THEN
    xIsV12 := (wTemperature >= 100);   // ≥100 → v1.2 (регистр ×10)
    IF xIsV12 THEN
        iTemperatureC := WORD_TO_INT(wTemperature) / 10;   // v1.2: ×10 → °C
    ELSE
        iTemperatureC := WORD_TO_INT(wTemperature);         // v2.0: целые °C
    END_IF;
ELSE
    xIsV12        := FALSE;
    iTemperatureC := 0;
END_IF;

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
IF rTmp > 999.9 THEN rTmp := 999.9; END_IF;
(* ВНИМАНИЕ: блок ЗАПИСИ параметров (разгон/частоты/ток и т.п.) —      *)
(* PUMP-специфичный (адреса F-кодов, свои масштабы). Для VL параметры  *)
(* в P-группах (0xF0xx) с другими масштабами — запись уставок VL пока  *)
(* НЕ реализована (отдельная задача). Для VL используется только пуск/ *)
(* стоп + задание частоты (%) и мониторинг.                            *)
wOverCurrentTimeWrite := REAL_TO_WORD(rTmp * 10.0);

IF xOverVoltProtect_Set THEN wOverVoltProtectWrite := 1; ELSE wOverVoltProtectWrite := 0; END_IF;

iTmp := iOverheatLevel_Set;
IF iTmp < cMinOverheat THEN iTmp := cMinOverheat; ELSIF iTmp > cMaxOverheat THEN iTmp := cMaxOverheat; END_IF;
wOverheatLevelWrite := INT_TO_WORD(iTmp);

iTmp := iOverCurAcc_Set;
IF iTmp < 0 THEN iTmp := 0; ELSIF iTmp > 200 THEN iTmp := 200; END_IF;
wOverCurAccWrite := INT_TO_WORD(iTmp);
