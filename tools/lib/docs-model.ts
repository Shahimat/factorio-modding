import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';

import { parse } from 'yaml';

import { REPO_ROOT } from './packages.ts';
import { error, type Problem } from './problems.ts';

export const DIRS = {
  entities: join(REPO_ROOT, 'docs', 'entities'),
  behaviors: join(REPO_ROOT, 'docs', 'behavior'),
  manuals: join(REPO_ROOT, 'docs', 'manuals'),
  conventions: join(REPO_ROOT, 'context', 'conventions'),
  modules: join(REPO_ROOT, 'context', 'modules'),
  views: join(REPO_ROOT, 'context', 'views'),
  specs: join(REPO_ROOT, 'specs'),
} as const;

export type YamlRecord = Record<string, unknown>;

export interface LoadedYaml {
  /** Имя файла без каталога. */
  readonly fileName: string;
  /** Путь относительно корня репозитория — для сообщений. */
  readonly file: string;
  readonly data: YamlRecord;
}

export function asRecord(value: unknown): YamlRecord | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as YamlRecord)
    : null;
}

export function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v) => typeof v === 'string') : [];
}

export function asString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

/** Читает все *.yml / *.yaml каталога. Непарсящиеся файлы — находка. */
export async function loadYamlDir(
  dir: string,
): Promise<{ items: LoadedYaml[]; problems: Problem[] }> {
  const problems: Problem[] = [];
  let names: string[];
  try {
    names = await readdir(dir);
  } catch {
    return { items: [], problems };
  }

  const items: LoadedYaml[] = [];
  for (const fileName of names.sort()) {
    if (!fileName.endsWith('.yml') && !fileName.endsWith('.yaml')) continue;
    const path = join(dir, fileName);
    const file = relative(REPO_ROOT, path);
    let parsed: unknown;
    try {
      parsed = parse(await readFile(path, 'utf8'));
    } catch (cause: unknown) {
      const detail = cause instanceof Error ? cause.message : String(cause);
      problems.push(error(file, `YAML не парсится: ${detail}`));
      continue;
    }
    const data = asRecord(parsed);
    if (data === null) {
      problems.push(error(file, 'ожидается YAML-объект на верхнем уровне'));
      continue;
    }
    items.push({ fileName, file, data });
  }
  return { items, problems };
}

/** Имена файлов каталога без расширения, отфильтрованные по суффиксу. */
export async function listBaseNames(
  dir: string,
  suffix: string,
): Promise<string[]> {
  try {
    const names = await readdir(dir);
    return names
      .filter((n) => n.endsWith(suffix) && !n.startsWith('.'))
      .map((n) => n.slice(0, -suffix.length))
      .sort();
  } catch {
    return [];
  }
}
