import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  binaryCandidates,
  configIniText,
  needsRewrite,
  readDataOf,
  resolveBinary,
  resolveReadData,
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
