import { crit, describe } from '@shahimat/ai-core/expect';

// specs/03102026_spec_logistic_buildings.md · план: plans/logistic-buildings/iter-01.html §1.2
// Стенд для тестов внутри игры: фреймворк из существующих по двум условиям
// convention testing (обе дорожки 2.0/2.1, запуск без графики); не проходит —
// минимальный свой стенд (допущение плана, ~двойной объём).
describe('goal: lb-ingame-stand', () => {
  describe('ticket: lb-ingame-stand', () => {
    crit.todo('стенд запускается одной командой без графики и падает с ненулевым кодом — npm run test:ingame');
    crit.todo('демонстрационный сценарий зелёный: сущности созданы, тики промотаны, результат сверен');
    crit.todo('выбор фреймворка и отвергнутые альтернативы записаны в entity repo-toolchain — npm run check-docs');
  });
});
