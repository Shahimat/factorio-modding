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

/**
 * Кандидаты на путь к бинарю игры. Порядок: явное указание переменной
 * окружения, затем типовые установки. Абсолютных путей с именем пользователя
 * в репозитории быть не может (convention `secrets`), поэтому домашний
 * каталог приходит параметром, а не константой.
 */
export function binaryCandidates(
  home: string,
  fromEnv: string | undefined,
): string[] {
  const candidates = [
    `${home}/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio`,
    '/Applications/factorio.app/Contents/MacOS/factorio',
    `${home}/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio`,
    `${home}/.factorio/bin/x64/factorio`,
    '/usr/share/factorio/bin/x64/factorio',
  ];
  return fromEnv === undefined || fromEnv === '' ? candidates : [fromEnv, ...candidates];
}

/** Первый существующий кандидат. */
export function resolveBinary(
  candidates: readonly string[],
  exists: Exists,
): string | undefined {
  return candidates.find((candidate) => exists(candidate));
}
