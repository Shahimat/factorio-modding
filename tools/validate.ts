#!/usr/bin/env node
/**
 * Проверяет все пакеты модов против ограничений мод-портала и требований
 * парсера игры. Запуск: `npm run validate`.
 *
 * Покрывает behaviors `mod-name-carries-author-prefix`,
 * `changelog-parses-in-game` и часть `mod-zip-matches-portal-rules`.
 */
import { basename } from 'node:path';

import { countErrors, formatProblem } from './lib/problems.ts';
import { listModDirs } from './lib/packages.ts';
import { validateMod } from './lib/validate-mod.ts';

async function main(): Promise<void> {
  const modDirs = await listModDirs();

  if (modDirs.length === 0) {
    console.log('Модов в mods/ нет — проверять нечего.');
    return;
  }

  let errorsTotal = 0;
  let warningsTotal = 0;

  for (const modDir of modDirs) {
    const { problems } = await validateMod(modDir);
    const errors = countErrors(problems);
    const warnings = problems.length - errors;
    errorsTotal += errors;
    warningsTotal += warnings;

    const status = errors > 0 ? 'ОШИБКИ' : warnings > 0 ? 'замечания' : 'ок';
    console.log(`${basename(modDir)}: ${status}`);
    for (const problem of problems) {
      console.log(formatProblem(problem));
    }
  }

  console.log(
    `\nИтого: модов ${modDirs.length}, ошибок ${errorsTotal}, замечаний ${warningsTotal}`,
  );

  if (errorsTotal > 0) {
    process.exitCode = 1;
  }
}

await main();
