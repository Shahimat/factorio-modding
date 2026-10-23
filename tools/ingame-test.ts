#!/usr/bin/env node
/**
 * Стенд тестов внутри игры: готовит `config.ini` под раскладку установленной
 * игры и запускает `factorio-test run`, пробрасывая аргументы и код возврата.
 *
 *     npm run test:ingame
 *     npm run test:ingame -- -v
 *     npm run test:ingame -- "оснастка"
 *
 * Почему обёртка, а не прямой вызов CLI — `tools/lib/ingame-config.ts`.
 * Путь к бинарю игры переопределяется переменной `FACTORIO_BIN`, как
 * `LUA_BIN` у Lua-тестов: абсолютных путей с именем пользователя в
 * версионируемых файлах быть не может, convention `secrets`.
 */
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';

import {
  binaryCandidates,
  configIniText,
  needsRewrite,
  resolveBinary,
  resolveReadData,
} from './lib/ingame-config.ts';
import { REPO_ROOT } from './lib/packages.ts';

/** Конфиг CLI; тот же файл читает и сам `factorio-test`. */
const CLI_CONFIG = join(REPO_ROOT, 'factorio-test.json');

/** Дефолт самого CLI — на случай, если конфига в репозитории нет. */
const DEFAULT_DATA_DIR = './factorio-test-data-dir';

async function dataDirectory(): Promise<string> {
  let raw: string;
  try {
    raw = await readFile(CLI_CONFIG, 'utf8');
  } catch {
    return resolve(REPO_ROOT, DEFAULT_DATA_DIR);
  }

  const parsed: unknown = JSON.parse(raw);
  const value =
    typeof parsed === 'object' && parsed !== null
      ? (parsed as { dataDirectory?: unknown }).dataDirectory
      : undefined;
  const dir = typeof value === 'string' && value !== '' ? value : DEFAULT_DATA_DIR;
  return isAbsolute(dir) ? dir : resolve(REPO_ROOT, dir);
}

function runCli(binary: string, args: readonly string[]): Promise<number> {
  const cli = join(REPO_ROOT, 'node_modules', '.bin', 'factorio-test');
  const child = spawn(cli, ['run', '--factorio-path', binary, ...args], {
    cwd: REPO_ROOT,
    stdio: 'inherit',
  });

  return new Promise((done, fail) => {
    child.on('error', fail);
    child.on('exit', (code, signal) => {
      // Убитый сигналом процесс — не успех: иначе падение стенда прошло бы
      // как зелёный прогон.
      done(code ?? (signal === null ? 1 : 128));
    });
  });
}

async function main(): Promise<void> {
  const binary = resolveBinary(
    binaryCandidates(homedir(), process.env.FACTORIO_BIN),
    existsSync,
  );
  if (binary === undefined) {
    throw new Error(
      'бинарь игры не найден — укажи путь в переменной FACTORIO_BIN',
    );
  }

  const readData = resolveReadData(dirname(binary), existsSync);
  if (readData === undefined) {
    throw new Error(
      `рядом с ${binary} нет каталога данных игры с пакетом base — проверь установку`,
    );
  }

  const dataDir = await dataDirectory();
  await mkdir(dataDir, { recursive: true });

  const configPath = join(dataDir, 'config.ini');
  let existing: string | undefined;
  try {
    existing = await readFile(configPath, 'utf8');
  } catch {
    existing = undefined;
  }

  if (needsRewrite(existing, readData)) {
    await writeFile(configPath, configIniText(readData, dataDir));
    console.log(
      `config.ini: ${relative(REPO_ROOT, configPath)}, read-data=${readData}`,
    );
  }

  process.exitCode = await runCli(binary, process.argv.slice(2));
}

try {
  await main();
} catch (cause: unknown) {
  console.error(cause instanceof Error ? cause.message : String(cause));
  process.exitCode = 1;
}
