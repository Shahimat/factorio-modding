#!/usr/bin/env node
/**
 * Стенд тестов внутри игры: готовит `config.ini` под раскладку установленной
 * игры и запускает `factorio-test run`, пробрасывая аргументы и код возврата.
 *
 *     npm run test:ingame
 *     npm run test:ingame -- -v
 *     npm run test:ingame -- "оснастка"
 *     npm run test:ingame -- -c mods/<mod>/tests/ingame/factorio-test.json
 *
 * Без `-c` берётся `factorio-test.json` в корне. Игра запускается из
 * каталога данных стенда, где обёртка кладёт `steam_appid.txt`: иначе
 * Steam-сборка перезапустит себя через Steam и потеряет аргументы, см.
 * `STEAM_APP_ID`. Поэтому CLI получает путь к конфигу абсолютным.
 *
 * Почему обёртка, а не прямой вызов CLI — `tools/lib/ingame-config.ts`.
 * Путь к бинарю игры переопределяется переменной `FACTORIO_BIN`, как
 * `LUA_BIN` у Lua-тестов: абсолютных путей с именем пользователя в
 * версионируемых файлах быть не может, convention `secrets`.
 * Креды портала для скачивания `factorio-test` без `FACTORIO_USERNAME` /
 * `FACTORIO_TOKEN` берутся из Steam Cloud, см. `cliEnvironment`.
 */
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';

import { findGameBinary, gameReadData, steamCloudCredentials } from './lib/game-install.ts';
import {
  STEAM_APP_ID,
  configIniText,
  extractConfigArgument,
  isGraphicsRun,
  needsRewrite,
  runOutcome,
} from './lib/ingame-config.ts';
import { REPO_ROOT } from './lib/packages.ts';

/** Конфиг CLI по умолчанию; тот же файл читает и сам `factorio-test`. */
const DEFAULT_CLI_CONFIG = join(REPO_ROOT, 'factorio-test.json');

/** Дефолт самого CLI — на случай, если конфига в репозитории нет. */
const DEFAULT_DATA_DIR = './factorio-test-data-dir';

/**
 * Каталог данных стенда. Относительные пути конфига CLI считает от каталога
 * самого конфига — обёртка делает так же.
 */
async function dataDirectory(configPath: string): Promise<string> {
  const configDir = dirname(configPath);
  let raw: string;
  try {
    raw = await readFile(configPath, 'utf8');
  } catch {
    return resolve(configDir, DEFAULT_DATA_DIR);
  }

  const parsed: unknown = JSON.parse(raw);
  const value =
    typeof parsed === 'object' && parsed !== null
      ? (parsed as { dataDirectory?: unknown }).dataDirectory
      : undefined;
  const dir = typeof value === 'string' && value !== '' ? value : DEFAULT_DATA_DIR;
  return isAbsolute(dir) ? dir : resolve(configDir, dir);
}

/**
 * Окружение процесса CLI. Креды не заданы переменными — подставляются из
 * Steam Cloud, если они там есть: на Linux CLI сам туда не смотрит. Значения
 * живут только в окружении дочернего процесса.
 */
function cliEnvironment(): NodeJS.ProcessEnv {
  const env = process.env;
  if (env['FACTORIO_USERNAME'] || env['FACTORIO_TOKEN']) return env;
  const cloud = steamCloudCredentials();
  if (cloud === undefined) return env;
  console.log('креды портала: Steam Cloud');
  return {
    ...env,
    FACTORIO_USERNAME: cloud.username,
    FACTORIO_TOKEN: cloud.token,
  };
}

function runCli(
  binary: string,
  configPath: string,
  cwd: string,
  args: readonly string[],
): Promise<number> {
  const cli = join(REPO_ROOT, 'node_modules', '.bin', 'factorio-test');
  const graphics = isGraphicsRun(args);
  // С графикой CLI ждёт, пока игру закроют руками. Своя группа процессов
  // позволяет по итоговой строке закрыть CLI вместе с игрой одним сигналом.
  const child = spawn(
    cli,
    ['run', '--factorio-path', binary, '--config', configPath, ...args],
    {
      cwd,
      env: cliEnvironment(),
      stdio: graphics ? ['inherit', 'pipe', 'inherit'] : 'inherit',
      detached: graphics,
    },
  );

  let outcome: 'passed' | 'failed' | undefined;
  if (graphics && child.stdout !== null) {
    let buffer = '';
    child.stdout.on('data', (chunk: Buffer) => {
      process.stdout.write(chunk);
      buffer += chunk.toString('utf8');
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        const found = runOutcome(line);
        if (found !== undefined && outcome === undefined && child.pid !== undefined) {
          outcome = found;
          process.kill(-child.pid, 'SIGTERM');
        }
      }
    });
  }

  return new Promise((done, fail) => {
    child.on('error', fail);
    child.on('exit', (code, signal) => {
      if (outcome !== undefined) {
        done(outcome === 'passed' ? 0 : 1);
        return;
      }
      // Убитый сигналом процесс — не успех: иначе падение стенда прошло бы
      // как зелёный прогон.
      done(code ?? (signal === null ? 1 : 128));
    });
  });
}

async function main(): Promise<void> {
  const binary = findGameBinary();
  const readData = gameReadData(binary);

  const { config, rest } = extractConfigArgument(process.argv.slice(2));
  const configPath = config === undefined ? DEFAULT_CLI_CONFIG : resolve(config);
  if (!existsSync(configPath)) {
    throw new Error(`нет конфига стенда ${configPath}`);
  }

  const dataDir = await dataDirectory(configPath);
  await mkdir(dataDir, { recursive: true });
  await writeFile(join(dataDir, 'steam_appid.txt'), `${STEAM_APP_ID}\n`);

  const configIni = join(dataDir, 'config.ini');
  let existing: string | undefined;
  try {
    existing = await readFile(configIni, 'utf8');
  } catch {
    existing = undefined;
  }

  if (needsRewrite(existing, readData)) {
    await writeFile(configIni, configIniText(readData, dataDir));
    console.log(
      `config.ini: ${relative(REPO_ROOT, configIni)}, read-data=${readData}`,
    );
  }

  process.exitCode = await runCli(binary, configPath, dataDir, rest);
}

try {
  await main();
} catch (cause: unknown) {
  console.error(cause instanceof Error ? cause.message : String(cause));
  process.exitCode = 1;
}
