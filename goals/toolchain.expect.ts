import { crit, describe, warn } from '@shahimat/ai-core/expect';

// Инструментальный контур репозитория. Описание — entity repo-toolchain.
// Публикация необратима: первый выпуск руками по manual publish-new-mod;
// FMTK Publish сам делает git commit, тег и push — не используем.
describe('goal: toolchain', () => {
  describe('ticket: toolchain', () => {
    crit.todo('link-local: симлинк мода или прототипа в каталог модов игры — npm run link-local -- <путь>');
    crit.todo('FMTK настроен вместо своего publish — manual setup-dev-environment, раздел «Редактор»');
    crit.todo('check-docs-layers и check-docs-context параметризованы корнем вместо константы REPO_ROOT и покрыты тестами');
    warn.todo('validate и pack прогнаны на первом реальном моде, verified у mod-zip-matches-portal-rules переподтверждён');
  });

  // Релиз 0.1.1 shm-orbital-logistics 2026-11-03 шёл одноразовым скриптом из
  // /tmp — владелец запретил: публикация только командами из репозитория.
  describe('ticket: tool-publish-command', () => {
    crit.todo('npm run publish:mod -- <mod-key> из корня публикует dist/<name>_<version>.zip: init_upload → загрузка → {"success": true}; нет zip — подсказка собрать через npm run pack');
    crit.todo('после загрузки инструмент проверяет публичным API, что версия появилась с ожидаемой factorio_version, с повторными попытками');
    crit.todo('ключ FACTORIO_UPLOAD_API_KEY берётся из окружения или .env.local/.env в корне (префикс export, кавычки, \\r); ключ не печатается и не попадает в сообщения об ошибках; нет ключа — понятная подсказка');
    crit.todo('ошибки портала (InvalidApiKey, InvalidModRelease, Forbidden и др.) выводятся с текстом; git-действий и правки страницы мода в инструменте нет');
    crit.todo('чистые функции (разбор env-строки, путь zip, разбор upload_url, сверка версии) в tools/lib покрыты node:test — npm test зелёный');
    crit.todo('npm run check зелёный');
  });
});
