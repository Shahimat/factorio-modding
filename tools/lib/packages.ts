import { readdir, readFile, stat } from 'node:fs/promises';
import { basename, isAbsolute, join, resolve } from 'node:path';

import { MOD_NAME_PREFIX, THUMBNAIL_SIZE } from './conventions.ts';

/** Корень репозитория: `tools/lib` → на два уровня вверх. */
export const REPO_ROOT = resolve(import.meta.dirname, '..', '..');

export const MODS_DIR = join(REPO_ROOT, 'mods');

/** Моды-щупы, convention `spec-program`, раздел «PoC». */
export const POC_DIR = join(REPO_ROOT, 'poc');

/** Корни, где может лежать Lua-код, исполняемый игрой. */
export const LUA_ROOTS = [MODS_DIR, POC_DIR] as const;

/** Каталоги внутри корня, которые содержат info.json. */
export async function listPackageDirs(root: string): Promise<string[]> {
  let entries: string[];
  try {
    entries = await readdir(root);
  } catch {
    return [];
  }
  const found: string[] = [];
  for (const entry of entries.sort()) {
    if (entry.startsWith('.')) continue;
    const dir = join(root, entry);
    try {
      const info = await stat(join(dir, 'info.json'));
      if (info.isFile()) found.push(dir);
    } catch {
      // каталог без info.json пакетом не считается
    }
  }
  return found;
}

/** Каталоги в `mods/`, которые содержат info.json. */
export async function listModDirs(): Promise<string[]> {
  return listPackageDirs(MODS_DIR);
}

/**
 * Каталоги-кандидаты для запрошенного имени, в порядке поиска: сначала имя
 * как есть, затем с приставкой `shm-`, и так по каждому корню. Чистая
 * функция — существование каталогов проверяет вызывающий.
 */
export function packageCandidatePaths(
  roots: readonly string[],
  requested: string,
): string[] {
  return roots.flatMap((root) => [
    join(root, requested),
    join(root, `${MOD_NAME_PREFIX}${requested}`),
  ]);
}

/** Каталоги, в которые обход файлов мода не заходит. */
export const WALK_SKIP_DIRS = ['node_modules', '.git', 'dist'] as const;

/**
 * Файлы с заданным суффиксом внутри каталога, рекурсивно. Скрытые записи и
 * `WALK_SKIP_DIRS` пропускаются. Нечитаемый подкаталог не роняет обход:
 * валидатор должен дойти до конца и выдать все находки сразу.
 */
export async function listFilesBySuffix(
  dir: string,
  suffix: string,
): Promise<string[]> {
  const found: string[] = [];

  const walk = async (current: string): Promise<void> => {
    let entries;
    try {
      entries = await readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue;
      const path = join(current, entry.name);
      if (entry.isDirectory()) {
        if ((WALK_SKIP_DIRS as readonly string[]).includes(entry.name)) continue;
        await walk(path);
      } else if (entry.name.endsWith(suffix)) {
        found.push(path);
      }
    }
  };

  await walk(dir);
  return found.sort();
}

/**
 * Сопоставляет запрошенное имя мода с именами каталогов в `mods/`. Приставку
 * `shm-` разрешено не писать: в командной строке `logistic-buildings` удобнее,
 * чем полное имя, а разночтений это не создаёт — приставка одна на все моды
 * (convention `mod-naming`).
 */
export function matchModName(
  names: readonly string[],
  requested: string,
): string | null {
  if (names.includes(requested)) return requested;
  const prefixed = `${MOD_NAME_PREFIX}${requested}`;
  return names.includes(prefixed) ? prefixed : null;
}

export interface ResolvedMods {
  readonly dirs: string[];
  /** Аргументы, которым не нашлось мода. */
  readonly unknown: string[];
}

/**
 * Разбирает аргументы командной строки в набор каталогов модов. Понимает
 * `--all`, имя мода с приставкой и без, а также путь — чтобы скрипт
 * `npm test -w shm-<mod>` мог передать `.` из своего каталога.
 */
export async function resolveModDirs(
  args: readonly string[],
): Promise<ResolvedMods> {
  const all = await listModDirs();
  if (args.includes('--all')) return { dirs: all, unknown: [] };

  const names = all.map((dir) => basename(dir));
  const dirs: string[] = [];
  const unknown: string[] = [];

  for (const arg of args) {
    if (arg.startsWith('.') || isAbsolute(arg)) {
      const dir = resolve(process.cwd(), arg);
      if (await fileExists(join(dir, 'info.json'))) {
        dirs.push(dir);
      } else {
        unknown.push(arg);
      }
      continue;
    }
    const matched = matchModName(names, arg);
    if (matched === null) {
      unknown.push(arg);
    } else {
      dirs.push(join(MODS_DIR, matched));
    }
  }

  return { dirs: [...new Set(dirs)], unknown };
}

export async function fileExists(path: string): Promise<boolean> {
  try {
    const s = await stat(path);
    return s.isFile();
  } catch {
    return false;
  }
}

export async function dirExists(path: string): Promise<boolean> {
  try {
    const s = await stat(path);
    return s.isDirectory();
  } catch {
    return false;
  }
}

/**
 * Размеры PNG из блока IHDR. Возвращает `null`, если файл не PNG или короче
 * заголовка. Без внешних зависимостей: ширина и высота лежат по фиксированным
 * смещениям 16 и 20.
 */
export async function readPngSize(
  path: string,
): Promise<{ width: number; height: number } | null> {
  let buffer: Buffer;
  try {
    buffer = await readFile(path);
  } catch {
    return null;
  }
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buffer.length < 24 || !buffer.subarray(0, 8).equals(signature)) {
    return null;
  }
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  };
}

export function isExpectedThumbnailSize(size: {
  width: number;
  height: number;
}): boolean {
  return size.width === THUMBNAIL_SIZE && size.height === THUMBNAIL_SIZE;
}
