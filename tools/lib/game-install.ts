/**
 * Поиск установленной игры для инструментов, которым она нужна:
 * `test:ingame`, `recolor-sprites`, `orbital-art`, и кредов портала из
 * Steam Cloud для стенда. Здесь — обращения к файловой системе, правила
 * выбора — чистые функции `ingame-config.ts`.
 */

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';

import {
  binaryCandidates,
  portalCredentials,
  resolveBinary,
  resolveReadData,
  steamCloudPlayerData,
  steamLibraryPaths,
  steamRoots,
  type PortalCredentials,
} from './ingame-config.ts';

/** Текст файла; нет файла или нет доступа — `undefined`. */
function readText(path: string): string | undefined {
  try {
    return readFileSync(path, 'utf8');
  } catch {
    return undefined;
  }
}

/** Библиотеки Steam из `libraryfolders.vdf` всех найденных клиентов Steam. */
function steamLibraries(): string[] {
  return steamRoots(homedir()).flatMap((root) => {
    const vdf = readText(`${root}/steamapps/libraryfolders.vdf`);
    return vdf === undefined ? [] : steamLibraryPaths(vdf);
  });
}

/** Бинарь игры; не найден — ошибка с подсказкой про `FACTORIO_BIN`. */
export function findGameBinary(): string {
  const binary = resolveBinary(
    binaryCandidates(homedir(), process.env['FACTORIO_BIN'], steamLibraries()),
    existsSync,
  );
  if (binary === undefined) {
    throw new Error('бинарь игры не найден — укажи путь в переменной FACTORIO_BIN');
  }
  return binary;
}

/** Значение `read-data` для бинаря; нет пакета `base` рядом — ошибка. */
export function gameReadData(binary: string): string {
  const readData = resolveReadData(dirname(binary), existsSync);
  if (readData === undefined) {
    throw new Error(`рядом с ${binary} нет каталога данных игры с пакетом base — проверь установку`);
  }
  return readData;
}

/**
 * Креды портала из первой Steam Cloud-копии `player-data.json`, где выполнен
 * вход. Значения уходят только вызывающему — ни в вывод, ни на диск.
 */
export function steamCloudCredentials(): PortalCredentials | undefined {
  for (const root of steamRoots(homedir())) {
    let userIds: string[];
    try {
      userIds = readdirSync(`${root}/userdata`).sort();
    } catch {
      continue;
    }
    for (const path of steamCloudPlayerData(root, userIds)) {
      const text = readText(path);
      const credentials = text === undefined ? undefined : portalCredentials(text);
      if (credentials !== undefined) return credentials;
    }
  }
  return undefined;
}

/** Абсолютный путь к каталогу `data/` установленной игры. */
export function gameDataDir(): string {
  const binary = findGameBinary();
  return resolve(dirname(binary), gameReadData(binary).replace('__PATH__executable__/', ''));
}
