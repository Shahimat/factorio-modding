import { crit, describe } from '@shahimat/ai-core/expect';

// specs/03102026_spec_logistic_buildings.md · план: plans/logistic-buildings/iter-01.html §1.1
// Каркас прототипа: пакет poc/shm-logistic-buildings-probe вне mods/ —
// консольная команда запуска проверок и единый формат строки отчёта.
describe('goal: lb-probe-frame', () => {
  describe('ticket: lb-probe-frame', () => {
    crit.todo('исходники прототипа проходят линтер Lua — npm run check-lua -- poc/shm-logistic-buildings-probe');
    crit.todo('прототип загружается в игре; /shm-probe отвечает списком проверок и строкой версии');
  });
});
