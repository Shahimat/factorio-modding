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
  const sha = fx('e9217055c51a2b4f·26ae1e33ad82a136·cf1288a0a51322dd·8b96dccf99fa7ff9');
  assert.deepEqual(ids(`  index_sha: ${sha}`), []);
  assert.deepEqual(ids(`    synced_sha: ${sha}`), []);
  assert.deepEqual(ids(`"integrity": "sha512-${sha}"`), []);
});

test('строка «имя: чистый hex» — SHA-чекпоинт контракта, не секрет', () => {
  // sync.contract.parts и manifest'ы модулей держат SHA значением ключа.
  // Фикстура с · — чтобы сам тест не поймал свой литерал.
  const sha = fx('4afe17218d9044d8cc1ee0f873f3·df239fa53e94eb8c836dac257906e·df7a109');
  assert.deepEqual(ids(`  contract-setup: ${sha}`), []);
  assert.deepEqual(ids(`    domain: ${sha}`), []);
  // Секретный ключ ловится правилом присваивания независимо от формы значения.
  const line = 'api_key·: ${sha}'.replace('·', '').replace('${sha}', sha);
  assert.ok(ids(line).includes('secret-assignment'));
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

// Синтетические checksum/token значения собираются только в runtime.
const checksum = 'a1b2c3d4'.repeat(8);
const commit = 'a1b2c3d4'.repeat(5);
const otherHex = 'c9d8e7f6'.repeat(8);
const publicRaw = `https://raw.githubusercontent.com/Shahimat/ai-prompts/${commit}/prompts/modules/domain.md`;

test('публичный ai-prompts commit pin разрешён только в точном URL segment', () => {
  assert.deepEqual(ids(`source: ${publicRaw}`), []);
  for (const url of [
    publicRaw.replace('https:', 'http:'),
    publicRaw.replace('raw.githubusercontent.com', 'raw.githubusercontent.com.evil.test'),
    publicRaw.replace('Shahimat', 'another-owner'),
    publicRaw.replace('ai-prompts', 'another-repo'),
    publicRaw.replace(commit, checksum),
    `https://example.test/?redirect=${publicRaw}`,
    `https://raw.githubusercontent.com/Shahimat/ai-prompts/main/file?ref=${commit}`,
  ]) {
    assert.ok(ids(url).includes('long-hex'), url);
  }
});

test('Markdown SHA checksum column с inline или соседним label разрешена', () => {
  assert.deepEqual(ids(`${checksum}  file.md SHA-256`), []);
  for (const label of ['SHA-256', 'SHA локального index.yml:']) {
    assert.deepEqual(scanText('evidence.md', `${label}\n\`${checksum}\`.`), []);
  }
  assert.deepEqual(scanText('evidence.md',
    `## File-content SHA-256\n\n\`\`\`text\n${checksum}  startup\n${otherHex}  closeout\n\`\`\``), []);
});

test('bare hex, assignments и неверная checksum column не получают исключение', () => {
  for (const text of [
    checksum,
    `ordinary text\n\`${checksum}\``,
    `SHA-256\nvalue=${checksum}`,
    `SHA-256\nrandom ${checksum}`,
    `SHA-256\n${commit}  short`,
    `SHA-256\n${checksum}abcd  too-long`,
    `SHA-256\n${checksum}/not-a-column`,
    `SHA-256\n\`\`\`js\n${checksum}\n\`\`\``,
    `SHA-256\n\n\n${checksum}`,
    `SHA-256\n\`\`\`text\n${checksum}\n\`\`\`\n${otherHex}`,
  ]) {
    assert.ok(scanText('f.md', text).some((p) => p.message.includes('[long-hex]')), text);
  }
  assert.ok(scanText('f.ts', `SHA-256\n${checksum}`).some((p) => p.message.includes('[long-hex]')));
});

test('commit pin не скрывает query credentials или второй hex на строке', () => {
  assert.ok(ids(`${publicRaw}?token=${otherHex}`).includes('long-hex'));
  const querySecret = fx('?api·_key=');
  assert.ok(ids(`${publicRaw}${querySecret}${otherHex}`).includes('secret-assignment'));
  assert.ok(ids(`${publicRaw} ${otherHex}`).includes('long-hex'));
  assert.ok(ids(publicRaw.replace('https://', fx('https·://user:password1234@')))
    .includes('url-embedded-credentials'));
});

test('SHA label не скрывает token assignment, второй hex или base64', () => {
  for (const assignment of ['api_key', 'service-token', 'password']) {
    assert.ok(scanText('f.md', `SHA-256\n${assignment}=${checksum}`)
      .some((p) => p.message.includes('[secret-assignment]')));
  }
  assert.ok(ids(`${checksum}  SHA-256 ${otherHex}`).includes('long-hex'));
  assert.ok(ids(`${checksum}  SHA-256 Zz9${'Qq7'.repeat(20)}`).includes('long-base64'));
});

test('checksum occurrence не скрывает известный token или private home path', () => {
  const token = fx('ghp·_AbCdEfGhIjKlMnOpQrStUvWxYz012345');
  const home = fx('/Users·/ivan/project/');
  for (const prefix of [`${checksum}  SHA-256`, publicRaw, `hash: ${checksum}`]) {
    assert.ok(ids(`${prefix} ${token}`).includes('github-token'));
    assert.ok(ids(`${prefix} ${home}`).includes('home-absolute-path'));
  }
  const block = `SHA-256\n\`\`\`text\n${checksum}  ${home}\n${otherHex}  ${token}\n\`\`\``;
  const found = scanText('f.md', block);
  assert.ok(found.some((p) => p.message.includes('[home-absolute-path]')));
  assert.ok(found.some((p) => p.message.includes('[github-token]')));
});

test('поле hash исключает только своё значение, не остальные hex/base64', () => {
  assert.ok(ids(`hash: ${checksum}, other: ${otherHex}`).includes('long-hex'));
  assert.ok(ids(`hash: ${checksum}, other: Zz9${'Qq7'.repeat(20)}`).includes('long-base64'));
  assert.deepEqual(ids(`{"hash":"${checksum}","public_hash":"${otherHex}"}`), []);
  const sri = `sha512-Zz9${'Qq7'.repeat(16)}/DG0${'aB2'.repeat(16)}==`;
  assert.deepEqual(ids(`"integrity": "${sri}"`), []);
  assert.ok(ids(`"integrity": "${sri}", "other": "${otherHex}"`).includes('long-hex'));
  assert.ok(ids(`hash: ${publicRaw}?token=${otherHex}`).includes('long-hex'));
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
