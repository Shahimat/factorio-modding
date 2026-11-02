import { crit, describe, warn } from '@shahimat/ai-core/expect';

// specs/03102026_spec_logistic_buildings.md · план: plans/logistic-buildings/iter-01.html §1.4
// Запросы логистической сети: на чтении чужих запросов стоит весь расчёт
// спроса. Буферный сундук обязан отличаться от обычного — ошибка даёт лишнюю
// партию на каждом уровне цепочки.
describe('goal: lb-network-requests', () => {
  describe('ticket: lb-network-requests', () => {
    crit.todo('точки запроса сети: запросы, содержимое, количество в пути — зелёные на стенде');
    crit.todo('буферный сундук отличён от обычного, персонажи в списке проверены — зелёные на стенде');
    crit.todo('событие смены запроса: вручную на сундуке и правкой логистической группы — поймано на стенде');
    warn.todo('разбор ответа сети в сводку — чистая функция с тестом: node tools/lua-test.ts ./poc/shm-logistic-buildings-probe');
  });
});
