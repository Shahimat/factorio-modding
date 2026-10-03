import { readdir, readFile, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';

import { THUMBNAIL_SIZE } from './conventions.ts';

/** Корень репозитория: `tools/lib` → на два уровня вверх. */
export const REPO_ROOT = resolve(import.meta.dirname, '..', '..');

export const MODS_DIR = join(REPO_ROOT, 'mods');

/** Каталоги в `mods/`, которые содержат info.json. */
export async function listModDirs(): Promise<string[]> {
  let entries: string[];
  try {
    entries = await readdir(MODS_DIR);
  } catch {
    return [];
  }
  const found: string[] = [];
  for (const entry of entries.sort()) {
    if (entry.startsWith('.')) continue;
    const dir = join(MODS_DIR, entry);
    try {
      const info = await stat(join(dir, 'info.json'));
      if (info.isFile()) found.push(dir);
    } catch {
      // каталог без info.json модом не считается
    }
  }
  return found;
}

export async function fileExists(path: string): Promise<boolean> {
  try {
    const s = await stat(path);
    return s.isFile();
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
