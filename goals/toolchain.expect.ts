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
});
