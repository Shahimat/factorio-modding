import { readFile } from 'node:fs/promises';
import { basename, dirname, join, relative } from 'node:path';

import {
  FACTORIO_VERSION_TRACKS,
  MOD_AUTHOR,
  MOD_NAME_MAX_LENGTH_EXCLUSIVE,
  MOD_NAME_MIN_LENGTH_EXCLUSIVE,
  MOD_NAME_PATTERN,
  MOD_NAME_PREFIX,
  MOD_TITLE_MAX_LENGTH,
  MOD_TITLE_PREFIX,
  VERSION_PART_MAX,
} from './conventions.ts';
import { error, warning, type Problem } from './problems.ts';

/** Поля info.json, на которые опираются инструменты. */
export interface InfoJson {
  readonly name: string;
  readonly version: string;
  readonly title: string;
  readonly author: string;
  readonly factorio_version: string;
  readonly dependencies: readonly string[];
}

const DEPENDENCY_PATTERN =
  /^(?:!|\(\?\)|\?|~)?\s*[A-Za-z0-9_ -]+?(?:\s*(?:<=|>=|=|<|>)\s*\d+\.\d+\.\d+)?$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function checkVersionString(
  value: string,
  file: string,
  field: string,
  parts: 2 | 3,
): Problem[] {
  const problems: Problem[] = [];
  const expected = parts === 3 ? /^\d+\.\d+\.\d+$/ : /^\d+\.\d+$/;
  if (!expected.test(value)) {
    problems.push(
      error(
        file,
        `${field}: ожидается ${parts} числа через точку, получено "${value}"`,
      ),
    );
    return problems;
  }
  for (const part of value.split('.')) {
    if (Number(part) > VERSION_PART_MAX) {
      problems.push(
        error(file, `${field}: число ${part} больше ${VERSION_PART_MAX}`),
      );
    }
  }
  return problems;
}

/**
 * Читает и проверяет info.json пакета мода. Возвращает распознанные поля и
 * список находок. `info` равен `null`, если файл нечитаем или в нём нет
 * обязательных полей — в этом случае дальнейшие проверки невозможны.
 */
export async function validateInfoJson(
  modDir: string,
  repoRoot: string,
): Promise<{ info: InfoJson | null; problems: Problem[] }> {
  const path = join(modDir, 'info.json');
  const file = relative(repoRoot, path);

  let raw: string;
  try {
    raw = await readFile(path, 'utf8');
  } catch {
    return {
      info: null,
      problems: [error(file, 'info.json отсутствует или нечитаем')],
    };
  }

  return checkInfoJsonText(raw, basename(modDir), file);
}

/**
 * Чистая проверка текста info.json. Отделена от чтения файла, чтобы
 * покрываться юнит-тестами без файловой системы — convention `testing`.
 *
 * `dirName` — имя каталога пакета, с ним сверяется поле `name`.
 */
export function checkInfoJsonText(
  raw: string,
  dirName: string,
  file: string,
): { info: InfoJson | null; problems: Problem[] } {
  const problems: Problem[] = [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (cause: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    problems.push(error(file, `info.json не парсится как JSON: ${detail}`));
    return { info: null, problems };
  }

  if (!isRecord(parsed)) {
    problems.push(error(file, 'info.json должен быть JSON-объектом'));
    return { info: null, problems };
  }

  const strings = new Map<string, string>();
  for (const field of ['name', 'version', 'title', 'author'] as const) {
    const value = parsed[field];
    if (typeof value !== 'string' || value.length === 0) {
      problems.push(
        error(file, `обязательное поле "${field}" отсутствует или не строка`),
      );
    } else {
      strings.set(field, value);
    }
  }

  const factorioVersion = parsed['factorio_version'];
  if (typeof factorioVersion !== 'string') {
    problems.push(
      error(
        file,
        'поле "factorio_version" обязательно: без него игра считает мод совместимым с 0.12',
      ),
    );
  } else {
    strings.set('factorio_version', factorioVersion);
  }

  const name = strings.get('name');
  if (name !== undefined) {
    if (!name.startsWith(MOD_NAME_PREFIX)) {
      problems.push(
        error(file, `"name" должен начинаться с "${MOD_NAME_PREFIX}"`),
      );
    }
    if (!MOD_NAME_PATTERN.test(name)) {
      problems.push(
        error(
          file,
          '"name": мод-портал принимает только латиницу, цифры, дефис и подчёркивание',
        ),
      );
    }
    if (
      name.length <= MOD_NAME_MIN_LENGTH_EXCLUSIVE ||
      name.length >= MOD_NAME_MAX_LENGTH_EXCLUSIVE
    ) {
      problems.push(
        error(
          file,
          `"name": длина ${name.length}, портал требует строго больше ${MOD_NAME_MIN_LENGTH_EXCLUSIVE} и строго меньше ${MOD_NAME_MAX_LENGTH_EXCLUSIVE}`,
        ),
      );
    }
    if (dirName !== name) {
      problems.push(
        error(
          file,
          `имя каталога "${dirName}" не совпадает с "name" = "${name}"`,
        ),
      );
    }
  }

  const version = strings.get('version');
  if (version !== undefined) {
    problems.push(...checkVersionString(version, file, '"version"', 3));
    if (version === '0.0.0') {
      problems.push(error(file, '"version" 0.0.0 недопустима'));
    }
  }

  const title = strings.get('title');
  if (title !== undefined) {
    if (!title.startsWith(MOD_TITLE_PREFIX)) {
      problems.push(
        error(file, `"title" должен начинаться с "${MOD_TITLE_PREFIX}"`),
      );
    }
    if (title.length > MOD_TITLE_MAX_LENGTH) {
      problems.push(
        error(
          file,
          `"title": длина ${title.length}, игра отклоняет длиннее ${MOD_TITLE_MAX_LENGTH}`,
        ),
      );
    }
  }

  const author = strings.get('author');
  if (author !== undefined && author !== MOD_AUTHOR) {
    problems.push(error(file, `"author" должен быть "${MOD_AUTHOR}"`));
  }

  const track = strings.get('factorio_version');
  if (track !== undefined) {
    problems.push(...checkVersionString(track, file, '"factorio_version"', 2));
    if (
      /^\d+\.\d+$/.test(track) &&
      !(FACTORIO_VERSION_TRACKS as readonly string[]).includes(track)
    ) {
      problems.push(
        warning(
          file,
          `"factorio_version" = "${track}" вне известных дорожек ${FACTORIO_VERSION_TRACKS.join(', ')}`,
        ),
      );
    }
  }

  const dependencies: string[] = [];
  const rawDeps = parsed['dependencies'];
  if (rawDeps !== undefined) {
    if (!Array.isArray(rawDeps)) {
      problems.push(error(file, '"dependencies" должно быть массивом строк'));
    } else {
      for (const dep of rawDeps) {
        if (typeof dep !== 'string') {
          problems.push(error(file, '"dependencies": элемент не строка'));
          continue;
        }
        if (!DEPENDENCY_PATTERN.test(dep.trim())) {
          problems.push(
            error(file, `"dependencies": не разбирается строка "${dep}"`),
          );
          continue;
        }
        dependencies.push(dep);
      }
    }
  }

  if (
    name === undefined ||
    version === undefined ||
    title === undefined ||
    author === undefined ||
    track === undefined
  ) {
    return { info: null, problems };
  }

  return {
    info: {
      name,
      version,
      title,
      author,
      factorio_version: track,
      dependencies,
    },
    problems,
  };
}

/** Путь к info.json пакета мода. */
export function infoJsonPath(modDir: string): string {
  return join(modDir, 'info.json');
}

/** Каталог, в котором лежит переданный info.json. */
export function modDirOf(infoPath: string): string {
  return dirname(infoPath);
}
