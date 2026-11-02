import { crit, describe, warn } from '@shahimat/ai-core/expect';

// specs/03102026_spec_logistic_buildings.md · план: plans/logistic-buildings/iter-01.html §1.5
// Расходники и призраки запроса: так доставляются топливо, патроны и семена.
// Навязчивость предупреждения «нечем выполнить» глазами — в lb-session-facts.
describe('goal: lb-request-proxy', () => {
  describe('ticket: lb-request-proxy', () => {
    crit.todo('призрак запроса создаётся скриптом с указанием инвентаря и слота — зелёный на стенде');
    crit.todo('свои строки дописываются в чужой призрак без порчи; несколько призраков на здании — зелёные на стенде');
    crit.todo('невыполненный остаток читается, запрос на изъятие и снятие своих строк работают — зелёные на стенде');
    warn.todo('сборка плана вставки — чистая функция с тестом: node tools/lua-test.ts ./poc/shm-logistic-buildings-probe');
  });
});
