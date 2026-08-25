# SETUP — что нужно установить и скачать для работы с проектом

Файл собран 25.08.2026 при первом развёртывании репозитория на новой
машине. Проверено фактически: что лежит в репозитории, что установлено
на ПК, какие библиотеки и устройства требует код.

---

## 0. ГЛАВНОЕ: чего в репозитории НЕТ

Репозиторий `BelikGM/Codesys` содержит **только текст программ** (`.st`)
и документацию (`.md`) — 60 файлов, ни одного файла проекта CODESYS.

**Отсутствует (и не восстанавливается из репозитория):**

| Чего нет | Почему это критично |
|---|---|
| `*.project` — сам файл проекта CODESYS | Без него нечего открывать, компилировать и грузить |
| Дерево устройств (Device tree) | Контроллер, Modbus COM1/COM2, МВ110, МУ110, EMD_PUMP_1/2/3 |
| Modbus I/O Mapping | Привязка `wMV110_Inputs`, `wMU110_Outputs`, регистров ПЧ |
| Визуализация (экраны) | `docs/SCREENS.md` — это ОПИСАНИЕ экранов, а не сами экраны |
| Конфигурация задач (Task configuration) | MainTask, период цикла |
| Менеджер библиотек с версиями | CAA File, SysTimeRtc, OwenVisuDialogs |

**Вывод:** собрать рабочий проект «с нуля» только из этого репозитория
нельзя. Нужен исходный `.project` (или архив `.projectarchive`) с
машины, где проект писался. Репозиторий — это версионируемая копия
кода POU для правок и ревью, а не поставка проекта.

**Первое действие:** найти на старой машине файл проекта и положить
рядом. Либо выгрузить архивом из CODESYS:
`Файл → Архив проекта → Сохранить/отправить архив` (`.projectarchive`
тянет с собой библиотеки и описания устройств).

---

## 1. Состояние этой машины (проверено 25.08.2026)

| Компонент | Статус |
|---|---|
| Git 2.55.0.windows.3 | ✅ установлен |
| Node.js v24.19.0 | ✅ установлен |
| Тест модели SD-сторожа | ✅ 165/165 (`node 60-let-oktyabrya/docs/sd_guard_model_test.js`) |
| **CODESYS V3.5** | ❌ **не установлен** |
| **Таргет-файлы ОВЕН** | ❌ нет |
| **Библиотеки ОВЕН** | ❌ нет |
| **Драйвер USB для СПК** | ❌ нет |
| **Конфигуратор М110** | ❌ нет |

Проверено перебором `C:\Program Files*` и веток реестра Uninstall —
ничего от CODESYS / ОВЕН на машине нет. Ставить всё с нуля.

---

## 2. ЖЕЛЕЗО И ВЕРСИИ

| Параметр | Значение |
|---|---|
| Контроллер | **ОВЕН СПК107 [М01]** (семейство СПК1хх [М01]) |
| Прошивка | **2.4** (последняя в линейке — 2.4.0923.1000) |
| Среда | **CODESYS V3.5 SP17 Patch 3** |
| Таргет | **OwenTargets-3.5.17.3x** |

Подтверждается и кодом: каталог приложения `app.spk1xxm01`, путь SD
`/mnt/ufs/media/mmcblk0p1/`, тип дескриптора `FILE.CAA.HANDLE`.

⚠️ Контроллеры с рантаймом SP17 Patch 3 **откатить на более старую
прошивку нельзя**. Версию таргета брать под прошивку 2.4, а не «самую
новую из принципа».

---

## 3. ЧТО СКАЧАТЬ — все ссылки

### 3.1 Среда программирования (обязательно)

| Файл | Размер | Ссылка |
|---|---|---|
| **CODESYS V3.5 SP17 Patch 3** — наша версия | ~2 ГБ | https://ftp.owen.ru/CoDeSys3/01_CODESYS/CODESYS_3.5_SP17_Patch3.zip |
| CODESYS Installer 2.6.0.0 (менеджер пакетов) | 171 МБ | https://ftp.owen.ru/CoDeSys3/01_CODESYS/CODESYS%20Installer%202.6.0.0.exe |
| CODESYS Gateway V3.5 SP5 Patch5 (если шлюз не встал со средой) | — | https://ftp.owen.ru/CoDeSys3/01_CODESYS/CODESYS%20Gateway%20V3.5SP5Patch5%20Setup.zip |

Каталог целиком: https://ftp.owen.ru/CoDeSys3/01_CODESYS/

### 3.2 Таргет-файлы ОВЕН (обязательно)

Без таргета контроллера СПК не будет в списке устройств. Наша линейка —
SP17; всё, что ниже 3.5.17.x, к СПК107 [М01] с прошивкой 2.4 не
относится и приведено только для полноты каталога.

| Файл | Дата | Для чего | Ссылка |
|---|---|---|---|
| **OwenTargets-3.5.17.36.package** | 16.02.2026 | самый свежий в линейке SP17 | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.17.36.package |
| OwenTargets-3.5.17.35.package | 14.03.2025 | предыдущий | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.17.35.package |
| OwenTargets-3.5.17.34.package | 29.10.2024 | — | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.17.34.package |
| OwenTargets-3.5.17.33.package | 13.06.2024 | — | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.17.33.package |
| OwenTargets-3.5.17.32.package | 07.12.2023 | — | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.17.32.package |
| **OwenTargets-3.5.17.31.package** | 19.05.2022 | базовый для СПК1хх [М01] | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.17.31.package |
| OwenTargets-3.5.16.32.package | 21.06.2021 | SP16 — не наш | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.16.32.package |
| OwenTargets-3.5.14.30-10.package | 18.03.2021 | SP14 — не наш | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.14.30-10.package |
| OwenTargets-3.5.11.50-14.package | 02.07.2019 | SP11 P5 — не наш | https://ftp.owen.ru/CoDeSys3/03_Targets/OwenTargets-3.5.11.50-14.package |

Каталог целиком (рядом лежат `.txt` с составом каждого пакета):
https://ftp.owen.ru/CoDeSys3/03_Targets/

⚠️ Ставить нужно тот таргет, с которым проект собирался в прошлый раз —
версию видно в свойствах устройства в самом проекте. Если поставить
более новый, при открытии среда предложит обновить дерево устройств,
а это тянет пересборку и лишние риски на объекте.

### 3.3 Библиотеки ОВЕН (нужны для визуализации проекта)

Проект использует диалоги ОВЕН — в `ddyut/docs/SCREENS.md` прямо
упомянут элемент `LoginOnlyPassWithKeysOwen` (экран пароля).

| Файл | Ссылка |
|---|---|
| **OwenVisuDialogs_v3.5.17.3.library** (для SP17 P3) | https://ftp.owen.ru/CoDeSys3/04_Library/05_3.5.11.5/02_Libraries/OwenVisuDialogs_v3.5.17.3.library |
| OwenVisuDialogs_v3.5.16.3.library (для SP16) | https://ftp.owen.ru/CoDeSys3/04_Library/05_3.5.11.5/02_Libraries/OwenVisuDialogs_v3.5.16.3.library |
| OwenVisuDialogs_v3.5.14.3.library (для SP14) | https://ftp.owen.ru/CoDeSys3/04_Library/05_3.5.11.5/02_Libraries/OwenVisuDialogs_v3.5.14.3.library |
| OwenVisuTools_v3.5.17.21.library (доп. виджеты) | https://ftp.owen.ru/CoDeSys3/04_Library/05_3.5.11.5/02_Libraries/OwenVisuTools_v3.5.17.21.library |

Каталог всех библиотек (там же OwenStringUtils, OwenCommunication,
OwenVendorProtocols, OwenAppTools):
https://ftp.owen.ru/CoDeSys3/04_Library/05_3.5.11.5/02_Libraries/

### 3.4 Драйвер USB для связи с СПК (обязательно при подключении по USB)

| Файл | Ссылка |
|---|---|
| **SPK_USB_Driver_1.2.90.exe** (20.03.2026) | https://ftp.owen.ru/CoDeSys3/06_SPK_USB_Driver/SPK_USB_Driver_1.2.90.exe |
| USB_Driver_v.1.5.102.zip (старый) | https://ftp.owen.ru/CoDeSys3/06_SPK_USB_Driver/USB_Driver_v.1.5.102.zip |

Каталог: https://ftp.owen.ru/CoDeSys3/06_SPK_USB_Driver/

### 3.5 Прошивки (скачать, но НЕ шить без необходимости)

| Устройство | Ссылка на каталог |
|---|---|
| **СПК1хх [М01]** — последняя 2.4.0923.1000 (411 МБ, 30.11.2022) | https://ftp.owen.ru/CoDeSys3/10_Firmware/SPK1xx_M01/ |
| СПК1хх (старый) | https://ftp.owen.ru/CoDeSys3/10_Firmware/SPK1xx/ |
| Все прошивки | https://ftp.owen.ru/CoDeSys3/10_Firmware/ |

На объекте стоит прошивка **2.4** — под неё и подобран таргет SP17.
Прошивку трогать **только** если версии таргета и прошивки разошлись и
CODESYS отказывается логиниться. Это операция с риском окирпичивания —
на объекте её не делают «на всякий случай».

### 3.6 Модули Мх110 (МВ110-16Д, МУ110-16Р)

| Что | Ссылка |
|---|---|
| Драйверы Мх110 для дерева CODESYS `Mx110Drivers_v3.5.4.12.package` | https://ftp.owen.ru/CoDeSys3/05_MX110/Mx110Drivers_v3.5.4.12.package |
| Описание Мх110 в CODESYS (PDF) | https://ftp.owen.ru/CoDeSys3/05_MX110/Mx110_2015.05.22.pdf |
| Каталог | https://ftp.owen.ru/CoDeSys3/05_MX110/ |
| **Конфигуратор М110** (задать адрес/скорость модулям) | https://owen.ru/soft |
| Owen Configurator (универсальный) | https://owen.ru/product/owen_configurator |
| РП «Конфигуратор М110» (PDF) | https://owen.ru/uploads/167/rp_konfigurator_m110_1-ru-57090-1.1.pdf |
| РЭ МВ110-16Д / 16ДН (PDF) | https://owen.ru/uploads/171/re_mv110-16d_dn__m01__1-ru-34143-1.14.pdf |

⚠️ Пакет `Mx110Drivers` собран под CODESYS 3.5.4 и на SP17 может не
встать. Это не блокирует работу: в проекте модули опрашиваются как
**обычные Modbus-slave**, вся привязка сделана через одно слово
`wMV110_Inputs` / `wMU110_Outputs` (см. `GVL.st`, блоки 4 и 5).
Драйвер — удобство, а не обязательность.

### 3.7 Преобразователи частоты ELHART EMD-PUMP (COM2, адреса 41/42/43)

| Что | Ссылка |
|---|---|
| Страница серии EMD-PUMP (паспорт, РЭ, быстрый старт) | https://elhart.ru/drive_technology/pump_frequency_converters/emd-pump.html |
| Руководство по эксплуатации (PDF, зеркало) | https://ftp.totalkip.ru/report.local/re/RE_elhart_7747.pdf |
| Обзор серий EMD-MINI / EMD-PUMP | https://docplayer.com/149459409-Chastotnye-preobrazovateli-elhart-serii-emd-mini-i-emd-pump.html |

Карта регистров нужна, чтобы читать `PRG_Pumps.st`:
`0x0069` MaxFreq, `0x006A` MinFreq, `0x006B` AccTime, `0x006C` DecTime,
`0x0076` F1.18 (замок параметров), `0x00D1` номин. напряжение,
`0x00D2` номин. ток, `0x0199` / `0x01A7` / `0x01A8` защита по току,
`0x019B` защита по перенапряжению, `0x0320` F800, `0x0325` перегрев.

### 3.8 Документация ОВЕН по CODESYS (рекомендуется)

Каталог: https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/

| Документ | Ссылка |
|---|---|
| **Первый старт CODESYS V3.5 (v3.0, 15.07.2026)** | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_FirstStart_v3.0.pdf |
| **Modbus в CODESYS V3.5 (v3.2)** | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_Modbus_v3.2.pdf |
| **Визуализация (v3.0, 25.06.2025)** | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_Visu_v3.0.pdf |
| Таргет-файлы: установка (v3.5) | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_Targets_v3.5.pdf |
| OwenVisuDialogs (v3.0) | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_OwenVisuDialogs_v3.0.pdf |
| OwenVisuTools (v3.0) | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_OwenVisuTools_v3.0.pdf |
| Архивация (запись на SD) v3.1 | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_Archives_v3.1.pdf |
| FAQ (v3.7, 26.02.2026) | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_Faq_v3.7.pdf |
| История версий | https://ftp.owen.ru/CoDeSys3/11_Documentation/03_3.5.11.5/CDSv3.5_VersionsHistory.pdf |

Старый комплект по СПК (много скриншотов, по смыслу актуален):
https://ftp.owen.ru/CoDeSys3/11_Documentation/01_SPK/

- Первый старт СПК: https://ftp.owen.ru/CoDeSys3/11_Documentation/01_SPK/SPK_First_start_v.1.0.pdf
- Modbus СПК: https://ftp.owen.ru/CoDeSys3/11_Documentation/01_SPK/SPK_Modbus_v.1.1.pdf
- Визуализация СПК: https://ftp.owen.ru/CoDeSys3/11_Documentation/01_SPK/SPK_Visu_v.1.2.pdf
- Системное время СПК: https://ftp.owen.ru/CoDeSys3/11_Documentation/01_SPK/SPK_SystemTime_v.1.1.pdf
- Архивы СПК: https://ftp.owen.ru/CoDeSys3/11_Documentation/01_SPK/SPK_Archives_v.1.0.pdf

### 3.9 Прочее

| Что | Ссылка |
|---|---|
| Общая страница ПО CODESYS V3 у ОВЕН | https://owen.ru/product/codesys_v3/software |
| Корень FTP ОВЕН по CODESYS 3 | https://ftp.owen.ru/CoDeSys3/ |
| Примеры программ | https://ftp.owen.ru/CoDeSys3/21_Examples/ |
| WinSCP (забрать журналы с SD по сети) | https://winscp.net/eng/download.php |
| Форум ОВЕН, ветка по СПК (FAQ, примеры) | https://owen.ru/forum/showthread.php?t=15530 |

---

## 4. Порядок установки (один раз на машину)

1. Распаковать `CODESYS_3.5_SP17_Patch3.zip` → запустить `setup*.exe`
   **от имени администратора**. Язык интерфейса меняется потом:
   `Tools → Options → International Settings`.
2. Перезагрузить ПК (ставится служба CODESYS Gateway).
3. Запустить CODESYS. Меню **`Tools` (Инструменты) → `CODESYS Installer`**
   (в старых версиях среды пункт называется **`Package Manager`**).
4. Нажать **`Install File…`** и указать `OwenTargets-3.5.17.36.package`.
   Согласиться на перезапуск среды.
5. Установить драйвер `SPK_USB_Driver_1.2.90.exe`.
6. Библиотеки ОВЕН: **`Tools → Library Repository → Install…`**, указать
   `OwenVisuDialogs_v3.5.17.3.library`.
7. Проверка: `Файл → Новый проект → Стандартный проект` — в списке
   устройств должен появиться **СПК1хх [М01]**.
   Появился — среда готова. Пустой проект после проверки не сохранять.

---

## 5. Что должно быть в дереве проекта CODESYS

Восстановлено по коду — понадобится при сверке или пересборке.

```
Device (СПК107 [М01])
├── PLC Logic
│   └── Application
│       ├── Менеджер библиотек
│       │     Standard, Util
│       │     CAA File            ← ОБЯЗАТЕЛЬНО (журналы на SD)
│       │     SysTimeRtc          ← ОБЯЗАТЕЛЬНО (SysTimeRtcGet/Set/ConvertUtcToDate)
│       │     OwenVisuDialogs     ← экраны пароля
│       ├── GVL, GVL_Fountain     (списки глобальных переменных)
│       ├── PLC_PRG               (вызывает всё остальное)
│       ├── PRG_IO, PRG_Fountain, PRG_Pumps, PRG_Errors,
│       │   PRG_TimeCorrect, PRG_AlarmLogSD, PRG_IO_Write
│       ├── FB_*, F_*             (ФБ и функции)
│       ├── Конфигурация задач → MainTask → PLC_PRG
│       └── Менеджер визуализации + экраны
├── Modbus_COM  (COM1, 9600 8N1)
│   └── Modbus_Master_COM_Port
│       ├── МВ110-16Д   адрес 1   → wMV110_Inputs (WORD), xMV110_Error
│       └── МУ110-16Р   адрес 2   → wMU110_Outputs, wMU110_OutputsRead, xMU110_Error
└── Modbus_COM_2 (COM2, 38400)
    └── Modbus_Master_COM_Port
        ├── EMD_PUMP_1  адрес 41
        ├── EMD_PUMP_2  адрес 42
        └── EMD_PUMP_3  адрес 43   ← только «60 Лет Октября»
```

**Насосы-шоу по объектам.** На «60 Лет Октября» их **три**
(`cPumpCount := 3`, адреса 41/42/43), на ДДЮТ — **два**
(`cPumpCount := 2`, адреса 41/42). Тип у всех — `E_PumpType.PUMP`.

`EMD_PUMP_3` есть в дереве «60 Лет Октября» и используется в коде
явно: `PRG_Pumps.st`, блок 4а, строки 354 и 379 —
`EMD_PUMP_3.xError`. Имя устройства в дереве должно совпадать точно,
иначе файл не скомпилируется.

У ДДЮТ дополнительно лежат `PRG_PR200.st` и `PRG_PolivSPK.st` —
физически в проекте есть, но вызовы в `PLC_PRG.st` закомментированы.

---

## 6. Правила правки .st из этого репозитория

Из `ddyut/docs/LOGIC.md` — грабли, найденные на реальном железе:

- Файлы `.st` здесь — это содержимое окна **«Реализация»** редактора
  CODESYS. Строку `END_PROGRAM` / `END_FUNCTION_BLOCK` в него
  **не вставлять**: среда добавляет границу сама.
- Литералы WSTRING — **двойные** кавычки `"текст"`. Одинарные дают
  STRING и ошибку компиляции.
- Вложенные комментарии `(* (* *) *)` ломают компиляцию.
- `REAL_TO_INT` / `REAL_TO_UDINT` **округляют**, а не отбрасывают.
- `WCONCAT` / `CONCAT` возвращают ~255 символов независимо от размера
  переменной. Растущий лог одной строкой невозможен — только массив
  коротких строк.
- `CASE TRUE OF` недопустимо: метка CASE требует целочисленный литерал.

---

## 7. Чек-лист «можно работать»

- [ ] Найден и получен исходный `.project` / `.projectarchive`
- [ ] Установлен CODESYS V3.5 SP17 Patch 3
- [ ] Установлен таргет-пакет ОВЕН, СПК виден в списке устройств
- [ ] Установлен драйвер USB для СПК
- [ ] Установлена OwenVisuDialogs
- [ ] Установлен Конфигуратор М110 (для адресов модулей)
- [ ] Скачаны РЭ на EMD-PUMP, МВ110-16Д, МУ110-16Р
- [ ] Проект открывается и компилируется без ошибок (F11)
- [ ] `node 60-let-oktyabrya/docs/sd_guard_model_test.js` → 165/165
