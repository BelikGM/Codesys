(* ============================================================ *)
(* GVL — Глобальные переменные проекта ДДЮТ                     *)
(* (на основе Fontan_V1 / Саки Пруд)                            *)
(*                                                              *)
(* ШИНА Modbus RTU / RS-485:                                   *)
(*   COM1 (Modbus_COM), 9600/8/N/1:                            *)
(*     Адрес 1  — МВ110-16Д   (16 дискретных входов DI1..DI11) *)
(*     Адрес 2  — МУ110-16Р   (16 дискретных выходов DO1..DO16)*)
(*     Аналогового модуля МВ110-8А на ДДЮТ НЕТ.                *)
(*   COM2 (Modbus_COM_2):                                       *)
(*     Адрес 41 — ELHART EMD-PUMP 1 (насос фонтана, индекс 1)  *)
(*     Адрес 42 — ELHART EMD-PUMP 2 (насос фонтана, индекс 2)  *)
(*   === ДДЮТ:ИЗМЕНЕНО === Насосы COM2 — это насосы фонтана    *)
(*   (клапаны/форсунки), НЕ фильтрационные, как было в Саки.    *)
(*   Признак работы фильтрации приходит отдельно на DI5.        *)
(* ============================================================ *)

(* ============================================================ *)
(* КОНСТАНТЫ СИСТЕМЫ                                            *)
(* ============================================================ *)
VAR_GLOBAL CONSTANT
    cPumpCount   : INT  := 2;        // количество насосов (2 × EMD-PUMP)
    cDI_Count    : INT  := 16;       // дискретных входов МВ110
    cDO_Count    : INT  := 16;       // дискретных выходов МУ110
    cMaxFreq     : REAL := 50.0;     // максимальная частота, Гц
    cMinFreq     : REAL := 0.0;      // минимальная частота, Гц
    cMinTime     : REAL := 0.1;      // мин. время разгона/торможения, с
    cMaxTime     : REAL := 6000.0;   // макс. время разгона/торможения, с
    cMaxCurrent  : REAL := 999.9;    // потолок номинального тока, А
    cMaxVoltage  : REAL := 500.0;    // потолок номинального напряжения, В
    cMaxOverheat : INT  := 150;      // потолок уровня перегрева, °C
    cMinOverheat : INT  := 40;       // минимум уровня перегрева, °C
END_VAR


(* ============================================================ *)
(* RETAIN-переменные (хранятся при отключении питания)         *)
(* ============================================================ *)
VAR_GLOBAL RETAIN
    (* Тип каждого ПЧ. Оба насоса — EMD-PUMP.                   *)
    (* ВНИМАНИЕ: изменение требует Reset cold контроллера.      *)
    ePumpType : ARRAY[1..cPumpCount] OF E_PumpType :=
        [E_PumpType.PUMP, E_PumpType.PUMP];

    (* === ДДЮТ:ИЗМЕНЕНО (round 7, ФИНАЛЬНАЯ СХЕМА) — ЖУРНАЛ ПЧ === *)
    (* Та же схема сдвига, что у журнала фонтана (см. подробный комментарий  *)
    (* в GVL_Fountain.st) — позиция 1 всегда самая свежая запись, при новой  *)
    (* записи всё сдвигается на 1 вниз, самая старая (позиция 30) выпадает.  *)
    (* Размер: 30 записей (как настроено), длина ячейки 65 (полное время     *)
    (* ДД.ММ.ГГ ЧЧ:ММ:СС + номер ПЧ + название параметра + два REAL-значения *)
    (* — уже было впритык на 65, оставлен без изменений по твоей настройке,  *)
    (* но следи, не обрезаются ли самые длинные названия типа                *)
    (* "Огр.тока.разг" — если увидишь обрыв текста, увеличь до 80-90).       *)
    aPumpLog       : ARRAY[1..30] OF WSTRING(65);
    iPumpLogCount  : INT;   // сколько записей реально заполнено (0..30)

    (* Флаг "задержка ошибки 0x02C0 уже записана в ПЧ" — RETAIN *)
    xErrDelayWritten : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    (* Флаг "параметр дисплея Fout (регистр 0) уже записан" — RETAIN *)
    xDispParamWritten : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];
END_VAR


(* ============================================================ *)
(* ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ                                        *)
(* ============================================================ *)
VAR_GLOBAL

    (* ========================================================= *)
    (* БЛОК 1: СОСТОЯНИЕ СИСТЕМЫ                                 *)
    (* ========================================================= *)
    xSystemState     : BOOL := TRUE;
    sSystemStateText : WSTRING(20);
    iErrors          : INT  := 0;
    iWorkCount       : INT  := 0;
    iStopCount       : INT  := 0;
    xAnyAlarm        : BOOL := FALSE;
    iErrorsPumps     : INT  := 0;
    iErrorsModules   : INT  := 0;
    iErrorsFountain  : INT  := 0;

    (* ========================================================= *)
    (* БЛОК 2: НАВИГАЦИЯ И ИНТЕРФЕЙС HMI                         *)
    (* ========================================================= *)
    xMenuOpen      : BOOL := TRUE;
    iCurrentScreen : INT  := 1;
    iSelPump       : INT  := 1;

    (* ========================================================= *)
    (* БЛОК 3: РЕЖИМ ОТЛАДКИ RS-485                              *)
    (* ========================================================= *)
    xDebugModeAll      : BOOL := FALSE;
    xDebugModeAll_Prev : BOOL := FALSE;

    xDebugModePump      : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];
    xDebugModePump_Prev : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    xApplyParamsAll  : BOOL := FALSE;
    xApplyParamsPump : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    (* ========================================================= *)
    (* ТРИГГЕРЫ ЧТЕНИЯ/ЗАПИСИ (конфигуратор-стиль)               *)
    (* ========================================================= *)
    xReadAllPump  : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];
    xReadAllAsk   : BOOL := FALSE;

    xWriteAllPump : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];
    xWriteAllAsk  : BOOL := FALSE;
    xWriteAllConfirm : BOOL := FALSE;

    xWr_AccTime      : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x006B
    xWr_DecTime      : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x006C
    xWr_MaxFreq      : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x0069
    xWr_MinFreq      : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x006A
    xWr_MotorCurrent : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x00D2
    xWr_MotorVoltage : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x00D1
    xWr_OverCurLevel : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x01A7
    xWr_OverCurTime  : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x01A8
    xWr_OverVoltProt : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x019B
    xWr_Overheat     : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x0325
    xWr_OverCurAcc   : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x0199

    xWr_UnlockF800   : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x0320
    xWr_Sources      : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)]; // 0x0065/0x0066

    xWritePending    : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];
    xWaitStopForWrite : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    (* === ДДЮТ:УДАЛИТЬ ===                                       *)
    (* Раньше использовался для запроса физической остановки      *)
    (* фильтр.насоса через лампы DO6/DO8 перед записью параметров. *)
    (* На ДДЮТ ПЧ COM2 — насосы фонтана, ламп-повторов DI4/DI5     *)
    (* больше нет (DO6/DO8 свободны). Остановка перед записью      *)
    (* параметров идёт командой Modbus (см. PRG_Pumps, источник    *)
    (* RS-485) — эта переменная физически нигде не читается,      *)
    (* оставлена только для истории. Можно удалить совсем.        *)
    xReqStopFiltrForWrite : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    xFactoryResetAll  : BOOL := FALSE;
    xFactoryResetPump : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    wCmdSourceWrite  : ARRAY[1..cPumpCount] OF WORD := [cPumpCount(WORD#1)];
    wFreqSourceWrite : ARRAY[1..cPumpCount] OF WORD := [cPumpCount(WORD#3)];

    (* ========================================================= *)
    (* БЛОК 4: МВ110-16Д — ДИСКРЕТНЫЕ ВХОДЫ                      *)
    (* ========================================================= *)
    wMV110_Inputs : WORD;
    xMV110_Error  : BOOL;
    xDI           : ARRAY[1..cDI_Count] OF BOOL;
    (* === ДДЮТ:ИЗМЕНЕНО === Используются DI1..DI11.             *)
    (* Карта DI — см. PRG_Fountain блок 2.                       *)

    (* ========================================================= *)
    (* БЛОК 5: МУ110-16Р — ДИСКРЕТНЫЕ ВЫХОДЫ                     *)
    (* ========================================================= *)
    (* === ДДЮТ:ИЗМЕНЕНО === Карта DO1..DO16 — см. PRG_Fountain   *)
    (* блок 17. DO1 свет, DO2 авария, DO9 насосы, DO11 добор,     *)
    (* DO13 сухой ход/разрешение (инверсия аварии добора),        *)
    (* DO14 альгицид, DO15 биопаг, DO16 pH. Остальные свободны.   *)
    xDO                : ARRAY[1..cDO_Count] OF BOOL := [cDO_Count(FALSE)];

    wMU110_Outputs     : WORD := 0;
    wMU110_OutputsRead : WORD;
    xMU110_Error       : BOOL;

    wMU110_SafeOutputs : WORD := 0;
    xMU110_WriteSafe   : BOOL := FALSE;

    (* ========================================================= *)
    (* БЛОК 6: НАСОСЫ — ЭКЗЕМПЛЯРЫ ФУНКЦИОНАЛЬНЫХ БЛОКОВ         *)
    (* ========================================================= *)
    Pump : ARRAY[1..cPumpCount] OF FB_Pump;

    (* ========================================================= *)
    (* БЛОК 7: НАСОСЫ — ЗАДАНИЕ ОПЕРАТОРА (_Set)                 *)
    (* ========================================================= *)
    xPumpRunCmd : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    rPumpFreqSetHz          : ARRAY[1..cPumpCount] OF REAL := [cPumpCount(40.0)];
    rPumpAccTime_Set        : ARRAY[1..cPumpCount] OF REAL := [10.0, 10.0];
    rPumpDecTime_Set        : ARRAY[1..cPumpCount] OF REAL := [10.0, 10.0];
    rPumpMaxFreq_Set        : ARRAY[1..cPumpCount] OF REAL := [cPumpCount(40.0)];
    rPumpMinFreq_Set        : ARRAY[1..cPumpCount] OF REAL := [cPumpCount(0.0)];
    rPumpMotorRatedCurrent_Set : ARRAY[1..cPumpCount] OF REAL := [cPumpCount(14.9)];
    rPumpMotorRatedVoltage_Set : ARRAY[1..cPumpCount] OF REAL := [cPumpCount(380.0)];
    rPumpOverCurrentLevel_A_Set : ARRAY[1..cPumpCount] OF REAL := [cPumpCount(26.1)];
    rPumpOverCurrentTime_Set    : ARRAY[1..cPumpCount] OF REAL := [cPumpCount(5.0)];
    xPumpOverVoltProtect_Set    : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(TRUE)];
    iPumpOverheatLevel_Set      : ARRAY[1..cPumpCount] OF INT  := [cPumpCount(95)];
    iPumpOverCurAcc_Set         : ARRAY[1..cPumpCount] OF INT  := [cPumpCount(150)];

    (* ========================================================= *)
    (* БЛОК 7а: ОТЛАДКА — групповые команды и флаги окон        *)
    (* ========================================================= *)
    xDbgRunAll  : BOOL;
    xDbgStopAll : BOOL;

    xAskApply   : BOOL := FALSE;
    xAskFactory : BOOL := FALSE;
	xAskDialogStopPch : BOOL := FALSE;

    (* ========================================================= *)
    (* БЛОК 8: НАСОСЫ — ДАННЫЕ ДЛЯ ОТОБРАЖЕНИЯ НА HMI            *)
    (* ========================================================= *)
    xPumpWork      : ARRAY[1..cPumpCount] OF BOOL;
    xPumpStop      : ARRAY[1..cPumpCount] OF BOOL;
    xPumpAlarm     : ARRAY[1..cPumpCount] OF BOOL;
    (* Версия прошивки ПЧ, определяется по температуре в FB_Pump *)
    xPumpIsV12     : ARRAY[1..cPumpCount] OF BOOL;          // TRUE=v1.2 (T×10), FALSE=v2.0
    sPumpFwVerText : ARRAY[1..cPumpCount] OF WSTRING(10);   // "v1.2"/"v2.0" для экрана
    xPumpReverse   : ARRAY[1..cPumpCount] OF BOOL;
    xPumpCommError : ARRAY[1..cPumpCount] OF BOOL;
    xPumpCommRaw   : ARRAY[1..cPumpCount] OF BOOL;
    tonPumpCommFilter : ARRAY[1..cPumpCount] OF TON;
    (* === ДДЮТ:ИСПРАВЛЕНО (баг мигания статуса) === Удержание   *)
    (* провалов xError перед фильтром TON — см. PRG_Pumps блок 4а *)
    tofPumpCommHold   : ARRAY[1..cPumpCount] OF TOF;

    sPumpState         : ARRAY[1..cPumpCount] OF WSTRING(50);
    sPumpFaultText     : ARRAY[1..cPumpCount] OF WSTRING(100);
    sPumpTypeText      : ARRAY[1..cPumpCount] OF WSTRING(20);
    sPumpFaultLastText : ARRAY[1..cPumpCount] OF WSTRING(100);
    sPumpFault2Text    : ARRAY[1..cPumpCount] OF WSTRING(100);
    sPumpFault3Text    : ARRAY[1..cPumpCount] OF WSTRING(100);
    sPumpFault4Text    : ARRAY[1..cPumpCount] OF WSTRING(100);

    rPumpFreqSetActHz : ARRAY[1..cPumpCount] OF REAL;
    rPumpFreqActHz    : ARRAY[1..cPumpCount] OF REAL;
    rPumpCurrentActA  : ARRAY[1..cPumpCount] OF REAL;
    rPumpSpeedActRpm  : ARRAY[1..cPumpCount] OF REAL;
    rPumpDcVoltageV   : ARRAY[1..cPumpCount] OF REAL;
    iPumpTemperatureC : ARRAY[1..cPumpCount] OF INT;
    rPumpVoltageActV  : ARRAY[1..cPumpCount] OF REAL;
    rPumpRuntimeHours : ARRAY[1..cPumpCount] OF REAL;

    dwPumpLampColor : ARRAY[1..cPumpCount] OF DWORD;

    rPumpAccTime_Disp            : ARRAY[1..cPumpCount] OF REAL;
    rPumpDecTime_Disp            : ARRAY[1..cPumpCount] OF REAL;
    rPumpMaxFreq_Disp            : ARRAY[1..cPumpCount] OF REAL;
    rPumpMinFreq_Disp            : ARRAY[1..cPumpCount] OF REAL;
    rPumpMotorRatedCurrent_Disp  : ARRAY[1..cPumpCount] OF REAL;
    rPumpMotorRatedVoltage_Disp  : ARRAY[1..cPumpCount] OF REAL;
    rPumpOverCurrentLevel_A_Disp : ARRAY[1..cPumpCount] OF REAL;
    rPumpOverCurrentTime_Disp    : ARRAY[1..cPumpCount] OF REAL;
    xPumpOverVoltProtect_Disp    : ARRAY[1..cPumpCount] OF BOOL;
    sPumpOverVoltProtect : ARRAY[1..cPumpCount] OF WSTRING(20);
    iPumpOverCurrentLevel_pct_Disp : ARRAY[1..cPumpCount] OF INT;
    iPumpOverheatLevel_Disp      : ARRAY[1..cPumpCount] OF INT;
    iPumpOverCurAcc_Disp         : ARRAY[1..cPumpCount] OF INT;

    (* ========================================================= *)
    (* БЛОК 9: НАСОСЫ — ЗАПИСЬ В ПЧ (Modbus WRITE)               *)
    (* ========================================================= *)
    wPumpCmd  : ARRAY[1..cPumpCount] OF WORD;
    wPumpFreq : ARRAY[1..cPumpCount] OF WORD;

    wPumpAccTimeWrite           : ARRAY[1..cPumpCount] OF WORD;
    wPumpDecTimeWrite           : ARRAY[1..cPumpCount] OF WORD;
    wPumpMaxFreqWrite           : ARRAY[1..cPumpCount] OF WORD;
    wPumpMinFreqWrite           : ARRAY[1..cPumpCount] OF WORD;
    wPumpMotorRatedCurrentWrite : ARRAY[1..cPumpCount] OF WORD;
    wPumpMotorRatedVoltageWrite : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverCurrentLevelWrite  : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverCurrentTimeWrite   : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverVoltProtectWrite   : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverheatLevelWrite     : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverCurAccWrite        : ARRAY[1..cPumpCount] OF WORD;

    wPumpDispParamWrite : ARRAY[1..cPumpCount] OF WORD := [cPumpCount(WORD#1)];

    wPumpRS_ErrDelayWrite : ARRAY[1..cPumpCount] OF WORD := [cPumpCount(WORD#5)];
    xWr_ErrDelayInit      : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

    wPumpExtSettingsUnlockWrite : ARRAY[1..cPumpCount] OF WORD;
    wPumpFactoryResetWrite      : ARRAY[1..cPumpCount] OF WORD := [cPumpCount(WORD#0)];

    (* ========================================================= *)
    (* БЛОК 10: НАСОСЫ — ЧТЕНИЕ ИЗ ПЧ (Modbus READ)             *)
    (* ========================================================= *)
    wPumpFreqSetRead     : ARRAY[1..cPumpCount] OF WORD;
    wPumpFreqActual      : ARRAY[1..cPumpCount] OF WORD;
    wPumpCurrentActual   : ARRAY[1..cPumpCount] OF WORD;
    wPumpSpeedActual     : ARRAY[1..cPumpCount] OF WORD;
    wPumpDcVoltage       : ARRAY[1..cPumpCount] OF WORD;
    wPumpTemperature     : ARRAY[1..cPumpCount] OF WORD;
    wPumpPidFeedback     : ARRAY[1..cPumpCount] OF WORD;
    wPumpRuntimeHoursRaw : ARRAY[1..cPumpCount] OF WORD;
    wPumpVoltageActual   : ARRAY[1..cPumpCount] OF WORD;

    wPumpFaultLast : ARRAY[1..cPumpCount] OF WORD;
    wPumpFault2    : ARRAY[1..cPumpCount] OF WORD;
    wPumpFault3    : ARRAY[1..cPumpCount] OF WORD;
    wPumpFault4    : ARRAY[1..cPumpCount] OF WORD;

    wPumpFaultReg : ARRAY[1..cPumpCount] OF WORD;
    wPumpStatus   : ARRAY[1..cPumpCount] OF WORD;
    wPumpStopState    : ARRAY[1..cPumpCount] OF WORD;
    xPumpFullyStopped : ARRAY[1..cPumpCount] OF BOOL;

    wPumpFreqPresetRead  : ARRAY[1..cPumpCount] OF WORD;
    rPumpFreqPresetHz : ARRAY[1..cPumpCount] OF REAL;
    wPumpFreqSourceRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpCmdSourceRead   : ARRAY[1..cPumpCount] OF WORD;
    wPumpStopKeyLockRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpReverseLockRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpMaxFreqRead     : ARRAY[1..cPumpCount] OF WORD;
    wPumpMinFreqRead     : ARRAY[1..cPumpCount] OF WORD;
    wPumpAccTimeRaw      : ARRAY[1..cPumpCount] OF WORD;
    wPumpDecTimeRaw      : ARRAY[1..cPumpCount] OF WORD;

    wPumpStartMethodRead        : ARRAY[1..cPumpCount] OF WORD;
    wPumpStopMethodRead         : ARRAY[1..cPumpCount] OF WORD;
    wPumpStartFreqRead          : ARRAY[1..cPumpCount] OF WORD;
    wPumpStopFreqRead           : ARRAY[1..cPumpCount] OF WORD;
    wPumpMotorRatedVoltageRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpMotorRatedCurrentRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpMotorNoLoadCurrentRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpMotorRatedSpeedRead    : ARRAY[1..cPumpCount] OF WORD;

    wPumpFIV_MinRead    : ARRAY[1..cPumpCount] OF WORD;
    wPumpFIV_MaxRead    : ARRAY[1..cPumpCount] OF WORD;
    wPumpFIV_FilterRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpFIC_MinRead    : ARRAY[1..cPumpCount] OF WORD;
    wPumpFIC_MaxRead    : ARRAY[1..cPumpCount] OF WORD;

    wPumpFOV_MinRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpFOV_MaxRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpFOC_MinRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpFOC_MaxRead : ARRAY[1..cPumpCount] OF WORD;

    wPumpAI_MinFreqRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpAI_MinDirRead   : ARRAY[1..cPumpCount] OF WORD;
    wPumpAI_MaxFreqRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpAI_MaxDirRead   : ARRAY[1..cPumpCount] OF WORD;
    wPumpAI_ReverseEnRead: ARRAY[1..cPumpCount] OF WORD;

    wPumpDI_FWD_Read : ARRAY[1..cPumpCount] OF WORD;
    wPumpDI_REV_Read : ARRAY[1..cPumpCount] OF WORD;
    wPumpDI_S1_Read  : ARRAY[1..cPumpCount] OF WORD;
    wPumpDI_S2_Read  : ARRAY[1..cPumpCount] OF WORD;
    wPumpDI_S3_Read  : ARRAY[1..cPumpCount] OF WORD;
    wPumpDI_S4_Read  : ARRAY[1..cPumpCount] OF WORD;
    wPumpDI_S5_Read  : ARRAY[1..cPumpCount] OF WORD;
    wPumpDI_S6_Read  : ARRAY[1..cPumpCount] OF WORD;

    wPumpDO_M01_Read   : ARRAY[1..cPumpCount] OF WORD;
    wPumpDO_M02_Read   : ARRAY[1..cPumpCount] OF WORD;
    wPumpDO_Relay_Read : ARRAY[1..cPumpCount] OF WORD;

    wPumpOverCurAccRead       : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverCurSteadyRead    : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverVoltProtectRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverCurReactionRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverCurrentLevelRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverCurrentTimeRead  : ARRAY[1..cPumpCount] OF WORD;
    wPumpOverheatLevelRead    : ARRAY[1..cPumpCount] OF WORD;

    wPumpRS_BaudRead      : ARRAY[1..cPumpCount] OF WORD;
    wPumpRS_FormatRead    : ARRAY[1..cPumpCount] OF WORD;
    wPumpRS_AddrRead      : ARRAY[1..cPumpCount] OF WORD;
    wPumpRS_ErrActionRead : ARRAY[1..cPumpCount] OF WORD;
    wPumpRS_ErrDelayRead  : ARRAY[1..cPumpCount] OF WORD;

    (* ========================================================= *)
    (* БЛОК 11: VISU DEBUG — ВЫБОР НАСОСА И ДИАЛОГИ              *)
    (* ========================================================= *)
    iDebugMode         : INT;
    iDebugPumpSelected : INT := 1;
    xDlgConfirmApply   : BOOL;
    xDlgConfirmFactory : BOOL;


(* ========================================================= *)
(* БЛОК 12: ЖУРНАЛ ИЗМЕНЕНИЙ ПАРАМЕТРОВ ПЧ *)
(* ========================================================= *)
xLogClear : BOOL := FALSE;
xAskClearLog : BOOL := FALSE;

rLog_AccTime_Prev : ARRAY[1..cPumpCount] OF REAL;
rLog_DecTime_Prev : ARRAY[1..cPumpCount] OF REAL;
rLog_MaxFreq_Prev : ARRAY[1..cPumpCount] OF REAL;
rLog_MinFreq_Prev : ARRAY[1..cPumpCount] OF REAL;
rLog_MotorCur_Prev : ARRAY[1..cPumpCount] OF REAL;
rLog_MotorVolt_Prev : ARRAY[1..cPumpCount] OF REAL;
rLog_OCLevel_Prev : ARRAY[1..cPumpCount] OF REAL;
rLog_OCTime_Prev : ARRAY[1..cPumpCount] OF REAL;
xLog_OVProt_Prev : ARRAY[1..cPumpCount] OF BOOL;
iLog_Overheat_Prev : ARRAY[1..cPumpCount] OF INT;
iLog_OCAcc_Prev : ARRAY[1..cPumpCount] OF INT;
xLog_Initialized : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];
rtrigReadAll_Prev : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];

xWr_DispParam : ARRAY[1..cPumpCount] OF BOOL := [cPumpCount(FALSE)];
END_VAR
