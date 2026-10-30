import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  binaryCandidates,
  configIniText,
  extractConfigArgument,
  isGraphicsRun,
  needsRewrite,
  portalCredentials,
  readDataOf,
  resolveBinary,
  resolveReadData,
  runOutcome,
  steamCloudPlayerData,
  steamLibraryPaths,
} from './ingame-config.ts';

/** Проверка существования по списку путей, без файловой системы. */
function existsIn(paths: readonly string[]): (path: string) => boolean {
  return (path) => paths.includes(path);
}

const APP_BIN = '/Apps/factorio.app/Contents/MacOS/factorio';
const APP_DIR = '/Apps/factorio.app/Contents/MacOS';

test('macOS-бандл: данные на уровень выше бинаря', () => {
  const exists = existsIn(['/Apps/factorio.app/Contents/data/base/info.json']);
  assert.equal(
    resolveReadData(APP_DIR, exists),
    '__PATH__executable__/../data',
  );
});

test('раскладка bin/x64: данные на два уровня выше бинаря', () => {
  const exists = existsIn(['/opt/factorio/data/base/info.json']);
  assert.equal(
    resolveReadData('/opt/factorio/bin/x64', exists),
    '__PATH__executable__/../../data',
  );
});

test('каталога данных нет вовсе — ответа нет, а не догадка', () => {
  assert.equal(resolveReadData(APP_DIR, existsIn([])), undefined);
});

test('раскладка определяется по пакету base, а не по имени каталога', () => {
  // Каталог `Contents/data` без `base/info.json` не делает раскладку
  // macOS-овой: игра всё равно упала бы с «no package core».
  const exists = existsIn(['/Apps/factorio.app/data/base/info.json']);
  assert.equal(
    resolveReadData(APP_DIR, exists),
    '__PATH__executable__/../../data',
  );
});

test('пути нормализуются: регрессия на `bin/x64/../../data`', () => {
  // Сравнение строк без normalize давало undefined на реальной установке.
  const exists = existsIn(['/opt/factorio/data/base/info.json']);
  assert.equal(
    resolveReadData('/opt/factorio/bin/x64/', exists),
    '__PATH__executable__/../../data',
  );
});

test('конфиг содержит подобранный read-data и заданный write-data', () => {
  const text = configIniText('__PATH__executable__/../data', '/repo/.work/x');
  assert.equal(readDataOf(text), '__PATH__executable__/../data');
  assert.match(text, /^write-data=\/repo\/\.work\/x$/m);
});

test('read-data читается из существующего конфига', () => {
  const text = '[path]\nread-data=__PATH__executable__/../../data\nwrite-data=/tmp\n';
  assert.equal(readDataOf(text), '__PATH__executable__/../../data');
  assert.equal(readDataOf('[path]\nwrite-data=/tmp\n'), undefined);
});

test('перезапись нужна, когда файла нет или read-data указывает не туда', () => {
  const wanted = '__PATH__executable__/../data';
  assert.equal(needsRewrite(undefined, wanted), true);
  // Ровно тот случай, из-за которого обёртка и появилась: CLI пишет
  // Linux-раскладку, игра в macOS-бандле её не принимает.
  assert.equal(
    needsRewrite('[path]\nread-data=__PATH__executable__/../../data\n', wanted),
    true,
  );
  assert.equal(needsRewrite(`[path]\nread-data=${wanted}\n`, wanted), false);
});

test('FACTORIO_BIN идёт первым кандидатом, пустое значение игнорируется', () => {
  assert.equal(binaryCandidates('/fake-home', '/custom/factorio')[0], '/custom/factorio');
  const plain = binaryCandidates('/fake-home', undefined);
  assert.equal(plain.includes('/custom/factorio'), false);
  assert.deepEqual(binaryCandidates('/fake-home', ''), plain);
});

test('кандидаты раскрывают домашний каталог параметром, а не константой', () => {
  const candidates = binaryCandidates('/fake-home', undefined);
  assert.ok(candidates.every((path) => !path.includes('~')));
  assert.ok(candidates.some((path) => path.startsWith('/fake-home/')));
});

test('выбирается первый существующий кандидат', () => {
  const candidates = ['/a/factorio', APP_BIN, '/c/factorio'];
  assert.equal(resolveBinary(candidates, existsIn([APP_BIN, '/c/factorio'])), APP_BIN);
  assert.equal(resolveBinary(candidates, existsIn([])), undefined);
});

test('конфиг вынимается из -c, --config и --config=, остальное сохраняется по порядку', () => {
  assert.deepEqual(extractConfigArgument(['-v', '-c', 'a.json', '-g']), {
    config: 'a.json',
    rest: ['-v', '-g'],
  });
  assert.deepEqual(extractConfigArgument(['--config', 'b.json']), { config: 'b.json', rest: [] });
  assert.deepEqual(extractConfigArgument(['--config=c.json', 'filter']), {
    config: 'c.json',
    rest: ['filter'],
  });
});

test('без конфига — undefined, -c без значения не теряется', () => {
  assert.deepEqual(extractConfigArgument(['-v']), { config: undefined, rest: ['-v'] });
  assert.deepEqual(extractConfigArgument(['-c']), { config: undefined, rest: ['-c'] });
});

test('после -- аргументы не разбираются: это фильтры тестов', () => {
  assert.deepEqual(extractConfigArgument(['--', '-c', 'x']), {
    config: undefined,
    rest: ['--', '-c', 'x'],
  });
});

test('режим с графикой узнаётся по -g, --graphics и связке флагов, но не после --', () => {
  assert.equal(isGraphicsRun(['-g']), true);
  assert.equal(isGraphicsRun(['--graphics']), true);
  assert.equal(isGraphicsRun(['-gw']), true);
  assert.equal(isGraphicsRun(['-v', 'filter']), false);
  assert.equal(isGraphicsRun(['--', '-g']), false);
  assert.equal(isGraphicsRun(['--tag-whitelist', 'gui']), false);
});

test('итог прогона читается из строки CLI, прочие строки — не итог', () => {
  assert.equal(runOutcome('Test run finished: passed'), 'passed');
  assert.equal(runOutcome('   86.163 Script @x: Test run finished: failed'), 'failed');
  assert.equal(runOutcome('Test run finished: todo'), 'failed');
  assert.equal(runOutcome('PASS tests > a'), undefined);
});

test('библиотеки Steam читаются из libraryfolders.vdf, обратный слеш раскрывается', () => {
  const vdf = [
    '"libraryfolders"',
    '{',
    '\t"0"',
    '\t{',
    '\t\t"path"\t\t"/srv/steam-main"',
    '\t\t"apps"',
    '\t\t{',
    '\t\t\t"427520"\t\t"0"',
    '\t\t}',
    '\t}',
    '\t"1"',
    '\t{',
    '\t\t"path"\t\t"D:\\\\Games\\\\Steam"',
    '\t\t"label"\t\t""',
    '\t}',
    '}',
  ].join('\n');
  assert.deepEqual(steamLibraryPaths(vdf), ['/srv/steam-main', 'D:\\Games\\Steam']);
  assert.deepEqual(steamLibraryPaths(''), []);
});

test('игра во второй библиотеке Steam находится без FACTORIO_BIN', () => {
  const binary = '/disk/steam/steamapps/common/Factorio/bin/x64/factorio';
  const candidates = binaryCandidates('/fake-home', undefined, ['/disk/steam']);
  assert.equal(resolveBinary(candidates, existsIn([binary])), binary);
  assert.ok(candidates.includes('/disk/steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio'));
});

test('основная библиотека Steam не дублирует типовой кандидат, FACTORIO_BIN остаётся первым', () => {
  const plain = binaryCandidates('/fake-home', undefined);
  assert.deepEqual(
    binaryCandidates('/fake-home', undefined, ['/fake-home/.local/share/Steam']).filter(
      (path) => plain.includes(path),
    ),
    plain,
  );
  const withEnv = binaryCandidates('/fake-home', '/custom/factorio', ['/disk/steam']);
  assert.equal(withEnv[0], '/custom/factorio');
  assert.equal(new Set(withEnv).size, withEnv.length);
});

test('Steam Cloud-копии player-data.json — по одной на пользователя Steam', () => {
  assert.deepEqual(steamCloudPlayerData('/s', ['1', '2']), [
    '/s/userdata/1/427520/remote/player-data.json',
    '/s/userdata/2/427520/remote/player-data.json',
  ]);
});

/**
 * Текст `player-data.json`. Имя поля с токеном собирается через `fx`-подобный
 * маркер: литерал поймал бы `npm run check-secrets`, см. convention `testing`.
 */
function playerData(fields: Record<string, unknown>): string {
  const tokenKey = 'service-·token'.replace('·', '');
  const { token, ...rest } = fields;
  return JSON.stringify(token === undefined ? rest : { ...rest, [tokenKey]: token });
}

test('креды берутся из player-data.json только при входе в аккаунт', () => {
  assert.deepEqual(portalCredentials(playerData({ 'service-username': 'author', token: 'fake' })), {
    username: 'author',
    token: 'fake',
  });
  assert.equal(portalCredentials(playerData({ 'service-username': 'author' })), undefined);
  assert.equal(portalCredentials(playerData({ 'service-username': '', token: 'fake' })), undefined);
  assert.equal(portalCredentials(playerData({ token: 'fake' })), undefined);
  assert.equal(portalCredentials('не json'), undefined);
  assert.equal(portalCredentials('null'), undefined);
});
