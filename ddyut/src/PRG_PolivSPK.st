PROGRAM PRG_PolivSPK
(* === ДДЮТ: файл сохранён БЕЗ ИЗМЕНЕНИЙ, НЕ ВЫЗЫВАЕТСЯ === *)
(* На ДДЮТ нет ямы слива — резерв полива физически не нужен.    *)
(* Вызов закомментирован в PLC_PRG.                              *)
VAR
    rLevel : REAL;
    xLevGtSuhoy   : BOOL;
    xLevLePodpit  : BOOL;
    xLevGeNorma   : BOOL;
    xDobor : BOOL;
    tonErrDobor : TON;
    tonErrPoliv : TON;
    tErrDelay   : TIME;
    tonPereliv  : TON;
    tPerelivDelay : TIME;
    tonPrCommFilter : TON;
    tPrCommFilter   : TIME;
END_VAR

IF (cSlivRawMax - cSlivRawMin) > 0.0 THEN
    rLevel := (rSlivRaw - cSlivRawMin) / (cSlivRawMax - cSlivRawMin)
              * (cSlivCmMax - cSlivCmMin) + cSlivCmMin;
ELSE
    rLevel := 0.0;
END_IF;
IF rLevel < 0.0 THEN rLevel := 0.0; END_IF;
IF rLevel > 200.0 THEN rLevel := 200.0; END_IF;
rSlivLevelCm := rLevel;

tPrCommFilter := DINT_TO_TIME(INT_TO_DINT(iPr200CommFilterSec) * 1000);
tonPrCommFilter(IN := xPr200Online, PT := tPrCommFilter);
xPr200OnlineStable := tonPrCommFilter.Q;

IF xPr200OnlineStable THEN
    xSpkPolivMode := FALSE;
ELSIF NOT xSpkLevelSensorOk THEN
    xSpkPolivMode := FALSE;
END_IF;

IF NOT xSpkPolivMode THEN
    xSpkDO_Dobor := FALSE;
    xSpkDO_Poliv := TRUE;
    xSpkDoborOn  := FALSE;
    xSpkPolivOn  := FALSE;
    xSpkErrDobor := FALSE;
    xSpkErrPoliv := FALSE;
    xSpkErrPereliv := FALSE;
    xDobor       := FALSE;
    tonErrDobor(IN := FALSE, PT := T#1S);
    tonErrPoliv(IN := FALSE, PT := T#1S);
    tonPereliv(IN := FALSE, PT := T#1S);
    sSpkDoborStatus  := "Выкл";
    sSpkPolivStatus  := "Выкл";
    sSpkManualStatus := "Управление с ПР200";
    RETURN;
END_IF;

xLevGtSuhoy  := (rLevel > rPr200SuhoyHod_New);
xLevLePodpit := (rLevel <= rPr200Podpitka_New);
xLevGeNorma  := (rLevel >= rPr200Norma_New);

IF (xLevGtSuhoy AND NOT xSpkZapPoliv) OR xSpkRuchPoliv THEN
    xSpkDO_Poliv := FALSE;
ELSE
    xSpkDO_Poliv := TRUE;
END_IF;
xSpkPolivOn := (xSpkDO_Poliv = FALSE);

IF xLevLePodpit THEN
    xDobor := TRUE;
END_IF;
IF xLevGeNorma THEN
    xDobor := FALSE;
END_IF;
xSpkDO_Dobor := (xDobor AND NOT xSpkZapDobor) OR xSpkRuchDobor;
xSpkDoborOn := xSpkDO_Dobor;

tErrDelay := DINT_TO_TIME(INT_TO_DINT(iSpkErrDelaySec) * 1000);

tonErrDobor(IN := xSpkDO_Dobor AND NOT xSpkDI_Dobor, PT := tErrDelay);
xSpkErrDobor := tonErrDobor.Q;

tonErrPoliv(IN := (xSpkDO_Poliv = FALSE) AND (xSpkDI_Poliv = TRUE), PT := tErrDelay);
xSpkErrPoliv := tonErrPoliv.Q;

tPerelivDelay := DINT_TO_TIME(UDINT_TO_DINT(rPr200Delay_New) * 1000);
tonPereliv(IN := (rLevel >= rPr200Pereliv_New), PT := tPerelivDelay);
xSpkErrPereliv := tonPereliv.Q;

IF xSpkDoborOn THEN sSpkDoborStatus := "Вкл"; ELSE sSpkDoborStatus := "Выкл"; END_IF;
IF xSpkPolivOn THEN sSpkPolivStatus := "Вкл"; ELSE sSpkPolivStatus := "Выкл"; END_IF;

IF xSpkRuchDobor AND xSpkRuchPoliv THEN
    sSpkManualStatus := "Ручной: добор + полив";
ELSIF xSpkRuchDobor THEN
    sSpkManualStatus := "Ручной: добор";
ELSIF xSpkRuchPoliv THEN
    sSpkManualStatus := "Ручной: полив";
ELSE
    sSpkManualStatus := "Авто по уровню";
END_IF;
