PROGRAM PRG_PR200
(* === ДДЮТ: файл сохранён БЕЗ ИЗМЕНЕНИЙ, НЕ ВЫЗЫВАЕТСЯ === *)
(* Вызов закомментирован в PLC_PRG (ПР200 на объекте пока нет,   *)
(* может появиться). Чтобы вернуть — раскомментировать вызов     *)
(* PRG_PR200() в PLC_PRG и поднять канал slave в дереве Modbus.  *)
VAR
    rtrigApply  : R_TRIG;
    tonResetCmd : TON;
    xCmdSent    : BOOL;
END_VAR

GVL_Fountain.rPr200SuhoyHod_Cur := WORD_TO_REAL(GVL_Fountain.wPr200SuhoyHod_Net) / 10.0;
GVL_Fountain.rPr200Podpitka_Cur := WORD_TO_REAL(GVL_Fountain.wPr200Podpitka_Net) / 10.0;
GVL_Fountain.rPr200Norma_Cur    := WORD_TO_REAL(GVL_Fountain.wPr200Norma_Net)    / 10.0;
GVL_Fountain.rPr200Pereliv_Cur  := WORD_TO_REAL(GVL_Fountain.wPr200Pereliv_Net)  / 10.0;
GVL_Fountain.rPr200Delay_Cur    := WORD_TO_UDINT(GVL_Fountain.wPr200Delay_Net);
GVL_Fountain.rPr200LevelCm      := WORD_TO_REAL(GVL_Fountain.wPr200LevelRead)    / 10.0;

rtrigApply(CLK := GVL_Fountain.xApplyBtn);
IF rtrigApply.Q THEN
    GVL_Fountain.wPr200SuhoyHod_Write := REAL_TO_WORD(GVL_Fountain.rPr200SuhoyHod_New * 10.0);
    GVL_Fountain.wPr200Podpitka_Write := REAL_TO_WORD(GVL_Fountain.rPr200Podpitka_New * 10.0);
    GVL_Fountain.wPr200Norma_Write    := REAL_TO_WORD(GVL_Fountain.rPr200Norma_New    * 10.0);
    GVL_Fountain.wPr200Pereliv_Write  := REAL_TO_WORD(GVL_Fountain.rPr200Pereliv_New  * 10.0);
    GVL_Fountain.wPr200Delay_Write    := UDINT_TO_WORD(GVL_Fountain.rPr200Delay_New);
    GVL_Fountain.wPr200ApplyCmd       := WORD#1;
    xCmdSent                          := TRUE;
    GVL_Fountain.xApplyBtn            := FALSE;
END_IF;

tonResetCmd(IN := xCmdSent, PT := T#2S);
IF tonResetCmd.Q THEN
    GVL_Fountain.wPr200ApplyCmd := WORD#0;
    xCmdSent := FALSE;
    tonResetCmd(IN := FALSE);
END_IF;

GVL_Fountain.xPr200DoborActive := (GVL_Fountain.wPr200StatusRead AND WORD#1)  <> WORD#0;
GVL_Fountain.xPr200SlivActive  := (GVL_Fountain.wPr200StatusRead AND WORD#2)  <> WORD#0;
GVL_Fountain.xPr200PolivActive := (GVL_Fountain.wPr200StatusRead AND WORD#4)  <> WORD#0;
GVL_Fountain.xPr200ErrDobor    := (GVL_Fountain.wPr200StatusRead AND WORD#8)  <> WORD#0;
GVL_Fountain.xPr200ErrSliv     := (GVL_Fountain.wPr200StatusRead AND WORD#16) <> WORD#0;
GVL_Fountain.xPr200ErrPoliv    := (GVL_Fountain.wPr200StatusRead AND WORD#32) <> WORD#0;

GVL_Fountain.xPr200Online := NOT PR200_Slave.xError;
