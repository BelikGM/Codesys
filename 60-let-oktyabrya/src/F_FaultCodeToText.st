FUNCTION F_FaultCodeToText : WSTRING(100)
(* Без изменений относительно проекта ДДЮТ *)
VAR_INPUT
    eType    : E_PumpType;
    wCode    : WORD;
END_VAR
VAR
    wCleanCode : WORD;
    iCode      : INT;
END_VAR

CASE eType OF

    E_PumpType.PUMP:
        wCleanCode := wCode AND 16#7FFF;
        iCode := WORD_TO_INT(wCleanCode);

        CASE iCode OF
            0:  F_FaultCodeToText := "Нет ошибок";
            1:  F_FaultCodeToText := "OC0: Перегруз по току в режиме Стоп";
            2:  F_FaultCodeToText := "OC1: Перегруз по току при ускорении";
            3:  F_FaultCodeToText := "OC2: Перегруз по току при замедлении";
            4:  F_FaultCodeToText := "OC3: Перегруз по току в работе";
            5:  F_FaultCodeToText := "OU1: Перенапряжение при ускорении";
            6:  F_FaultCodeToText := "OU2: Перенапряжение при замедлении";
            7:  F_FaultCodeToText := "OU3: Перенапряжение в работе";
            9:  F_FaultCodeToText := "LU: Низкое напряжение питания";
            10: F_FaultCodeToText := "OL2: Перегрузка ПЧ";
            11: F_FaultCodeToText := "OL1: Перегрузка двигателя по току";
            14: F_FaultCodeToText := "OH: Перегрев ПЧ";
            15: F_FaultCodeToText := "EF: Аварийная остановка";
            16: F_FaultCodeToText := "CO: Ошибка коммуникации Modbus";
            20: F_FaultCodeToText := "Обрыв сигнала ОС ПИД";
            24: F_FaultCodeToText := "LP: Нижний уровень аварии ОС ПИД";
            27: F_FaultCodeToText := "HP: Верхний уровень аварии ОС ПИД";
            28: F_FaultCodeToText := "LL: Сухой ход";
            29: F_FaultCodeToText := "tE: Превышено время работы";
            31: F_FaultCodeToText := "Pr: Ошибка записи параметра";
        ELSE
            CASE iCode OF
                64: F_FaultCodeToText := "UC0: Внутр. ошибка в Стоп";
                65: F_FaultCodeToText := "UC1: Внутр. ошибка при ускорении";
                66: F_FaultCodeToText := "UC2: Внутр. ошибка при замедлении";
                67: F_FaultCodeToText := "UC3: Внутр. ошибка в работе";
                68: F_FaultCodeToText := "OC0: Перегруз по току в Стоп";
                69: F_FaultCodeToText := "OC1: Перегруз по току при ускорении";
                70: F_FaultCodeToText := "OC2: Перегруз по току при замедлении";
                71: F_FaultCodeToText := "OC3: Перегруз по току в работе";
                80: F_FaultCodeToText := "OU0: Перенапряжение в Стоп";
                81: F_FaultCodeToText := "OU1: Перенапряжение при ускорении";
                82: F_FaultCodeToText := "OU2: Перенапряжение при замедлении";
                83: F_FaultCodeToText := "OU3: Перенапряжение в работе";
                88: F_FaultCodeToText := "LU0: Низкое напряжение в Стоп";
                89: F_FaultCodeToText := "LU1: Низкое напряжение при ускорении";
                90: F_FaultCodeToText := "LU2: Низкое напряжение при замедлении";
                91: F_FaultCodeToText := "LU3: Низкое напряжение в работе";
                92: F_FaultCodeToText := "OL0: Перегрузка ПЧ в Стоп";
                93: F_FaultCodeToText := "OL1: Перегрузка ПЧ при ускорении";
                94: F_FaultCodeToText := "OL2: Перегрузка ПЧ при замедлении";
                95: F_FaultCodeToText := "OL3: Перегрузка ПЧ в работе";
                96: F_FaultCodeToText := "OT0: Перегрузка двиг. в Стоп";
                97: F_FaultCodeToText := "OT1: Перегрузка двиг. при ускорении";
                98: F_FaultCodeToText := "OT2: Перегрузка двиг. при замедлении";
                99: F_FaultCodeToText := "OT3: Перегрузка двиг. в работе";
                100: F_FaultCodeToText := "OH0: Перегрев ПЧ в Стоп";
                101: F_FaultCodeToText := "OH1: Перегрев ПЧ при ускорении";
                102: F_FaultCodeToText := "OH2: Перегрев ПЧ при замедлении";
                103: F_FaultCodeToText := "OH3: Перегрев ПЧ в работе";
                104: F_FaultCodeToText := "ES: Авар. остановка / обрыв фазы";
            ELSE
                F_FaultCodeToText := WCONCAT("Ошибка PUMP код ", INT_TO_WSTRING(iCode));
            END_CASE;
        END_CASE;

    E_PumpType.MINI:
        iCode := WORD_TO_INT(wCode);
        IF (iCode <= 63) OR ((iCode >= 88) AND (iCode <= 91)) THEN
            F_FaultCodeToText := "Нет ошибок";
        ELSE
            CASE iCode OF
                64: F_FaultCodeToText := "UC0: Внутр. ошибка в Стоп";
                65: F_FaultCodeToText := "UC1: Внутр. ошибка при ускорении";
                66: F_FaultCodeToText := "UC2: Внутр. ошибка при замедлении";
                67: F_FaultCodeToText := "UC3: Внутр. ошибка в работе";
                68: F_FaultCodeToText := "OC0: Перегруз по току в Стоп";
                69: F_FaultCodeToText := "OC1: Перегруз по току при ускорении";
                70: F_FaultCodeToText := "OC2: Перегруз по току при замедлении";
                71: F_FaultCodeToText := "OC3: Перегруз по току в работе";
                80: F_FaultCodeToText := "OU0: Перенапряжение в Стоп";
                81: F_FaultCodeToText := "OU1: Перенапряжение при ускорении";
                82: F_FaultCodeToText := "OU2: Перенапряжение при замедлении";
                83: F_FaultCodeToText := "OU3: Перенапряжение в работе";
                92: F_FaultCodeToText := "OL0: Перегрузка ПЧ в Стоп";
                93: F_FaultCodeToText := "OL1: Перегрузка ПЧ при ускорении";
                94: F_FaultCodeToText := "OL2: Перегрузка ПЧ при замедлении";
                95: F_FaultCodeToText := "OL3: Перегрузка ПЧ в работе";
                96: F_FaultCodeToText := "OT0: Перегрузка двиг. в Стоп";
                97: F_FaultCodeToText := "OT1: Перегрузка двиг. при ускорении";
                98: F_FaultCodeToText := "OT2: Перегрузка двиг. при замедлении";
                99: F_FaultCodeToText := "OT3: Перегрузка двиг. в работе";
                100: F_FaultCodeToText := "OH0: Перегрев ПЧ в Стоп";
                101: F_FaultCodeToText := "OH1: Перегрев ПЧ при ускорении";
                102: F_FaultCodeToText := "OH2: Перегрев ПЧ при замедлении";
                103: F_FaultCodeToText := "OH3: Перегрев ПЧ в работе";
                104: F_FaultCodeToText := "ES: Авар. остановка / обрыв фазы";
            ELSE
                F_FaultCodeToText := WCONCAT("Ошибка MINI код ", INT_TO_WSTRING(iCode));
            END_CASE;
        END_IF;

END_CASE;
