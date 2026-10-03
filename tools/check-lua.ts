#!/usr/bin/env node
/**
 * Проверяет Lua-исходники на диалект: игра исполняет патченный Lua 5.2, а
 * локальный интерпретатор новее и лишнего не запрещает. Правило — convention
 * `testing`, раздел «Диалект Lua».
 *
 *     npm run check-lua -- <mod-key|poc/<имя>|путь>...
 *     npm run check-lua -- --all
 *
 * Скоуп обязателен: пакеты в `mods/` и так проверяются внутри
 * `npm run validate`, а эта команда нужна для того, что сейчас в работе —
 * в первую очередь для щупов в `poc/`, куда `validate` не ходит.
 */
import { readFile } from 'node:fs/promises';
import { relative } from 'node:path';

import { scanLuaDialect } from './lib/lua-dialect.ts';
import {
  dirExists,
  listFilesBySuffix,
  listPackageDirs,
  LUA_ROOTS,
  packageCandidatePaths,
  REPO_ROOT,
} from './lib/packages.ts';
import { countErrors, formatProblem, type Problem } from './lib/problems.ts';

async function resolveTargets(
  args: readonly string[],
): Promise<{ dirs: string[]; unknown: string[] }> {
  if (args.includes('--all')) {
    const dirs: string[] = [];
    for (const root of LUA_ROOTS) {
      dirs.push(...(await listPackageDirs(root)));
    }
    return { dirs, unknown: [] };
  }

  const dirs: string[] = [];
  const unknown: string[] = [];

  for (const arg of args) {
    // Путь принимается любым каталогом: в `poc/` может лежать щуп, который
    // ещё не дорос до info.json.
    if (arg.includes('/') || arg.startsWith('.')) {
      if (await dirExists(arg)) {
        dirs.push(arg);
      } else {
        unknown.push(arg);
      }
      continue;
    }

    const candidate = (
      await Promise.all(
        packageCandidatePaths(LUA_ROOTS, arg).map(async (path) =>
          (await dirExists(path)) ? path : null,
        ),
      )
    ).find((path): path is string => path !== null);

    if (candidate === undefined) {
      unknown.push(arg);
    } else {
      dirs.push(candidate);
    }
  }

  return { dirs: [...new Set(dirs)], unknown };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    throw new Error(
      'не задан скоуп: `npm run check-lua -- <mod-key|poc/<имя>|путь>` либо `-- --all`',
    );
  }

  const { dirs, unknown } = await resolveTargets(args);
  if (unknown.length > 0) {
    throw new Error(
      `не найдены каталоги: ${unknown.join(', ')} — искал в mods/ и poc/, с приставкой shm- и без`,
    );
  }
  if (dirs.length === 0) {
    console.log('Lua-кода в mods/ и poc/ нет — проверять нечего.');
    return;
  }

  let errorsTotal = 0;
  let filesTotal = 0;

  for (const dir of dirs) {
    const problems: Problem[] = [];
    const files = await listFilesBySuffix(dir, '.lua');
    filesTotal += files.length;

    for (const path of files) {
      let text: string;
      try {
        text = await readFile(path, 'utf8');
      } catch {
        continue;
      }
      problems.push(...scanLuaDialect(relative(REPO_ROOT, path), text));
    }

    const errors = countErrors(problems);
    errorsTotal += errors;
    console.log(
      `${relative(REPO_ROOT, dir) || '.'}: ${errors > 0 ? 'ОШИБКИ' : 'ок'} — файлов ${files.length}`,
    );
    for (const problem of problems) {
      console.log(formatProblem(problem));
    }
  }

  console.log(
    `\nИтого: каталогов ${dirs.length}, файлов ${filesTotal}, ошибок ${errorsTotal}`,
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
