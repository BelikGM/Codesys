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

    E_PumpType.VL:
        (* Коды из регистра 0x8000 EMD-VL/VH (десятичные) *)
        iCode := WORD_TO_INT(wCode);
        CASE iCode OF
            0:   F_FaultCodeToText := "Нет ошибок";
            1:   F_FaultCodeToText := "Ошибка модуля";
            2:   F_FaultCodeToText := "Перегруз по току при разгоне";
            3:   F_FaultCodeToText := "Перегруз по току при торможении";
            4:   F_FaultCodeToText := "Перегруз по току на пост. скорости";
            5:   F_FaultCodeToText := "Перенапряжение при разгоне";
            6:   F_FaultCodeToText := "Перенапряжение при торможении";
            7:   F_FaultCodeToText := "Перенапряжение на пост. скорости";
            8:   F_FaultCodeToText := "Перегрузка тормозного резистора";
            9:   F_FaultCodeToText := "Низкое напряжение питания";
            10:  F_FaultCodeToText := "Перегрузка ПЧ";
            11:  F_FaultCodeToText := "Перегрузка двигателя";
            12:  F_FaultCodeToText := "Обрыв фазы питания";
            13:  F_FaultCodeToText := "Обрыв фазы мотора";
            14:  F_FaultCodeToText := "Перегрев IGBT-модуля";
            15:  F_FaultCodeToText := "Внешний аварийный сигнал";
            16:  F_FaultCodeToText := "Ошибка подключения (Modbus)";
            18:  F_FaultCodeToText := "Неисправность платы управления";
            19:  F_FaultCodeToText := "Ошибка автонастройки двигателя";
            20:  F_FaultCodeToText := "Неисправность энкодера";
            21:  F_FaultCodeToText := "Ошибка чтения/записи параметров";
            22:  F_FaultCodeToText := "Неисправность ПЧ";
            23:  F_FaultCodeToText := "Короткое замыкание на землю";
            26:  F_FaultCodeToText := "Достигнуто время работы (RUN)";
            29:  F_FaultCodeToText := "Достигнуто время во вкл. состоянии";
            30:  F_FaultCodeToText := "Работа двигателя вхолостую";
            31:  F_FaultCodeToText := "Обрыв датчика ОС ПИД";
            42:  F_FaultCodeToText := "Рассогласование скорости";
            43:  F_FaultCodeToText := "Переразгон двигателя";
            90:  F_FaultCodeToText := "Неверное разрешение энкодера";
            91:  F_FaultCodeToText := "Обрыв сигнала энкодера";
            92:  F_FaultCodeToText := "Ошибка начального положения";
            94:  F_FaultCodeToText := "Ошибка сигнала ОС по скорости";
        ELSE
            F_FaultCodeToText := WCONCAT("Ошибка VL код ", INT_TO_WSTRING(iCode));
        END_CASE;

END_CASE;
