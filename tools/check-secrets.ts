#!/usr/bin/env node
/**
 * Проверяет, что в версионируемые файлы не попало ничего чувствительного.
 * Запуск: `npm run check-secrets`, входит в `npm run check`.
 *
 * Правило — `context/conventions/secrets.yml`. Репозиторий публичный.
 *
 * Сканируется ровно то множество, которое попадёт в git: отслеживаемые файлы
 * плюс неигнорируемые untracked. Отдельно проверяется, что `.gitignore`
 * действительно скрывает файлы с секретами. Разбор строк — в
 * `tools/lib/secret-scan.ts`.
 */
import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { promisify } from 'node:util';

import { REPO_ROOT } from './lib/packages.ts';
import {
  countErrors,
  error,
  formatProblem,
  type Problem,
} from './lib/problems.ts';
import {
  MUST_BE_IGNORED,
  MUST_NOT_BE_IGNORED,
} from './lib/secret-rules.ts';
import {
  checkFileName,
  isBinaryPath,
  scanText,
} from './lib/secret-scan.ts';

const run = promisify(execFile);

async function git(args: readonly string[]): Promise<string> {
  const { stdout } = await run('git', [...args], { cwd: REPO_ROOT });
  return stdout;
}

/** Файлы, которые попадут в git: отслеживаемые + неигнорируемые untracked. */
async function filesUnderGit(): Promise<string[]> {
  const tracked = await git(['ls-files', '-z']);
  const untracked = await git([
    'ls-files',
    '--others',
    '--exclude-standard',
    '-z',
  ]);
  const all = [...tracked.split('\0'), ...untracked.split('\0')].filter(
    (p) => p !== '',
  );
  return [...new Set(all)].sort();
}

/** `git check-ignore` — проверка, что .gitignore работает как заявлено. */
async function isIgnored(path: string): Promise<boolean> {
  try {
    await git(['check-ignore', '-q', '--no-index', path]);
    return true;
  } catch {
    return false;
  }
}

async function scanFile(relPath: string): Promise<Problem[]> {
  if (isBinaryPath(relPath)) return [];

  const byName = checkFileName(relPath);
  if (byName !== null) return [byName];

  let text: string;
  try {
    text = await readFile(join(REPO_ROOT, relPath), 'utf8');
  } catch {
    return [];
  }
  if (text.includes('\u0000')) return [];

  return scanText(relPath, text);
}

async function checkGitignore(): Promise<Problem[]> {
  const problems: Problem[] = [];
  for (const path of MUST_BE_IGNORED) {
    if (!(await isIgnored(path))) {
      problems.push(
        error('.gitignore', `путь "${path}" не игнорируется, а должен`),
      );
    }
  }
  for (const path of MUST_NOT_BE_IGNORED) {
    if (await isIgnored(path)) {
      problems.push(
        error('.gitignore', `путь "${path}" игнорируется, а не должен`),
      );
    }
  }
  return problems;
}

async function main(): Promise<void> {
  const ignoreProblems = await checkGitignore();
  const files = await filesUnderGit();

  const scanProblems: Problem[] = [];
  for (const file of files) {
    scanProblems.push(...(await scanFile(file)));
  }

  const sections = [
    { title: '.gitignore', problems: ignoreProblems },
    { title: 'содержимое версионируемых файлов', problems: scanProblems },
  ];

  let errorsTotal = 0;
  let warningsTotal = 0;
  for (const section of sections) {
    const errors = countErrors(section.problems);
    errorsTotal += errors;
    warningsTotal += section.problems.length - errors;
    const status =
      errors > 0
        ? 'ОШИБКИ'
        : section.problems.length > 0
          ? 'замечания'
          : 'ок';
    console.log(`${section.title}: ${status}`);
    for (const problem of section.problems) {
      console.log(formatProblem(problem));
    }
  }

  console.log(`\nПросканировано файлов: ${files.length}`);
  console.log(`Итого: ошибок ${errorsTotal}, замечаний ${warningsTotal}`);

  if (errorsTotal > 0) {
    process.exitCode = 1;
  }
}

await main();
