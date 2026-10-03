import { readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';

import {
  CHANGELOG_KNOWN_CATEGORIES,
  CHANGELOG_SEPARATOR_LENGTH,
  VERSION_PART_MAX,
} from './conventions.ts';
import { error, warning, type Problem } from './problems.ts';

export interface ChangelogResult {
  /** Версии в порядке появления в файле; первая — верхняя секция. */
  readonly versions: readonly string[];
  readonly problems: readonly Problem[];
  /** `false`, если файла нет. */
  readonly present: boolean;
}

const SEPARATOR = /^-+$/;
const VERSION_LINE = /^Version: (.*)$/;
const DATE_LINE = /^Date: (.*)$/;
const CATEGORY_LINE = /^ {2}(\S.*)$/;
const ENTRY_LINE = /^ {4}- (.*)$/;
const CONTINUATION_LINE = /^ {6}(\S.*)$/;

function checkVersion(value: string, file: string, line: number): Problem[] {
  const problems: Problem[] = [];
  if (!/^\d+\.\d+\.\d+$/.test(value)) {
    problems.push(
      error(file, `версия "${value}" не в формате number.number.number`, line),
    );
    return problems;
  }
  if (value === '0.0.0') {
    problems.push(error(file, 'версия 0.0.0 недопустима', line));
  }
  for (const part of value.split('.')) {
    if (Number(part) > VERSION_PART_MAX) {
      problems.push(
        error(file, `число ${part} больше ${VERSION_PART_MAX}`, line),
      );
    }
  }
  return problems;
}

/**
 * Проверяет changelog.txt по требованиям парсера игры. Читает файл и
 * делегирует разбор `parseChangelog`.
 */
export async function validateChangelog(
  modDir: string,
  repoRoot: string,
): Promise<ChangelogResult> {
  const path = join(modDir, 'changelog.txt');
  const file = relative(repoRoot, path);

  let raw: string;
  try {
    raw = await readFile(path, 'utf8');
  } catch {
    return { versions: [], problems: [], present: false };
  }

  return parseChangelog(raw, file);
}

/**
 * Чистый разбор содержимого changelog.txt. Правила жёсткие: ошибки формата
 * игра пишет в лог-файл, а не на экран, поэтому ловим их здесь.
 *
 * Отделено от чтения файла, чтобы покрываться юнит-тестами без файловой
 * системы — convention `testing`.
 */
export function parseChangelog(raw: string, file: string): ChangelogResult {
  const problems: Problem[] = [];
  const versions: string[] = [];
  const seenVersions = new Set<string>();
  const seenEntryLines = new Map<string, Set<string>>();

  let currentVersion: string | null = null;
  let currentCategory: string | null = null;
  let expectVersionLine = false;
  let sawDateInSection = false;
  let lastWasEntryOrContinuation = false;

  const lines = raw.split('\n');
  for (const [index, line] of lines.entries()) {
    const lineNo = index + 1;
    const isLastAndEmpty = index === lines.length - 1 && line === '';

    if (line.includes('\t')) {
      problems.push(error(file, 'табуляция запрещена парсером', lineNo));
    }
    if (line.length > 0 && /\s$/.test(line)) {
      problems.push(
        error(file, 'пробел в конце строки запрещён парсером', lineNo),
      );
    }

    if (expectVersionLine) {
      if (line.trim() === '') {
        problems.push(
          error(
            file,
            'строка сразу после разделителя не может быть пустой',
            lineNo,
          ),
        );
        // Остаёмся в ожидании строки Version: иначе одна пустая строка
        // превращает весь остаток файла в каскад «вне секции версии».
        continue;
      }
      const match = VERSION_LINE.exec(line);
      if (match === null) {
        problems.push(
          error(
            file,
            'после разделителя ожидается строка "Version: <версия>" (с пробелом после двоеточия)',
            lineNo,
          ),
        );
        expectVersionLine = false;
        continue;
      }
      const version = (match[1] ?? '').trim();
      problems.push(...checkVersion(version, file, lineNo));
      if (seenVersions.has(version)) {
        problems.push(
          error(file, `секция версии ${version} встречается повторно`, lineNo),
        );
      } else {
        seenVersions.add(version);
        versions.push(version);
      }
      currentVersion = version;
      currentCategory = null;
      expectVersionLine = false;
      sawDateInSection = false;
      lastWasEntryOrContinuation = false;
      continue;
    }

    if (line.trim() === '') {
      continue;
    }

    if (SEPARATOR.test(line)) {
      if (line.length !== CHANGELOG_SEPARATOR_LENGTH) {
        problems.push(
          error(
            file,
            `разделитель секции: ${line.length} дефисов вместо ${CHANGELOG_SEPARATOR_LENGTH}`,
            lineNo,
          ),
        );
      }
      expectVersionLine = true;
      continue;
    }

    if (currentVersion === null) {
      if (!isLastAndEmpty) {
        problems.push(
          error(
            file,
            'строка вне секции версии: файл должен начинаться с разделителя из 99 дефисов',
            lineNo,
          ),
        );
      }
      continue;
    }

    const dateMatch = DATE_LINE.exec(line);
    if (dateMatch !== null) {
      if (sawDateInSection) {
        problems.push(
          error(file, 'в одной секции версии две строки Date:', lineNo),
        );
      }
      sawDateInSection = true;
      lastWasEntryOrContinuation = false;
      continue;
    }

    const entryMatch = ENTRY_LINE.exec(line);
    if (entryMatch !== null) {
      if (currentCategory === null) {
        problems.push(
          error(file, 'запись идёт до строки категории', lineNo),
        );
      } else {
        const key = `${currentVersion}\u0000${currentCategory}`;
        const bucket = seenEntryLines.get(key) ?? new Set<string>();
        const content = entryMatch[1] ?? '';
        if (bucket.has(content)) {
          problems.push(
            error(
              file,
              `дубль записи в категории "${currentCategory}" версии ${currentVersion}`,
              lineNo,
            ),
          );
        }
        bucket.add(content);
        seenEntryLines.set(key, bucket);
      }
      lastWasEntryOrContinuation = true;
      continue;
    }

    const continuationMatch = CONTINUATION_LINE.exec(line);
    if (continuationMatch !== null) {
      if (!lastWasEntryOrContinuation) {
        problems.push(
          error(
            file,
            'продолжение многострочной записи без предшествующей записи',
            lineNo,
          ),
        );
      } else if (currentCategory !== null) {
        const key = `${currentVersion}\u0000${currentCategory}`;
        const bucket = seenEntryLines.get(key) ?? new Set<string>();
        const content = continuationMatch[1] ?? '';
        if (bucket.has(content)) {
          problems.push(
            error(
              file,
              `строка многострочной записи дублирует другую в категории "${currentCategory}"`,
              lineNo,
            ),
          );
        }
        bucket.add(content);
        seenEntryLines.set(key, bucket);
      }
      continue;
    }

    const categoryMatch = CATEGORY_LINE.exec(line);
    if (categoryMatch !== null) {
      const text = categoryMatch[1] ?? '';
      if (!text.endsWith(':')) {
        problems.push(
          error(file, 'строка категории должна заканчиваться двоеточием', lineNo),
        );
      }
      const category = text.replace(/:$/, '');
      if (
        !(CHANGELOG_KNOWN_CATEGORIES as readonly string[]).includes(category)
      ) {
        problems.push(
          warning(
            file,
            `категория "${category}" не распознаётся игрой — проверь опечатку`,
            lineNo,
          ),
        );
      }
      currentCategory = category;
      lastWasEntryOrContinuation = false;
      continue;
    }

    problems.push(
      error(
        file,
        'некорректный отступ: ожидается 2 пробела (категория), 4 пробела и "- " (запись) или 6 пробелов (продолжение)',
        lineNo,
      ),
    );
    lastWasEntryOrContinuation = false;
  }

  if (expectVersionLine) {
    problems.push(
      error(file, 'файл заканчивается разделителем без строки Version:'),
    );
  }

  return { versions, problems, present: true };
}
