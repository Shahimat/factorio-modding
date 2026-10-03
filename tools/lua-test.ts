#!/usr/bin/env node
/**
 * Запускает Lua-тесты модов. Скоуп задаётся явно — convention `testing`:
 *
 *     node tools/lua-test.ts <mod-key|каталог>...   один мод
 *     node tools/lua-test.ts --all                  все моды, осознанно
 *
 * Из пакета мода вызывается как `npm test -w shm-<mod>`, где скрипт
 * указывает на этот файл с аргументом `.`.
 */
import { basename } from 'node:path';

import { runLuaTests } from './lib/lua-tests.ts';
import { resolveModDirs } from './lib/packages.ts';
import { countErrors, formatProblem } from './lib/problems.ts';

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    throw new Error(
      'не задан скоуп: укажи мод (`node tools/lua-test.ts shm-<mod>`) либо `--all`',
    );
  }

  const { dirs, unknown } = await resolveModDirs(args);
  if (unknown.length > 0) {
    throw new Error(`нет таких модов в mods/: ${unknown.join(', ')}`);
  }
  if (dirs.length === 0) {
    console.log('Модов в mods/ нет — тестировать нечего.');
    return;
  }

  let errorsTotal = 0;
  let passedTotal = 0;
  let failedTotal = 0;

  for (const modDir of dirs) {
    const result = await runLuaTests(modDir);
    const errors = countErrors(result.problems);
    errorsTotal += errors;
    passedTotal += result.passed;
    failedTotal += result.failed;

    const status = errors > 0 ? 'ОШИБКИ' : 'ок';
    console.log(
      `${basename(modDir)}: ${status} — файлов ${result.files.length}, прошло ${result.passed}, упало ${result.failed}`,
    );
    for (const problem of result.problems) {
      console.log(formatProblem(problem));
    }
  }

  console.log(
    `\nИтого: модов ${dirs.length}, прошло ${passedTotal}, упало ${failedTotal}`,
  );

  if (errorsTotal > 0) {
    process.exitCode = 1;
  }
}

try {
  await main();
} catch (cause: unknown) {
  console.error(cause instanceof Error ? cause.message : String(cause));
  process.exitCode = 1;
}
