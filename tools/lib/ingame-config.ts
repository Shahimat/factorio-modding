/**
 * Подготовка `config.ini` для стенда тестов внутри игры.
 *
 * Зачем свой код поверх `factorio-test-cli`: CLI пишет в конфиг
 * `read-data=__PATH__executable__/../../data` — раскладку Linux-сборки, где
 * бинарь лежит в `bin/x64/`. В macOS-бандле исполняемый файл лежит в
 * `factorio.app/Contents/MacOS/`, а данные игры — в `factorio.app/Contents/data`,
 * то есть на уровень выше, и игра падает с «there is no package core».
 * Существующий конфиг CLI не переписывает (правит только `write-data`),
 * поэтому достаточно положить файл с верным путём до его запуска.
 *
 * Логика здесь чистая: проверка файловой системы приходит параметром, а
 * обход каталогов и запуск процесса живут в `tools/ingame-test.ts`.
 */

import { resolve } from 'node:path';

/** Как игре искать свои данные относительно исполняемого файла. */
export const READ_DATA_CANDIDATES = [
  '__PATH__executable__/../data',
  '__PATH__executable__/../../data',
] as const;

/** Проверка существования пути; в тестах подставляется своя. */
export type Exists = (path: string) => boolean;

/**
 * Значение `read-data` для конкретного бинаря игры. Раскладка определяется
 * фактом, а не платформой: в каталоге данных обязан лежать пакет `base`.
 * Ни один кандидат не подошёл — `undefined`, и это ошибка вызывающего.
 */
export function resolveReadData(
  binaryDir: string,
  exists: Exists,
): string | undefined {
  for (const candidate of READ_DATA_CANDIDATES) {
    const relative = candidate.replace('__PATH__executable__/', '');
    // Путь нормализуется: без этого `bin/x64/../../data` не совпал бы с
    // фактическим каталогом данных — на этом тест уже ловил дефект.
    if (exists(resolve(binaryDir, relative, 'base', 'info.json'))) return candidate;
  }
  return undefined;
}

/** Содержимое `config.ini`. `write-data` CLI потом поправит под себя сам. */
export function configIniText(readData: string, dataDir: string): string {
  return `; Сгенерирован npm run test:ingame — tools/ingame-test.ts.
; read-data подобран под раскладку установленной игры, см. tools/lib/ingame-config.ts.

[path]
read-data=${readData}
write-data=${dataDir}

[general]
locale=
`;
}

/** Значение `read-data` из существующего конфига; `undefined` — ключа нет. */
export function readDataOf(configIni: string): string | undefined {
  const match = /^read-data=(.*)$/m.exec(configIni);
  return match?.[1]?.trim();
}

/**
 * Нужно ли перезаписать конфиг. Да — если файла нет либо `read-data` в нём
 * указывает не туда: иначе прогон упадёт, а причина будет не видна.
 */
export function needsRewrite(
  existing: string | undefined,
  readData: string,
): boolean {
  if (existing === undefined) return true;
  return readDataOf(existing) !== readData;
}

/** Корни клиента Steam: macOS и Linux. */
export function steamRoots(home: string): string[] {
  return [`${home}/Library/Application Support/Steam`, `${home}/.local/share/Steam`];
}

/** Бинарь игры внутри библиотеки Steam — раскладки macOS и Linux. */
function steamLibraryBinaries(library: string): string[] {
  const game = `${library}/steamapps/common/Factorio`;
  return [`${game}/factorio.app/Contents/MacOS/factorio`, `${game}/bin/x64/factorio`];
}

/**
 * Пути библиотек Steam из `steamapps/libraryfolders.vdf`. Формат — KeyValues
 * Valve: нужны только строки `"path" "<каталог>"`, обратный слеш в значении
 * экранирован.
 */
export function steamLibraryPaths(vdf: string): string[] {
  const paths: string[] = [];
  for (const match of vdf.matchAll(/^\s*"path"\s+"((?:[^"\\]|\\.)*)"/gm)) {
    paths.push((match[1] as string).replace(/\\(.)/g, '$1'));
  }
  return paths;
}

/**
 * Кандидаты на путь к бинарю игры. Порядок: явное указание переменной
 * окружения, затем типовые установки, затем библиотеки Steam — игра может
 * стоять не в основной. Абсолютных путей с именем пользователя в
 * репозитории быть не может (convention `secrets`), поэтому домашний
 * каталог и библиотеки приходят параметрами, а не константами.
 */
export function binaryCandidates(
  home: string,
  fromEnv: string | undefined,
  steamLibraries: readonly string[] = [],
): string[] {
  const candidates = [
    `${home}/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio`,
    '/Applications/factorio.app/Contents/MacOS/factorio',
    `${home}/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio`,
    `${home}/.factorio/bin/x64/factorio`,
    '/usr/share/factorio/bin/x64/factorio',
  ];
  for (const library of steamLibraries) {
    for (const binary of steamLibraryBinaries(library)) {
      if (!candidates.includes(binary)) candidates.push(binary);
    }
  }
  return fromEnv === undefined || fromEnv === '' ? candidates : [fromEnv, ...candidates];
}

/** Первый существующий кандидат. */
export function resolveBinary(
  candidates: readonly string[],
  exists: Exists,
): string | undefined {
  return candidates.find((candidate) => exists(candidate));
}

/**
 * appID Factorio в Steam. Steam-сборка, запущенная напрямую, перезапускает
 * себя через Steam и теряет аргументы; файл `steam_appid.txt` с этим номером
 * в текущем каталоге процесса это отключает — так устроен Steamworks.
 * Поэтому стенд запускает игру из каталога данных, где лежит такой файл.
 */
export const STEAM_APP_ID = '427520';

/** Вход в аккаунт factorio.com, которым CLI качает моды с портала. */
export interface PortalCredentials {
  readonly username: string;
  readonly token: string;
}

/**
 * Копии `player-data.json` в Steam Cloud — по одной на пользователя Steam.
 * Steam-сборка под Linux держит файл только там, а CLI ищет его в каталоге
 * игры и в каталоге её данных.
 */
export function steamCloudPlayerData(steamRoot: string, userIds: readonly string[]): string[] {
  return userIds.map((id) => `${steamRoot}/userdata/${id}/${STEAM_APP_ID}/remote/player-data.json`);
}

/** Креды из текста `player-data.json`; нет входа или файл битый — `undefined`. */
export function portalCredentials(playerData: string): PortalCredentials | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(playerData);
  } catch {
    return undefined;
  }
  if (typeof parsed !== 'object' || parsed === null) return undefined;
  const fields = parsed as Record<string, unknown>;
  const username = fields['service-username'];
  const token = fields['service-token'];
  if (typeof username !== 'string' || username === '') return undefined;
  if (typeof token !== 'string' || token === '') return undefined;
  return { username, token };
}

/** Путь к конфигу из аргументов и аргументы без него. */
export interface ConfigArgument {
  readonly config: string | undefined;
  readonly rest: string[];
}

/**
 * Вынимает из аргументов `-c <путь>`, `--config <путь>` или
 * `--config=<путь>`. Обёртке путь нужен сама: по нему она находит каталог
 * данных, а CLI получает его обратно абсолютным, потому что запускается не
 * из корня репозитория. Аргументы после `--` — фильтры тестов, их не
 * трогаем.
 */
export function extractConfigArgument(args: readonly string[]): ConfigArgument {
  const rest: string[] = [];
  let config: string | undefined;
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i] as string;
    if (arg === '--') {
      rest.push(...args.slice(i));
      break;
    }
    if ((arg === '-c' || arg === '--config') && i + 1 < args.length) {
      config = args[i + 1];
      i += 1;
    } else if (arg.startsWith('--config=')) {
      config = arg.slice('--config='.length);
    } else {
      rest.push(arg);
    }
  }
  return { config, rest };
}

/** Включён ли режим с графикой: `-g`, `--graphics` или `-g` в связке флагов. */
export function isGraphicsRun(args: readonly string[]): boolean {
  for (const arg of args) {
    if (arg === '--') return false;
    if (arg === '--graphics') return true;
    if (/^-[A-Za-z]*g[A-Za-z]*$/.test(arg)) return true;
  }
  return false;
}

/**
 * Итог прогона по строке вывода CLI: `'passed'`, `'failed'` или `undefined`,
 * если строка не итоговая. В режиме с графикой CLI сам игру не закрывает и
 * ждёт, пока её закроют руками, поэтому обёртка ловит итог по этой строке.
 */
export function runOutcome(line: string): 'passed' | 'failed' | undefined {
  const match = /Test run finished: (\w+)/.exec(line);
  if (match === null) return undefined;
  return match[1] === 'passed' ? 'passed' : 'failed';
}
