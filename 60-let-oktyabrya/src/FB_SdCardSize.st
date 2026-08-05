(* ============================================================ *)
(* FB_SdCardSize — АВТООПРЕДЕЛЕНИЕ ЁМКОСТИ ВСТАВЛЕННОЙ SD        *)
(* ============================================================ *)
(* Читает размер раздела прямо у ядра Linux — ОБЫЧНЫМ ЧТЕНИЕМ    *)
(* ФАЙЛА через CAA File. Никаких дополнительных библиотек, ничего *)
(* не надо разрешать в CODESYSControl.cfg, задача не блокируется. *)
(*                                                               *)
(*   /sys/block/mmcblk0/mmcblk0p1/size                            *)
(*                                                               *)
(* Этот псевдофайл содержит одно число ASCII — количество         *)
(* 512-байтных секторов раздела, например "31116288\n". Отсюда:   *)
(*                                                               *)
(*   ёмкость, МиБ = секторы / 2048     (512 Б * 2048 = 1 МиБ)     *)
(*                                                               *)
(* Дальше вычитаем 1 % на служебные структуры FAT32 (зарезерви-   *)
(* рованные секторы, две копии таблицы FAT, корневой каталог).    *)
(* Для 32 ГБ это ~300 МБ — с запасом, но нам важнее не завысить.  *)
(*                                                               *)
(* ⚠️ ОСОБЕННОСТЬ sysfs: такие файлы часто отдают размер 0, потому *)
(* FILE.GetSize по ним звать нельзя — читаем сразу в буфер на 32  *)
(* байта и смотрим, сколько байт реально пришло (FILE.Read.szSize).*)
(*                                                               *)
(* ⚠️ ЕСЛИ НЕ ПОЛУЧИЛОСЬ (файла нет, другое имя устройства, права) *)
(* — xValid остаётся FALSE, и PRG_AlarmLogSD берёт ёмкость из     *)
(* выпадающего списка на экране. То есть хуже, чем было, не будет  *)
(* никогда: автоопределение — это только удобство.                *)
(*                                                               *)
(* ⚠️ ИМЯ УСТРОЙСТВА. Путь берётся из GVL_Fountain.sSdCardSysPath. *)
(* На СПК карта монтируется в /mnt/ufs/media/mmcblk0p1, поэтому   *)
(* устройство — mmcblk0, раздел — mmcblk0p1. Если на конкретном   *)
(* контроллере SD окажется вторым устройством (mmcblk1p1) —       *)
(* поправить строку в GVL, перекомпиляция логики не нужна.        *)
(* Проверить на месте можно так: значение udiSectors * 512 должно  *)
(* примерно совпасть с объёмом карты.                             *)
(* ============================================================ *)
FUNCTION_BLOCK FB_SdCardSize
VAR_INPUT
    xTrigger : BOOL;          (* ФРОНТ — перечитать размер *)
    sSysPath : STRING(120);   (* '/sys/block/mmcblk0/mmcblk0p1/size' *)
END_VAR
VAR_OUTPUT
    xBusy         : BOOL;
    xValid        : BOOL;     (* ёмкость определена, можно доверять *)
    udiCapacityMB : UDINT;    (* полезная ёмкость, МиБ *)
    udiSectors    : UDINT;    (* сырое значение из sysfs, секторов по 512 Б *)
END_VAR
VAR CONSTANT
    (* разумные границы: меньше 64 МБ и больше 2 ТБ — точно мусор *)
    cMinMB : UDINT := 64;
    cMaxMB : UDINT := 2097152;
END_VAR
VAR
    iSt       : INT;
    xTrigPrev : BOOL;

    fbOpen  : FILE.Open;
    fbRead  : FILE.Read;
    fbClose : FILE.Close;
    hFile   : FILE.CAA.HANDLE;

    abBuf   : ARRAY[0..31] OF BYTE;
    udiRead : UDINT;

    i       : INT;
    b       : BYTE;
    udiSec  : UDINT;
    udiMB   : UDINT;
    iDigits : INT;
END_VAR


(* --- запуск по фронту --- *)
IF xTrigger AND NOT xTrigPrev AND iSt = 0 THEN
    iSt := 1;
END_IF;
xTrigPrev := xTrigger;

xBusy := (iSt <> 0);


CASE iSt OF

    0:  (* IDLE *)
        ;

    1:  (* OPEN на чтение *)
        fbOpen(xExecute := TRUE, sFileName := sSysPath, eFileMode := FILE.MODE.MREAD);
        IF fbOpen.xDone THEN
            hFile := fbOpen.hFile;
            fbOpen(xExecute := FALSE);
            iSt := 2;
        ELSIF fbOpen.xError THEN
            (* нет такого файла / нет доступа — молча уходим на список *)
            fbOpen(xExecute := FALSE);
            xValid := FALSE;
            iSt := 0;
        END_IF;

    2:  (* READ — sysfs отдаёт короткую ASCII-строку *)
        fbRead(xExecute := TRUE, hFile := hFile,
               pBuffer := ADR(abBuf), szBuffer := SIZEOF(abBuf));
        IF fbRead.xDone THEN
            udiRead := fbRead.szSize;
            fbRead(xExecute := FALSE);
            iSt := 3;
        ELSIF fbRead.xError THEN
            fbRead(xExecute := FALSE);
            udiRead := 0;
            iSt := 3;
        END_IF;

    3:  (* CLOSE — закрыть надо в любом случае *)
        fbClose(xExecute := TRUE, hFile := hFile);
        IF fbClose.xDone OR fbClose.xError THEN
            fbClose(xExecute := FALSE);
            iSt := 4;
        END_IF;

    4:  (* РАЗБОР ЧИСЛА *)
        udiSec  := 0;
        iDigits := 0;

        IF udiRead > SIZEOF(abBuf) THEN
            udiRead := SIZEOF(abBuf);
        END_IF;

        FOR i := 0 TO UDINT_TO_INT(udiRead) - 1 DO
            b := abBuf[i];
            IF b >= 48 AND b <= 57 THEN
                (* защита от переполнения UDINT: 429 496 728 * 10 + 9 *)
                (* ещё влезает, больше — уже нет                       *)
                IF udiSec <= 429496728 THEN
                    udiSec  := udiSec * 10 + BYTE_TO_UDINT(b) - 48;
                    iDigits := iDigits + 1;
                ELSE
                    iDigits := 0;      (* число неправдоподобно велико *)
                    EXIT;
                END_IF;
            ELSE
                EXIT;                  (* первый нецифровой символ = конец *)
            END_IF;
        END_FOR;

        IF iDigits > 0 AND udiSec > 0 THEN
            udiSectors := udiSec;
            (* секторы по 512 Б → МиБ, затем −1 % на структуры FAT32 *)
            udiMB := (udiSec / 2048) * 99 / 100;
            IF udiMB >= cMinMB AND udiMB <= cMaxMB THEN
                udiCapacityMB := udiMB;
                xValid := TRUE;
            ELSE
                xValid := FALSE;
            END_IF;
        ELSE
            xValid := FALSE;
        END_IF;

        iSt := 0;

END_CASE;
