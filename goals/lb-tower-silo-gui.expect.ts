import { crit, describe, warn } from '@shahimat/ai-core/expect';

// specs/03102026_spec_logistic_buildings.md · план: plans/logistic-buildings/iter-01.html §1.6
// Башня, шахта и панель у окна здания: три возможности, которые либо есть
// в API, либо выпадают из мода. Внешний вид панели — глазами в
// lb-session-facts; здесь ответ бинарный: привязка есть или нет.
describe('goal: lb-tower-silo-gui', () => {
  describe('ticket: lb-tower-silo-gui', () => {
    crit.todo('сельскохозяйственная башня: хранилища семян и урожая, продукт по семени — зелёные на стенде');
    crit.todo('ракетная шахта: детали загружаются скриптом, признак «ракета собрана» — зелёные на стенде');
    crit.todo('пробная панель привязывается к штатному окну: производящие, печи, лаборатории, буры, котлы, реакторы, турели');
    warn.todo('сборка без Space Age не роняет прототип — башня и шахта пропускаются: node tools/lua-test.ts ./poc/shm-logistic-buildings-probe');
  });
});
