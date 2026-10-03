/**
 * Обнаружение и запуск Lua-тестов одного мода. Тонкая обёртка над
 * интерпретатором: разбор вывода и правила находок — в
 * `lua-test-runner.ts`, там же тесты.
 *
 * Скоупы запуска — convention `testing`, раздел «Скоупы запуска»: один вызов
 * покрывает один мод, общий прогон по всем модам вызывается осознанно.
 */

import { execFile } from 'node:child_process';
import { join, relative } from 'node:path';
import { promisify } from 'node:util';

import { LUA_TEST_SUFFIX } from './conventions.ts';
import { luaRunProblems, parseHarnessOutput } from './lua-test-runner.ts';
import { listFilesBySuffix, REPO_ROOT } from './packages.ts';
import { error, type Problem } from './problems.ts';

const run = promisify(execFile);

/** Интерпретатор. Переопределяется через `LUA_BIN`, см. convention `testing`. */
export const LUA_BIN = process.env['LUA_BIN'] ?? 'lua';

const RUNNER = join(REPO_ROOT, 'tools', 'lua', 'run.lua');

export interface LuaTestRun {
  /** Найденные файлы тестов, пути относительно корня репозитория. */
  readonly files: readonly string[];
  readonly problems: readonly Problem[];
  readonly passed: number;
  readonly failed: number;
}

/** Все `*.test.lua` внутри пакета мода, рекурсивно. */
export async function findLuaTestFiles(modDir: string): Promise<string[]> {
  return listFilesBySuffix(modDir, LUA_TEST_SUFFIX);
}

interface Spawned {
  readonly stdout: string;
  readonly stderr: string;
  readonly code: number | null;
}

async function spawnLua(args: readonly string[]): Promise<Spawned> {
  try {
    const { stdout, stderr } = await run(LUA_BIN, [...args], {
      cwd: REPO_ROOT,
    });
    return { stdout, stderr, code: 0 };
  } catch (cause: unknown) {
    const detail = cause as {
      code?: number | string;
      stdout?: string;
      stderr?: string;
    };
    if (detail.code === 'ENOENT') {
      throw new Error(
        `не найден интерпретатор "${LUA_BIN}". Поставь Lua (\`brew install lua\`) либо укажи другой бинарь через LUA_BIN`,
      );
    }
    return {
      stdout: detail.stdout ?? '',
      stderr: detail.stderr ?? '',
      code: typeof detail.code === 'number' ? detail.code : null,
    };
  }
}

/**
 * Прогон тестов мода. Отсутствие тестов — ошибка, а не «нечего делать»:
 * по convention `testing` логика мода покрывается тестами, и молчаливый
 * зелёный прогон пустого набора скрывал бы ровно тот случай, который надо
 * заметить.
 */
export async function runLuaTests(modDir: string): Promise<LuaTestRun> {
  const rel = relative(REPO_ROOT, modDir) || '.';
  const absolute = await findLuaTestFiles(modDir);
  const files = absolute.map((path) => relative(REPO_ROOT, path));

  if (absolute.length === 0) {
    return {
      files,
      problems: [
        error(
          rel,
          'нет ни одного файла `*.test.lua` — логика мода должна быть покрыта тестами, см. convention testing',
        ),
      ],
      passed: 0,
      failed: 0,
    };
  }

  const { stdout, stderr, code } = await spawnLua([
    RUNNER,
    '--root',
    modDir,
    ...absolute,
  ]);

  const parsed = parseHarnessOutput(stdout);
  const problems = luaRunProblems(rel, parsed, code, stderr);

  return {
    files,
    problems,
    passed: parsed.passed ?? 0,
    failed: parsed.failed ?? parsed.cases.filter((c) => !c.ok).length,
  };
}
