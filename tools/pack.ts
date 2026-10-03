#!/usr/bin/env node
/**
 * Собирает zip релиза мода по требованиям мод-портала:
 * `{name}_{version}.zip`, внутри ровно одна папка верхнего уровня,
 * `info.json` в её корне. Запуск: `npm run pack [-- <имя-мода>...]`.
 *
 * Покрывает behavior `mod-zip-matches-portal-rules`.
 */
import { execFile } from 'node:child_process';
import { cp, mkdir, rm } from 'node:fs/promises';
import { basename, join, relative, sep } from 'node:path';
import { promisify } from 'node:util';

import { PACK_EXCLUDED } from './lib/conventions.ts';
import { countErrors, formatProblem } from './lib/problems.ts';
import { listModDirs, REPO_ROOT } from './lib/packages.ts';
import { validateMod } from './lib/validate-mod.ts';

const run = promisify(execFile);

const DIST = join(REPO_ROOT, 'dist');
const STAGING = join(DIST, '.staging');

function isExcluded(modDir: string, source: string): boolean {
  const rel = relative(modDir, source);
  if (rel === '') return false;
  const segments = rel.split(sep);
  if (segments.some((s) => (PACK_EXCLUDED as readonly string[]).includes(s))) {
    return true;
  }
  return rel.endsWith('.zip');
}

async function ensureZipAvailable(): Promise<void> {
  try {
    await run('zip', ['-v']);
  } catch {
    throw new Error(
      'не найдена утилита `zip`. На macOS и большинстве дистрибутивов Linux она есть из коробки; установи её и повтори',
    );
  }
}

async function packMod(modDir: string): Promise<string> {
  const { info, problems } = await validateMod(modDir);
  for (const problem of problems) {
    console.log(formatProblem(problem));
  }
  if (countErrors(problems) > 0 || info === null) {
    throw new Error(
      `${basename(modDir)}: сборка остановлена, сначала исправь ошибки валидации`,
    );
  }

  const stageRoot = join(STAGING, info.name);
  await rm(stageRoot, { recursive: true, force: true });
  await mkdir(STAGING, { recursive: true });
  await cp(modDir, stageRoot, {
    recursive: true,
    dereference: true,
    filter: (source) => !isExcluded(modDir, source),
  });

  const zipName = `${info.name}_${info.version}.zip`;
  const zipPath = join(DIST, zipName);
  await rm(zipPath, { force: true });

  // -r рекурсивно, -X без лишних метаданных ФС, -q тихо.
  await run('zip', ['-rXq', zipPath, info.name], { cwd: STAGING });
  await rm(stageRoot, { recursive: true, force: true });

  return zipPath;
}

async function main(): Promise<void> {
  await ensureZipAvailable();

  const requested = process.argv.slice(2);
  const all = await listModDirs();

  if (all.length === 0) {
    console.log('Модов в mods/ нет — собирать нечего.');
    return;
  }

  const selected =
    requested.length === 0
      ? all
      : all.filter((dir) => requested.includes(basename(dir)));

  const unknown = requested.filter(
    (name) => !all.some((dir) => basename(dir) === name),
  );
  if (unknown.length > 0) {
    throw new Error(`нет таких модов в mods/: ${unknown.join(', ')}`);
  }

  await mkdir(DIST, { recursive: true });

  for (const modDir of selected) {
    const zipPath = await packMod(modDir);
    console.log(`собран ${relative(REPO_ROOT, zipPath)}`);
  }

  await rm(STAGING, { recursive: true, force: true });
}

try {
  await main();
} catch (cause: unknown) {
  console.error(cause instanceof Error ? cause.message : String(cause));
  process.exitCode = 1;
}
