#!/usr/bin/env node
/**
 * Полная проверка одного мода: его Lua-тесты плюс валидация пакета.
 * Запуск: `npm run check:mod -- <mod-key>`.
 *
 * Отдельно от `npm run check` сознательно — convention `testing`, раздел
 * «Скоупы запуска»: общий прогон по всем модам не должен быть налогом на
 * правку в `tools/`.
 */
import { basename } from 'node:path';

import { runLuaTests } from './lib/lua-tests.ts';
import { resolveModDirs } from './lib/packages.ts';
import { countErrors, formatProblem } from './lib/problems.ts';
import { validateMod } from './lib/validate-mod.ts';

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    throw new Error(
      'не задан мод: `npm run check:mod -- <mod-key>`; приставку shm- можно опустить',
    );
  }

  const { dirs, unknown } = await resolveModDirs(args);
  if (unknown.length > 0) {
    throw new Error(`нет таких модов в mods/: ${unknown.join(', ')}`);
  }

  let errorsTotal = 0;
  let warningsTotal = 0;

  for (const modDir of dirs) {
    const name = basename(modDir);

    const tests = await runLuaTests(modDir);
    const testErrors = countErrors(tests.problems);
    errorsTotal += testErrors;
    console.log(
      `${name} · тесты: ${testErrors > 0 ? 'ОШИБКИ' : 'ок'} — файлов ${tests.files.length}, прошло ${tests.passed}, упало ${tests.failed}`,
    );
    for (const problem of tests.problems) {
      console.log(formatProblem(problem));
    }

    const { problems } = await validateMod(modDir);
    const errors = countErrors(problems);
    const warnings = problems.length - errors;
    errorsTotal += errors;
    warningsTotal += warnings;
    const status = errors > 0 ? 'ОШИБКИ' : warnings > 0 ? 'замечания' : 'ок';
    console.log(`${name} · пакет: ${status}`);
    for (const problem of problems) {
      console.log(formatProblem(problem));
    }
  }

  console.log(
    `\nИтого: модов ${dirs.length}, ошибок ${errorsTotal}, замечаний ${warningsTotal}`,
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
