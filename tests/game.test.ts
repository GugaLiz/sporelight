import test from 'node:test';
import assert from 'node:assert/strict';
import { LEVELS, getLevel, totalSpores } from '../src/app/game/levels';
import { GameModel } from '../src/app/game/model';
import { createDefaultSave, normalizeSave, persistSave, loadSave } from '../src/app/save';
const walk = (model: GameModel, id: string) => {
  const route = model.pathTo(id); assert.ok(route, `Path to ${id}`);
  for (const step of route.slice(1)) assert.ok(model.move(step).ok);
};
for (const level of LEVELS) test(`${level.id} ${level.title}: all collectibles, mechanisms, exit and three stars`, () => {
  const model = new GameModel(level);
  assert.equal(new Set(level.nodes.map(n => n.id)).size, level.nodes.length);
  for (let round = 0; round < 30 && !model.state.completed; round++) {
    const collectible = level.nodes.find(n => n.spore && !model.state.collected.includes(n.id) && model.pathTo(n.id));
    if (collectible) { walk(model, collectible.id); continue; }
    const mechanism = level.nodes.find(n => n.mechanism && !model.state.activated.includes(n.id) && model.pathTo(n.id));
    if (mechanism) {
      walk(model, mechanism.id);
      for (let tries = 0; tries < 3 && !model.state.activated.includes(mechanism.id); tries++) assert.ok(model.interact(0).ok);
      assert.ok(model.state.activated.includes(mechanism.id));
      continue;
    }
    walk(model, level.exit);
  }
  assert.equal(model.state.completed, true);
  assert.equal(model.state.collected.length, totalSpores(level));
  assert.equal(model.stars, 3);
  assert.equal(model.state.activated.length, level.nodes.filter(n => n.mechanism).length);
  assert.equal(model.interact().ok, false, 'Completed games cannot mutate');
});
test('Locked bridge cannot be bypassed, then planting unlocks it', () => {
  const model = new GameModel(getLevel('1-2')); walk(model, 'n0');
  assert.equal(model.pathTo('n1'), null); assert.equal(model.move('n1').ok, false);
  assert.equal(model.interact().ok, true); assert.ok(model.pathTo('n1'));
  assert.equal(model.interact().ok, false, 'No duplicate planting');
});
test('Ordinary level can finish without all spores and has truthful rating', () => {
  const model = new GameModel(getLevel('1-1')); walk(model, 'n4');
  assert.equal(model.state.completed, true); assert.equal(model.state.collected.length, 2); assert.equal(model.stars, 2);
});
test('Undo restores collection and growth without duplicating rewards', () => {
  const model = new GameModel(getLevel('1-2')); const initial = model.snapshot(); walk(model, 'n0');
  model.interact(); model.undo(); assert.equal(model.state.activated.length, 0);
  model.undo(); assert.deepEqual(model.snapshot(), initial);
  walk(model, 'n0'); walk(model, 'start'); walk(model, 'n0'); assert.equal(model.state.collected.length, 1);
});
test('Rain windows reject at 2000ms, accept next cycle; reduced motion bypasses timing', () => {
  const model = new GameModel(getLevel('2-3')); walk(model, 'n0'); const previous = model.snapshot();
  assert.equal(model.interact(2000).ok, false); assert.deepEqual(model.snapshot(), previous);
  assert.equal(model.interact(3001).ok, true); model.undo(); assert.equal(model.interact(2000, true).ok, true);
});
test('Reflection needs correct orientation; wrong orientation does not open gate', () => {
  const model = new GameModel(getLevel('2-2')); walk(model, 'n0'); model.interact(); walk(model, 'n1');
  assert.equal(model.interact().ok, true); assert.equal(model.edgeOpen('n1', 'n2'), false);
  assert.equal(model.interact().ok, true); assert.equal(model.edgeOpen('n1', 'n2'), true);
});
test('Finale requires all eight spores before sequence, then rejects wrong order', () => {
  const model = new GameModel(getLevel('3-4')); walk(model, 's1'); assert.equal(model.interact().ok, false);
  for (const n of model.level.nodes.filter(n => n.spore)) walk(model, n.id);
  walk(model, 's3'); const previous = model.snapshot(); assert.equal(model.interact().ok, false); assert.deepEqual(model.snapshot(), previous);
  assert.equal(model.pathTo('end'), null);
  for (const id of ['s1', 's3', 's5', 's7']) { walk(model, id); assert.equal(model.interact().ok, true); }
  walk(model, 'end'); assert.equal(model.state.completed, true);
});
test('Serialized in-progress game restores position, spores and gate state', () => {
  const level = getLevel('1-3'); const model = new GameModel(level); walk(model, 'n0'); model.interact(); walk(model, 'n1');
  const restored = new GameModel(level, JSON.parse(JSON.stringify(model.snapshot()))); assert.deepEqual(restored.snapshot(), model.snapshot());
  assert.ok(restored.pathTo('start')); assert.equal(restored.pathTo('n2'), null);
});
test('Malformed runs and save fields cannot crash or expose locked chapters', () => {
  const defaultSave = createDefaultSave();
  for (const invalid of [null, [], 3, 'hello', { levels: null, settings: [] }, { levels: { '3-4': { completed: true, unlocked: true } }, lastLevel: '3-4', playerName: '<script>' }]) {
    const save = normalizeSave(invalid); assert.equal(save.levels['1-1'].unlocked, true); assert.equal(save.levels['3-4'].unlocked, false); assert.equal(save.lastLevel, '1-1');
  }
  const save = normalizeSave({ ...defaultSave, run: { levelId: '1-1', node: 'n0', collected: 4, activated: 'wrong', angles: null } });
  assert.equal(save.run?.node, 'n0'); assert.deepEqual(save.run?.collected, []);
  const model = new GameModel(getLevel('1-3'), { levelId: '1-3', node: 'n3', activated: [], collected: ['unknown', 'n0', 'n0'] });
  assert.equal(model.state.node, 'start'); assert.deepEqual(model.state.collected, ['n0']);
});
test('Legacy valley completion migrates to first level; settings are clamped', () => {
  const save = normalizeSave({ playerName: '茸茸', hasNamed: true, levels: { valley: { completed: true, bestStars: 3 } }, settings: { bgm: 5, sfx: -4, ambient: 'bad' } });
  assert.equal(save.playerName, '茸茸'); assert.equal(save.levels['1-1'].completed, true); assert.equal(save.levels['1-2'].unlocked, true);
  assert.equal(save.settings.bgm, 1); assert.equal(save.settings.sfx, 0); assert.equal(save.settings.ambient, .25);
});
test('Blocked storage returns false, bad JSON falls back to a fresh save', () => {
  Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: { setItem() { throw Error('Quota'); }, getItem() { return '{broken'; } } });
  assert.equal(persistSave(createDefaultSave()), false); assert.equal(loadSave().lastLevel, '1-1');
});
