(* ============================================================ *)
(* PRG_TimeCorrect — КОРРЕКЦИЯ УХОДА СИСТЕМНЫХ ЧАСОВ (RTC)      *)
(* ============================================================ *)
(* RTC контроллера уходит вперёд ~15с/сутки. Раз в сутки, в       *)
(* заданный час (iTimeDriftCorrHour, по умолч. 03:00), отводим    *)
(* RTC назад на iTimeDriftCorrSec секунд (по умолч. 15).          *)
(*                                                              *)
(* Ставить время из приложения ПЛК МОЖНО — это не защищённая      *)
(* операция (оператор так же правит RTC вручную с экрана).        *)
(*                                                              *)
(* Вызывается в PLC_PRG ПОСЛЕ PRG_Fountain — использует           *)
(* iCurrentHour/iCurrentMinute/iCurrentDay, посчитанные там.      *)
(*                                                              *)
(* ⚠️ ПРОВЕРЬ сигнатуру SysTimeRtcSet в Input Assistant проекта:  *)
(*   встречается два варианта:                                    *)
(*     rtcRes := SysTimeRtcSet(dwUtcRaw);                (1 арг)  *)
(*     rtcRes := SysTimeRtcSet(dwUtcRaw, pResult := rtcRes);      *)
(*   ниже стоит однопараметрный вариант — если библиотека требует *)
(*   pResult, допиши второй аргумент.                             *)
(* ============================================================ *)
PROGRAM PRG_TimeCorrect
VAR
    dwUtcRaw     : DWORD;
    rtcRes       : DWORD;
    iLastCorrDay : INT := -1;   // день месяца последней коррекции (защита "1 раз в сутки")
    xDoCorrect   : BOOL;
END_VAR

(* --- Когда корректировать --- *)
xDoCorrect := FALSE;

(* Авто: включено, наступил нужный час, минута 0, сегодня ещё не корректировали *)
IF xTimeDriftCorrEnable
   AND (iCurrentHour = iTimeDriftCorrHour)
   AND (iCurrentMinute = 0)
   AND (iCurrentDay <> iLastCorrDay) THEN
    xDoCorrect := TRUE;
END_IF;

(* Ручной триггер с экрана — срабатывает один раз *)
IF xTimeDriftCorrNow THEN
    xDoCorrect := TRUE;
END_IF;

(* --- Собственно коррекция --- *)
IF xDoCorrect THEN
    (* Читаем СЫРОЕ UTC (без смещения пояса!), вычитаем N секунд, пишем обратно *)
    dwUtcRaw := SysTimeRtcGet(pResult := rtcRes);
    dwUtcRaw := dwUtcRaw - INT_TO_DWORD(iTimeDriftCorrSec);
    rtcRes   := SysTimeRtcSet(dwUtcRaw);

    iLastCorrDay        := iCurrentDay;
    iTimeDriftCorrCount := iTimeDriftCorrCount + 1;
    sTimeDriftLast      := sCurrentDateStr;   // дата последней коррекции для экрана
    xTimeDriftCorrNow   := FALSE;             // гасим ручной триггер
END_IF;
