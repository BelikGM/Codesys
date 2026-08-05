// Исполняемая модель ST-кода: FB_SdSpaceGuard, FB_SdCardSize,
// F_SdLogPath, F_SdLogMonthKey. Каждая функция повторяет ST построчно,
// включая целочисленное деление и семантику "0 = не наш файл".
//
// Запуск:  node sd_guard_model_test.js

const FAIL = [];
let OK = 0;
const J = (v) => JSON.stringify(v);

function check(name, got, want) {
  if (J(got) === J(want)) OK++;
  else FAIL.push(`${name.padEnd(58)} got=${J(got)} want=${J(want)}`);
}

const div = (a, b) => Math.floor(a / b); // целочисленное деление ST

// ============================================================
// F_SdLogPath
// ============================================================
function fSdLogPath(sDir, sPrefix, iYear, iMonth) {
  let sMM = String(iMonth);
  if (iMonth < 10) sMM = '0' + sMM;
  return sDir + '/' + sPrefix + sMM + '-' + String(iYear) + '.log';
}

// ============================================================
// F_SdLogMonthKey (побайтовая логика ST)
// ============================================================
function fSdLogMonthKey(sName, sPrefix) {
  const res = 0;
  const n = Buffer.from(sName, 'latin1');
  const p = Buffer.from(sPrefix, 'latin1');
  const lenPref = p.length;

  if (lenPref === 0 || n.length !== lenPref + 11) return res;

  for (let i = 0; i < lenPref; i++) {
    let bn = n[i], bp = p[i];
    if (bn >= 65 && bn <= 90) bn += 32;
    if (bp >= 65 && bp <= 90) bp += 32;
    if (bn !== bp) return res;
  }

  const ofs = lenPref;

  let iMM = 0;
  for (let i = ofs; i <= ofs + 1; i++) {
    const bn = n[i];
    if (bn < 48 || bn > 57) return res;
    iMM = iMM * 10 + bn - 48;
  }
  if (n[ofs + 2] !== 45) return res;            // '-'

  let iYY = 0;
  for (let i = ofs + 3; i <= ofs + 6; i++) {
    const bn = n[i];
    if (bn < 48 || bn > 57) return res;
    iYY = iYY * 10 + bn - 48;
  }
  if (n[ofs + 7] !== 46) return res;            // '.'

  let b = n[ofs + 8];  if (b >= 65 && b <= 90) b += 32;  if (b !== 108) return res;
  b = n[ofs + 9];      if (b >= 65 && b <= 90) b += 32;  if (b !== 111) return res;
  b = n[ofs + 10];     if (b >= 65 && b <= 90) b += 32;  if (b !== 103) return res;

  if (iMM < 1 || iMM > 12) return res;
  if (iYY < 2000 || iYY > 2199) return res;

  return iYY * 12 + iMM - 1;
}

// ============================================================
// FB_SdCardSize — разбор /sys/block/mmcblk0/mmcblk0p1/size
// ============================================================
const CAP_MIN_MB = 64;
const CAP_MAX_MB = 2097152;

function fbCardSize(sysContent) {
  const buf = Buffer.from(String(sysContent), 'latin1');
  const read = Math.min(buf.length, 32);     // буфер ФБ — 32 байта

  let sec = 0, digits = 0;
  for (let i = 0; i < read; i++) {
    const b = buf[i];
    if (b >= 48 && b <= 57) {
      if (sec <= 429496728) {
        sec = sec * 10 + b - 48;
        digits++;
      } else { digits = 0; break; }
    } else break;                            // первый нецифровой = конец
  }

  if (digits > 0 && sec > 0) {
    const mb = div(div(sec, 2048) * 99, 100);
    if (mb >= CAP_MIN_MB && mb <= CAP_MAX_MB) {
      return { valid: true, sectors: sec, capacityMB: mb };
    }
  }
  return { valid: false, sectors: digits > 0 ? sec : 0, capacityMB: 0 };
}

// ============================================================
// FB_SdSpaceGuard — один запуск
// ============================================================
const PREFIXES = ['alarms-', 'pump_changes-', 'setpoints-'];

function guardRun(filesIn, curYear, curMonth, opts) {
  const {
    usableMB = 29000, freeMinMB = 100, maxRounds = 24,
    readOnly = false, maxEntries = 500, force = false,
  } = opts;

  const files = new Map(Object.entries(filesIn));
  const deleted = [];
  const log = {
    deleted, fault: false, nothingToDelete: false, quotaStop: false,
    usedMB: 0, oursMB: 0, foreignMB: 0, quotaMB: 0, oldestMB: 0,
  };

  let rounds = 0;
  let forceRun = force;

  for (;;) {
    // --- состояние 11 ---
    if (curYear < 2000 || curYear > 2199 || curMonth < 1 || curMonth > 12) {
      log.fault = true;
      return log;
    }
    const curKey = curYear * 12 + curMonth - 1;

    // --- состояния 12..14: обход каталога ---
    let usedKB = 0, oursKB = 0, oldKey = 0, oldestKB = 0, foundOld = false;
    for (const [name, size] of files) {
      const entryKB = div(size, 1024) + 1;
      usedKB += entryKB;
      let key = 0;
      for (const pref of PREFIXES) if (key === 0) key = fSdLogMonthKey(name, pref);
      if (key > 0) {
        oursKB += entryKB;                       // квота — только наши файлы
        if (key < curKey) {                      // строго старше текущего
          if (!foundOld || key < oldKey) {
            oldKey = key; oldestKB = entryKB; foundOld = true;
          } else if (key === oldKey) {
            oldestKB += entryKB;
          }
        }
      }
    }

    // --- обход оборван по лимиту -> скан недостоверен ---
    if (files.size >= maxEntries) { log.fault = true; return log; }

    // --- состояние 20: квота ---
    const usedMB = div(usedKB, 1024);
    const oursMB = div(oursKB, 1024);
    const foreignMB = usedMB - oursMB;
    const quotaMB = usableMB > freeMinMB + foreignMB
      ? usableMB - freeMinMB - foreignMB : 0;
    log.usedMB = usedMB;
    log.oursMB = oursMB;
    log.foreignMB = foreignMB;
    log.quotaMB = quotaMB;
    log.oldestMB = div(oldestKB, 1024);

    const overQuota = oursMB > quotaMB;

    // --- состояние 30: решение ---
    if (forceRun || overQuota) {
      if (!foundOld) {
        log.nothingToDelete = true;
        log.quotaStop = overQuota;
        return log;
      }
    } else {
      log.nothingToDelete = false;
      log.quotaStop = false;
      return log;
    }

    // --- состояния 40..42: удаление трёх файлов старого месяца ---
    const oldYear = div(oldKey, 12);
    const oldMonth = (oldKey % 12) + 1;
    let delOk = 0;
    for (const pref of PREFIXES) {
      const fname = fSdLogPath('', pref, oldYear, oldMonth).slice(1);
      if (files.has(fname) && !readOnly) {
        files.delete(fname); deleted.push(fname); delOk++;
      }
    }

    rounds++;
    forceRun = false;                    // аварийный форс = ровно один месяц
    if (delOk === 0) { log.fault = true; return log; }
    if (rounds >= maxRounds) return log;
  }
}

const MB = 1024 * 1024;
const monthSet = (y, m, size = 50 * MB) => {
  const o = {};
  for (const p of PREFIXES) o[fSdLogPath('', p, y, m).slice(1)] = size;
  return o;
};

// ============================================================
// 1. ЕДИНИЦЫ ИЗМЕРЕНИЯ
// ============================================================
check('100 МБ в байтах', 100 * 1024 * 1024, 104857600);
check('100 МБ в КиБ', 100 * 1024, 102400);
check('32 ГБ в КиБ влезает в UDINT', 32 * 1024 * 1024 < 4294967295, true);
check('сумма в БАЙТАХ переполнила бы UDINT (потому копим в КиБ)',
  32 * 1024 ** 3 > 4294967295, true);

// ============================================================
// 2. АВТООПРЕДЕЛЕНИЕ ЁМКОСТИ ИЗ /sys (FB_SdCardSize)
// ============================================================
// типовые значения секторов (по 512 Б) для карт разных номиналов
const CARDS = [
  { gb: 2, sectors: 3862528 },
  { gb: 4, sectors: 7744512 },
  { gb: 8, sectors: 15564800 },
  { gb: 16, sectors: 31116288 },
  { gb: 32, sectors: 62324736 },
  { gb: 64, sectors: 124735488 },
  { gb: 128, sectors: 249737216 },
];
for (const c of CARDS) {
  const res = fbCardSize(c.sectors + '\n');
  const nominalMiB = Math.floor((c.gb * 1e9) / MB);
  check(`${c.gb} ГБ: ёмкость определена`, res.valid, true);
  check(`${c.gb} ГБ: не завышена (${res.capacityMB} <= ${nominalMiB} МиБ)`,
    res.capacityMB <= nominalMiB, true);
  check(`${c.gb} ГБ: не занижена сверх меры (>= 90 %)`,
    res.capacityMB >= nominalMiB * 0.9, true);
  check(`${c.gb} ГБ: журналам достаётся ${res.capacityMB - 100} МБ`,
    res.capacityMB - 100 > 0, true);
}
check('32 ГБ: журналам почти вся карта, а не 256 МБ',
  fbCardSize('62324736\n').capacityMB - 100 > 29000, true);

check('пустое содержимое -> невалидно', fbCardSize('').valid, false);
check('не число -> невалидно', fbCardSize('abc\n').valid, false);
check('ноль секторов -> невалидно', fbCardSize('0\n').valid, false);
check('пробел в начале -> невалидно (первый символ не цифра)',
  fbCardSize(' 31116288\n').valid, false);
check('без перевода строки -> валидно', fbCardSize('31116288').valid, true);
check('лишний хвост после числа отсекается',
  fbCardSize('31116288 mumble').sectors, 31116288);
check('слишком маленький раздел (16 МБ) -> невалидно',
  fbCardSize('32768\n').valid, false);
check('абсурдно большое число не переполняет UDINT',
  fbCardSize('99999999999999\n').valid, false);
check('32 байта буфера хватает на 128 ГБ',
  fbCardSize('249737216\n').sectors, 249737216);

// ============================================================
// 3. РАЗБОР ИМЁН ФАЙЛОВ
// ============================================================
check('alarms-08-2026.log', fSdLogMonthKey('alarms-08-2026.log', 'alarms-'), 2026 * 12 + 7);
check('pump_changes-01-2026.log',
  fSdLogMonthKey('pump_changes-01-2026.log', 'pump_changes-'), 2026 * 12 + 0);
check('верхний регистр ALARMS-08-2026.LOG',
  fSdLogMonthKey('ALARMS-08-2026.LOG', 'alarms-'), 2026 * 12 + 7);

const kDec25 = fSdLogMonthKey('alarms-12-2025.log', 'alarms-');
const kJan26 = fSdLogMonthKey('alarms-01-2026.log', 'alarms-');
check('12-2025 СТАРШЕ 01-2026 по ключу', kDec25 < kJan26, true);
check('а по строке было бы наоборот (ловушка)', '12-2025' < '01-2026', false);
check('ключи соседних месяцев отличаются на 1', kJan26 - kDec25, 1);

for (const bad of ['alarms.log', 'alarms-8-2026.log', 'alarms-08-26.log',
  'alarms-13-2026.log', 'alarms-00-2026.log', 'alarms-08-1999.log',
  'alarms-08-2200.log', 'alarms-08-2026.txt', 'alarms-08-2026.log.bak',
  'alarms-ab-2026.log', 'alarms-08_2026.log', 'alarms-082026.log',
  'config.log', 'recipe-08-2026.log', '', 'alarms-08-2026.lo',
  'x-alarms-08-2026.log']) {
  let key = 0;
  for (const pref of PREFIXES) if (key === 0) key = fSdLogMonthKey(bad, pref);
  check(`НЕ наш файл: ${J(bad)}`, key, 0);
}
check('alarms- не ловит pump_changes-',
  fSdLogMonthKey('pump_changes-08-2026.log', 'alarms-'), 0);

for (const y of [2000, 2025, 2026, 2099, 2199]) {
  for (let m = 1; m <= 12; m++) {
    const nm = fSdLogPath('/mnt/ufs/media/mmcblk0p1', 'pump_changes-', y, m).split('/').pop();
    check(`round-trip ${y}-${String(m).padStart(2, '0')}`,
      fSdLogMonthKey(nm, 'pump_changes-'), y * 12 + m - 1);
  }
}
check('длина пути влезает в STRING(80)',
  fSdLogPath('/mnt/ufs/media/mmcblk0p1', 'pump_changes-', 2026, 12).length <= 80, true);
check('собранный путь',
  fSdLogPath('/mnt/ufs/media/mmcblk0p1', 'alarms-', 2026, 8),
  '/mnt/ufs/media/mmcblk0p1/alarms-08-2026.log');

// ============================================================
// 4. КВОТА = ЁМКОСТЬ − РЕЗЕРВ − ЧУЖИЕ ФАЙЛЫ
// ============================================================
let r = guardRun({ ...monthSet(2026, 8, 1 * MB) }, 2026, 8, { usableMB: 29000 });
check('квота на 32 ГБ без чужих файлов', r.quotaMB, 28900);
r = guardRun({ 'chuzhoi.dat': 5000 * MB, ...monthSet(2026, 8, 1 * MB) },
  2026, 8, { usableMB: 29000 });
check('чужие 5000 МБ уменьшают квоту', r.quotaMB, 23900);
check('но сами чужие файлы не удаляются', r.deleted, []);
check('чужой объём показан отдельно', r.foreignMB, 5000);
r = guardRun({ 'ogromnyi.dat': 29000 * MB, ...monthSet(2026, 8, 1 * MB) },
  2026, 8, { usableMB: 29000 });
check('чужие съели всё -> квота 0', r.quotaMB, 0);

// ============================================================
// 5. ВЫБОР САМОГО СТАРОГО МЕСЯЦА + УДАЛЕНИЕ
// ============================================================
// 5.1 переход через год
let files = { ...monthSet(2026, 1), ...monthSet(2025, 11), ...monthSet(2025, 12) };
r = guardRun(files, 2026, 2, { usableMB: 400 });     // занято 450 > квоты 300
check('самый старый = 11-2025 (переход через год)', r.deleted.slice().sort(),
  ['alarms-11-2025.log', 'pump_changes-11-2025.log', 'setpoints-11-2025.log'].sort());
check('удалён ровно один месяц', r.deleted.length, 3);

// 5.2 текущий месяц не удаляется НИКОГДА
r = guardRun(monthSet(2026, 8, 400 * MB), 2026, 8, { usableMB: 356 });
check('текущий месяц не удалён', r.deleted, []);
check('поднят признак «удалять нечего»', r.nothingToDelete, true);
check('и запись на SD остановлена (последний рубеж)', r.quotaStop, true);

// 5.3 удаляем ровно столько месяцев, сколько нужно
files = {};
for (let m = 1; m <= 7; m++) Object.assign(files, monthSet(2026, m, 30 * MB));
r = guardRun(files, 2026, 8, { usableMB: 600 });   // 630 > квоты 500
check('удалено 2 месяца (630 -> 540 -> 450 <= 500)', r.deleted.length, 6);
check('удалены самые старые (01, 02)',
  [...new Set(r.deleted.map((n) => n.split('-')[1]))].sort(), ['01', '02']);

// 5.4 места вдоволь -> не трогаем ничего
r = guardRun(files, 2026, 8, { usableMB: 29000 });
check('на 32 ГБ 630 МБ журналов никого не тревожат', r.deleted, []);
check('запрета записи нет', r.quotaStop, false);

// 5.5 неполный месяц (уставок в январе не было)
files = { 'alarms-01-2026.log': 90 * MB, 'pump_changes-01-2026.log': 90 * MB,
  ...monthSet(2026, 5, 100 * MB) };
r = guardRun(files, 2026, 8, { usableMB: 500 });   // 480 > квоты 400
check('неполный месяц удаляется без ошибок', r.deleted.slice().sort(),
  ['alarms-01-2026.log', 'pump_changes-01-2026.log'].sort());

// 5.6 чужие файлы целы
files = { 'arhiv_proekta.zip': 900 * MB, 'config.log': 10 * MB,
  'alarms.log': 100 * MB, ...monthSet(2026, 1, 10 * MB),
  ...monthSet(2026, 8, 10 * MB) };
r = guardRun(files, 2026, 8, { usableMB: 29000 });
check('чужие файлы целы', r.deleted, []);
check('наш объём посчитан без чужих', r.oursMB, 60);
check('общий объём каталога — со всеми', r.usedMB, 1070);

// 5.7 ограничение раундов
files = {};
for (let y = 2024; y <= 2025; y++) {
  for (let m = 1; m <= 12; m++) Object.assign(files, monthSet(y, m, 100 * MB));
}
Object.assign(files, monthSet(2026, 8, 100 * MB));
r = guardRun(files, 2026, 8, { usableMB: 200 });
check('не больше 24 раундов за запуск', r.deleted.length <= 24 * 3, true);
check('текущий месяц уцелел', r.deleted.every((n) => !n.includes('08-2026')), true);

// 5.8 файл сломанного RTC (01-2000) уходит первым
files = { ...monthSet(2000, 1, 100 * MB), ...monthSet(2026, 3, 100 * MB) };
r = guardRun(files, 2026, 8, { usableMB: 500 });   // 600 > квоты 400
check('01-2000 уходит первым', r.deleted.slice().sort(),
  ['alarms-01-2000.log', 'pump_changes-01-2000.log', 'setpoints-01-2000.log'].sort());
r = guardRun(files, 2000, 1, { usableMB: 500 });
check('пока RTC сбит и 01-2000 текущий — не трогаем его',
  r.deleted.every((n) => !n.includes('01-2000')), true);

// 5.9 невалидное «сегодня»
r = guardRun(monthSet(2026, 1), 1970, 1, { usableMB: 101 });
check('невалидный год -> fault, удалений нет', [r.fault, r.deleted], [true, []]);

// 5.10 карта только для чтения
files = {};
for (let m = 1; m <= 6; m++) Object.assign(files, monthSet(2026, m, 40 * MB));
r = guardRun(files, 2026, 8, { usableMB: 200, readOnly: true });
check('на защищённой от записи карте ничего не удалено', r.deleted, []);
check('и прогон прерван аварией, а не 24 холостыми раундами', r.fault, true);

// 5.11 обход каталога оборван по лимиту
const tooMany = { ...monthSet(2025, 1, 100 * MB), ...monthSet(2026, 3, 100 * MB) };
for (let i = 0; i < 500; i++) tooMany[`junk${String(i).padStart(4, '0')}.dat`] = 1;
r = guardRun(tooMany, 2026, 8, { usableMB: 200 });
check('оборванный скан -> удалений нет', r.deleted, []);
check('оборванный скан -> авария', r.fault, true);

// ============================================================
// 6. АВАРИЙНЫЙ ФОРС: ЁМКОСТЬ ПРИНЯТА БОЛЬШЕ РЕАЛЬНОЙ
// ============================================================
// Автоопределение не сработало, в списке выбрали 32 ГБ, стоит карта 16 ГБ.
// Журналы доросли до 21 ГБ: квота (28 900) не превышена — сторож молчит.
// Но запись физически не проходит, PRG считает отказы и включает форс.
files = {};
for (let m = 1; m <= 10; m++) Object.assign(files, monthSet(2025, m, 700 * MB));
Object.assign(files, monthSet(2026, 8, 700 * MB));
r = guardRun(files, 2026, 8, { usableMB: 29000 });
check('без форса сторож молчит (квота не выбрана)', r.deleted, []);
r = guardRun(files, 2026, 8, { usableMB: 29000, force: true });
check('форс по отказам записи удаляет самый старый месяц', r.deleted.length, 3);
check('форс удалил именно 01-2025',
  r.deleted.every((n) => n.includes('01-2025')), true);

// ============================================================
// 7. КВОТА: САМОСНЯТИЕ ЗАПРЕТА ЗАПИСИ ЧЕРЕЗ МЕСЯЦ
// ============================================================
let bloated = monthSet(2026, 8, 134 * MB);         // 402 МБ
r = guardRun(bloated, 2026, 8, { usableMB: 356 }); // квота 256
check('август: запись остановлена', r.quotaStop, true);
Object.assign(bloated, monthSet(2026, 9, 1 * MB));
r = guardRun(bloated, 2026, 9, { usableMB: 356 });
check('сентябрь: раздутый август удалён автоматически', r.deleted.length, 3);
check('запрет записи снят сам, без человека', r.quotaStop, false);

// ============================================================
// 8. ОЦЕНКА ОБЪЁМА — округление в безопасную сторону
// ============================================================
r = guardRun({ 'alarms-01-2026.log': 1 }, 2026, 8, { usableMB: 356 });
check('файл 1 байт -> занято 0 МБ', r.oursMB, 0);

const many = {};
for (let i = 0; i < 3000; i++) many[`f${String(i).padStart(4, '0')}.dat`] = 1;
r = guardRun(many, 2026, 8, { usableMB: 356, maxEntries: 4000 });
check('3000 мелких чужих файлов -> 2 МБ общего, 0 МБ нашего',
  [r.usedMB, r.oursMB], [2, 0]);

files = { 'alarms-01-2026.log': 256 * MB - 1024, ...monthSet(2026, 8, 0) };
r = guardRun(files, 2026, 8, { usableMB: 356 });
check('ровно на квоте -> не чистим', r.deleted, []);
files = { 'alarms-01-2026.log': 257 * MB, ...monthSet(2026, 8, 0) };
r = guardRun(files, 2026, 8, { usableMB: 356 });
check('на 1 МБ выше квоты -> чистим', r.deleted.length, 1);

// ============================================================
console.log('='.repeat(70));
console.log(`ПРОЙДЕНО: ${OK}`);
if (FAIL.length) {
  console.log(`ПРОВАЛЕНО: ${FAIL.length}`);
  for (const f of FAIL) console.log('  ' + f);
  process.exitCode = 1;
} else {
  console.log('ПРОВАЛЕНО: 0 — все проверки прошли');
}
console.log('='.repeat(70));
