import assert from 'node:assert/strict';
import { test } from 'node:test';

import { countErrors } from './problems.ts';
import { ALLOWED_EMAILS } from './secret-rules.ts';
import {
  checkFileName,
  isBinaryPath,
  scanLine,
  scanText,
} from './secret-scan.ts';

/**
 * Собирает фикстуру, убирая маркер `·`.
 *
 * Фикстуры нарочно хранятся «сломанными»: иначе этот файл сам становится
 * версионируемым файлом с литералами, похожими на секреты, и его ловит
 * `npm run check-secrets`. Исключение для файла в сканере не заводим —
 * это была бы дыра в правиле `secrets`. Маркер ставится так, чтобы в
 * исходнике не осталось ни совпадения с правилом, ни длинной строки:
 * порог hex — 30 символов, base64 — 40.
 */
const fx = (template: string): string => template.replaceAll('·', '');

function ids(line: string): string[] {
  return scanLine('f.md', line, 1).map((p) => {
    // Цифры в наборе обязательны: id вида `long-base64` их содержит.
    const m = /\[([a-z0-9-]+)\]/.exec(p.message);
    return m?.[1] ?? p.message;
  });
}

test('безобидная строка не даёт находок', () => {
  assert.deepEqual(ids('Обычный текст документации про мод.'), []);
});

test('литеральный токен после Bearer ловится, подстановка переменной — нет', () => {
  const line = fx('-H "Authorization: Bearer· abcd1234efgh5678ijkl"');
  assert.ok(ids(line).includes('bearer-literal'));
  assert.deepEqual(
    ids('-H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY"'),
    [],
  );
});

test('известные префиксы токенов ловятся', () => {
  assert.ok(
    ids(fx('ghp·_AbCdEfGhIjKlMnOpQrStUvWxYz012345')).includes('github-token'),
  );
  assert.ok(ids(fx('AKIA·IOSFODNN7EXAMPLE')).includes('aws-access-key'));
  assert.ok(ids(fx('xoxb·-12345678-abcdefgh')).includes('slack-token'));
});

test('приватный ключ ловится', () => {
  assert.ok(
    ids(fx('-----BEGIN RSA PRIVATE· KEY-----')).includes('private-key-block'),
  );
});

test('логин с паролем внутри URL ловится', () => {
  const line = fx('https·://user:p4ssw0rd@example·.com/x.git');
  const found = ids(line);
  assert.ok(found.includes('url-embedded-credentials'));
  assert.ok(found.includes('email'));
});

test('подчёркивание в имени переменной не мешает правилу присваивания', () => {
  // Регрессия: с границей \b правило не видело API_KEY после подчёркивания.
  const line = fx('FACTORIO_UPLOAD_API·_KEY=a1b2c3d4e5f6a7b8c9d0e1f2');
  assert.ok(ids(line).includes('secret-assignment'));
});

test('пустое значение и заглушка не считаются секретом', () => {
  assert.deepEqual(ids('export FACTORIO_UPLOAD_API_KEY='), []);
  assert.deepEqual(ids('export FACTORIO_UPLOAD_API_KEY=...'), []);
  assert.deepEqual(ids('api_key: $MY_VAR'), []);
  assert.deepEqual(ids('api_key: <твой ключ>'), []);
});

test('проза про поле секрета не считается присваиванием', () => {
  assert.deepEqual(ids('service-token: хранится только в player-data.json'), []);
});

test('service-token с литералом ловится', () => {
  const line = fx('"service·-token": "9f8e7d6c5b4a3928·1706f5e4d3c2b1"');
  assert.ok(ids(line).includes('secret-assignment'));
});

test('30-символьная hex-строка ловится', () => {
  // Регрессия: токен Factorio ровно 30 символов, порог 32 его пропускал.
  const line = fx('x 9f8e7d6c5b4a3928·1706f5e4d3c2b1 y');
  assert.ok(ids(line).includes('long-hex'));
});

test('hex рядом с полем хеша не считается секретом', () => {
  const sha = fx('e9217055c51a2b4f26ae1e33ad82a1·36cf1288a0a51322dd8b96dccf99fa7ff9');
  assert.deepEqual(ids(`  index_sha: ${sha}`), []);
  assert.deepEqual(ids(`    synced_sha: ${sha}`), []);
  assert.deepEqual(ids(`"integrity": "sha512-${sha}"`), []);
});

test('файловый путь не принимается за base64', () => {
  // Регрессия: слеш входил в алфавит base64, пути давали ложные находки.
  assert.deepEqual(
    ids(
      '~/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents',
    ),
    [],
  );
});

test('base64 без смешанного регистра и цифр не считается токеном', () => {
  // Буква вне hex-алфавита, иначе сработало бы правило long-hex.
  assert.deepEqual(ids('z'.repeat(50)), []);
  // Смешанный регистр с цифрой — уже похоже на токен.
  assert.ok(ids(`Zz9${'Qq7'.repeat(20)}`).includes('long-base64'));
});

test('абсолютный путь с именем пользователя ловится, заглушка — нет', () => {
  assert.ok(
    ids(fx('/Users·/ivan/.claude/hooks/x.sh')).includes('home-absolute-path'),
  );
  assert.ok(ids(fx('/home·/ivan/project/x')).includes('home-absolute-path'));
  assert.deepEqual(ids('/Users/<user>/.claude/hooks/x.sh'), []);
  assert.deepEqual(ids('~/Library/Application Support/factorio'), []);
});

test('белый список адресов Wube пропускается, прочие — нет', () => {
  for (const email of ALLOWED_EMAILS) {
    assert.deepEqual(ids(`пиши на ${email}`), [], email);
  }
  assert.ok(ids(fx('пиши на ivan.petrov@gmail·.com')).includes('email'));
});

test('scanText нумерует строки от единицы', () => {
  const text = `ок\n${fx('ghp·_AbCdEfGhIjKlMnOpQrStUvWxYz012345')}`;
  const problems = scanText('f.md', text);
  assert.equal(problems.length, 1);
  assert.equal(problems[0]?.line, 2);
});

test('checkFileName ловит запрещённые имена', () => {
  assert.notEqual(checkFileName('player-data.json'), null);
  assert.notEqual(checkFileName('player-data-probe.json'), null);
  assert.notEqual(checkFileName('.env'), null);
  assert.notEqual(checkFileName('.env.local'), null);
  assert.notEqual(checkFileName('certs/server.pem'), null);
  assert.notEqual(checkFileName('secrets/api.key'), null);
});

test('checkFileName пропускает шаблон и обычные файлы', () => {
  assert.equal(checkFileName('.env.example'), null);
  assert.equal(checkFileName('README.md'), null);
  assert.equal(checkFileName('mods/shm-x/info.json'), null);
});

test('находка по имени файла — ошибка, а не замечание', () => {
  const found = checkFileName('player-data.json');
  assert.equal(countErrors(found === null ? [] : [found]), 1);
});

test('isBinaryPath отделяет бинарные расширения', () => {
  assert.equal(isBinaryPath('thumbnail.png'), true);
  assert.equal(isBinaryPath('x.zip'), true);
  assert.equal(isBinaryPath('info.json'), false);
  assert.equal(isBinaryPath('README.md'), false);
});
