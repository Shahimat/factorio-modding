import { crit, describe } from '@shahimat/ai-core/expect';

// specs/03102026_spec_logistic_buildings.md · план: plans/logistic-buildings/iter-01.html §1.7
// Сеанс в игре и запись фактов: закрывает то, чего стенд не отвечает, и
// переносит выясненное в namespace engine по convention engine-facts.
// Дизайн молча не меняется: обходы непройденных проверок — на решение владельца.
describe('goal: lb-session-facts', () => {
  describe('ticket: lb-session-facts', () => {
    crit.todo('весь набор прогнан в игре со Space Age (/shm-probe all); лог прогона в .work/proofs/logistic-buildings/lb-session-facts/');
    crit.todo('панель и навязчивость предупреждений оценены глазами; скриншоты и число предупреждений — в пруф d2');
    crit.todo('факты записаны в namespace engine с версией игры, отличия 2.1 по официальной документации выписаны — npm run check-docs');
    crit.todo('по каждой непройденной проверке предложен обход одним блоком владельцу; сверб с отчётом прогона');
  });
});
