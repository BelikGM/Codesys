(* ============================================================ *)
(* PRG_TimeCorrect — КОРРЕКЦИЯ УХОДА СИСТЕМНЫХ ЧАСОВ (RTC)      *)
(* ============================================================ *)
(* RTC контроллера уходит вперёд. Один раз в НОВЫЙ календарный    *)
(* день (как только сменился iCurrentDay) отводим RTC назад на    *)
(* iTimeDriftCorrSec секунд. Час/минута НЕ важны — сработает при   *)
(* первом же скане нового дня, даже если питание пропадало.       *)
(*                                                              *)
(* iLastCorrDay — RETAIN: переживает перезагрузку, поэтому после   *)
(* рестарта в тот же день коррекция повторно НЕ сработает          *)
(* (ровно 1 раз в сутки, а не на каждый ребут).                  *)
(*                                                              *)
(* Ставить время из приложения ПЛК МОЖНО — не защищённая          *)
(* операция. Вызывается в PLC_PRG ПОСЛЕ PRG_Fountain.             *)
(*                                                              *)
(* Сигнатура (подтверждена по библиотеке SysTimeRtc проекта):     *)
(*   SysTimeRtcSet(ulTimestamp : DWORD) : RTS_IEC_RESULT          *)
(*   (Seconds since 1.1.1970 00:00 UTC).                          *)
(* ============================================================ *)
PROGRAM PRG_TimeCorrect
VAR RETAIN
    iLastCorrDay : INT := -1;   // день месяца последней коррекции (RETAIN — 1 раз в сутки, переживает ребут)
END_VAR
VAR
    dwUtcRaw   : DWORD;
    rtcRes     : DWORD;
    xDoCorrect : BOOL;
END_VAR

(* --- Когда корректировать --- *)
xDoCorrect := FALSE;

(* Авто: раз в новый день, НАЧИНАЯ с часа iTimeDriftCorrHour.        *)
(* Минута НЕ проверяется (окно — весь день от этого часа), поэтому    *)
(* пропуск из-за пропадания питания не страшен: сработает на первом   *)
(* же скане после включения, если день новый и час уже наступил.      *)
(* ⚠️ Час нужен, чтобы вычитание секунд НЕ пересекало полночь: без    *)
(* него (чистый «новый день») коррекция в 00:00 откатывает время в    *)
(* 23:59 прошлого дня → день снова «новый» → бесконечный откат, часы   *)
(* залипают на полуночи. iTimeDriftCorrHour>=1 (0 не ставить!).        *)
IF xTimeDriftCorrEnable
   AND (iCurrentDay <> iLastCorrDay)
   AND (iCurrentHour >= iTimeDriftCorrHour) THEN
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

(* iTimeDriftCorrHour — час-якорь (по умолч. 3), с которого в новый    *)
(* день разрешена коррекция. НЕ ставить 0 (см. предупреждение выше).    *)
(* iTimeDriftCorrSec — на сколько секунд отводить назад (по умолч. 15;  *)
(* поставь 20, если измеренный уход ~20с/сутки).                        *)
