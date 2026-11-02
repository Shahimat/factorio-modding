import assert from 'node:assert/strict';
import { join } from 'node:path';
import { test } from 'node:test';

import {
  API_KEY_VAR,
  checkReleasePresent,
  envValueFor,
  isUploadSuccess,
  parseEnvLine,
  parseInitUploadResponse,
  parsePortalError,
  portalErrorHint,
  releasesOf,
  releaseZipPath,
  resolveApiKey,
} from './portal-upload.ts';

// Все значения в тестах — заведомые фейки (convention `secrets`): короткие
// либо с пробелами, никогда не похожие на настоящий ключ портала.

test('обычная строка env-файла разбирается', () => {
  assert.deepEqual(parseEnvLine(`${API_KEY_VAR}=abc123`), {
    key: API_KEY_VAR,
    value: 'abc123',
  });
});

test('префикс export и \\r от правки в Windows отбрасываются', () => {
  assert.deepEqual(parseEnvLine(`export ${API_KEY_VAR}=abc123\r`), {
    key: API_KEY_VAR,
    value: 'abc123',
  });
});

test('значение в кавычках освобождается от них', () => {
  assert.deepEqual(parseEnvLine(`${API_KEY_VAR}="fake key one"`), {
    key: API_KEY_VAR,
    value: 'fake key one',
  });
  assert.deepEqual(parseEnvLine(`${API_KEY_VAR}='abc123'`), {
    key: API_KEY_VAR,
    value: 'abc123',
  });
});

test('комментарии, пустые и сломанные строки дают null', () => {
  for (const line of [
    '',
    '   ',
    '# комментарий',
    `export ${API_KEY_VAR}`,
    '=abc123',
    '=',
  ]) {
    assert.equal(parseEnvLine(line), null, JSON.stringify(line));
  }
});

test('всё после первого = — значение, включая знак = внутри', () => {
  assert.deepEqual(parseEnvLine('OTHER=a=b'), { key: 'OTHER', value: 'a=b' });
});

test('пробелы вокруг ключа и значения убираются', () => {
  assert.deepEqual(parseEnvLine('  OTHER = value99 '), {
    key: 'OTHER',
    value: 'value99',
  });
});

test('пустые значения ключа пропускаются, первое непустое выигрывает', () => {
  const text = [
    '# комментарий',
    'OTHER=не то',
    `${API_KEY_VAR}=`,
    `${API_KEY_VAR}=abc123`,
    `${API_KEY_VAR}=zzz999`,
  ].join('\n');
  assert.equal(envValueFor(text, API_KEY_VAR), 'abc123');
});

test('ключа в файле нет — null', () => {
  assert.equal(envValueFor('OTHER=abc123', API_KEY_VAR), null);
});

test('окружение сильнее env-файлов', () => {
  assert.equal(
    resolveApiKey({
      env: 'from-env',
      files: [`${API_KEY_VAR}=abc123`],
      key: API_KEY_VAR,
    }),
    'from-env',
  );
});

test('env-файлы читаются по порядку: локальный раньше общего', () => {
  assert.equal(
    resolveApiKey({
      env: undefined,
      files: [`${API_KEY_VAR}=local1`, `${API_KEY_VAR}=envone2`],
      key: API_KEY_VAR,
    }),
    'local1',
  );
});

test('пустое значение в окружении — как отсутствие ключа', () => {
  assert.equal(
    resolveApiKey({
      env: '  ',
      files: [`${API_KEY_VAR}=abc123`],
      key: API_KEY_VAR,
    }),
    'abc123',
  );
});

test('нечитаемый env-файл пропускается', () => {
  assert.equal(
    resolveApiKey({
      env: undefined,
      files: [null, `${API_KEY_VAR}=abc123`],
      key: API_KEY_VAR,
    }),
    'abc123',
  );
});

test('нигде нет — null', () => {
  assert.equal(
    resolveApiKey({ env: undefined, files: [null, ''], key: API_KEY_VAR }),
    null,
  );
});

test('путь zip из info.json: dist/<name>_<version>.zip', () => {
  assert.equal(
    releaseZipPath(
      join('/repo', 'dist'),
      { name: 'shm-orbital-logistics', version: '0.1.1' },
    ),
    join('/repo', 'dist', 'shm-orbital-logistics_0.1.1.zip'),
  );
});

test('upload_url разбирается из ответа init_upload', () => {
  assert.deepEqual(
    parseInitUploadResponse('{"upload_url":"https://uploads.factorio.com/m/42"}'),
    { uploadUrl: 'https://uploads.factorio.com/m/42' },
  );
});

test('поле url вместо upload_url не принимается', () => {
  // Регрессия на путаницу имён: у портала поле называется upload_url.
  assert.equal(
    parseInitUploadResponse('{"url":"https://uploads.factorio.com/m/42"}'),
    null,
  );
});

test('не-JSON и пустой ответ init_upload — null', () => {
  assert.equal(parseInitUploadResponse('<html>boom</html>'), null);
  assert.equal(parseInitUploadResponse(''), null);
});

test('успех загрузки — ровно булево {"success": true}', () => {
  assert.equal(isUploadSuccess('{"success": true}'), true);
  assert.equal(isUploadSuccess('{"success": "true"}'), false);
  assert.equal(isUploadSuccess('{"error":"InvalidModRelease"}'), false);
  assert.equal(isUploadSuccess('не JSON'), false);
});

test('код и message из JSON-ошибки портала', () => {
  assert.deepEqual(
    parsePortalError('{"error":"InvalidApiKey","message":"bad key"}'),
    { code: 'InvalidApiKey', detail: 'bad key' },
  );
});

test('без message в ошибке — кусочек сырого тела', () => {
  const info = parsePortalError('{"error":"Forbidden"}');
  assert.equal(info.code, 'Forbidden');
  assert.equal(info.detail, '{"error":"Forbidden"}');
});

test('не-JSON ответ — код Unknown и тело целиком-куском', () => {
  assert.deepEqual(parsePortalError('<html>Bad Gateway</html>'), {
    code: 'Unknown',
    detail: '<html>Bad Gateway</html>',
  });
});

test('длинное тело ошибки обрезается', () => {
  assert.equal(parsePortalError('x'.repeat(500)).detail.length, 200);
});

test('подсказки есть для известных кодов ошибок', () => {
  for (const code of [
    'InvalidApiKey',
    'Forbidden',
    'InvalidModRelease',
    'InvalidModUpload',
    'UnknownMod',
    'InternalError',
    'Unknown',
  ]) {
    assert.ok(portalErrorHint(code) !== null, code);
  }
  assert.equal(portalErrorHint('NoSuchCode'), null);
});

const RELEASES = [
  { version: '0.1.0', factorioVersion: '2.0' },
  { version: '0.1.1', factorioVersion: '2.0' },
] as const;

test('релизы разбираются из публичного ответа /api/mods/<name>', () => {
  assert.deepEqual(
    releasesOf({
      name: 'shm-orbital-logistics',
      releases: [
        { version: '0.1.0', info_json: { factorio_version: '2.0' } },
        {
          version: '0.1.1',
          info_json: { factorio_version: '2.0', engine_version: '2.0.60' },
        },
      ],
    }),
    [
      { version: '0.1.0', factorioVersion: '2.0' },
      { version: '0.1.1', factorioVersion: '2.0' },
    ],
  );
});

test('релиз без info_json — factorioVersion undefined', () => {
  assert.deepEqual(releasesOf({ releases: [{ version: '0.1.1' }] }), [
    { version: '0.1.1', factorioVersion: undefined },
  ]);
});

test('кривой ответ публичного API даёт пустой список, а не падение', () => {
  assert.deepEqual(releasesOf(undefined), []);
  assert.deepEqual(releasesOf('нет'), []);
  assert.deepEqual(releasesOf({}), []);
  assert.deepEqual(releasesOf({ releases: 'нет' }), []);
  assert.deepEqual(releasesOf({ releases: [{ version: 3 }, 'мусор'] }), []);
});

test('версия есть и дорожка совпала — успех', () => {
  assert.deepEqual(checkReleasePresent(RELEASES, '0.1.1', '2.0'), { ok: true });
});

test('версии нет — неудача с перечислением того, что на портале', () => {
  const verdict = checkReleasePresent(RELEASES, '0.1.2', '2.0');
  assert.equal(verdict.ok, false);
  if (!verdict.ok) {
    assert.match(verdict.reason, /0\.1\.2/);
    assert.match(verdict.reason, /0\.1\.0, 0\.1\.1/);
  }
});

test('пустой список релизов — отдельная причина', () => {
  const verdict = checkReleasePresent([], '0.1.1', '2.0');
  assert.equal(verdict.ok, false);
  if (!verdict.ok) assert.match(verdict.reason, /пуст/);
});

test('версия есть, дорожка не та — неудача с обеими дорожками', () => {
  const verdict = checkReleasePresent(RELEASES, '0.1.1', '1.1');
  assert.equal(verdict.ok, false);
  if (!verdict.ok) {
    assert.match(verdict.reason, /"2\.0"/);
    assert.match(verdict.reason, /"1\.1"/);
  }
});
