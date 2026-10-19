export type Chapter = 'valley' | 'pond' | 'cave';
export type Mechanism = 'grow' | 'vine' | 'lily' | 'reflect' | 'rhythm' | 'light' | 'friend' | 'sequence';
export interface WorldNode { id: string; x: number; y: number; spore?: boolean; mechanism?: Mechanism; order?: number; angle?: number }
export interface WorldEdge { from: string; to: string; gate?: string }
export interface Level { id: string; chapter: Chapter; title: string; subtitle: string; nodes: WorldNode[]; edges: WorldEdge[]; exit: string; rewards: string[]; allSpores?: boolean }
export const CHAPTERS: { id: Chapter; title: string; english: string; description: string }[] = [
  { id: 'valley', title: '苔藓山谷', english: 'THE MOSSY VALE', description: '每一粒微光，都有生长的方向。' },
  { id: 'pond', title: '雨滴池塘', english: 'THE DROPLET POND', description: '听，雨落下的地方，有新的回响。' },
  { id: 'cave', title: '星光洞穴', english: 'THE STARLIGHT GROTTO', description: '原来，你也是这片星光的一部分。' },
];

function trail(id: string, chapter: Chapter, title: string, subtitle: string, count: number, mechanisms: Mechanism[], rewards: string[]): Level {
  const nodes: WorldNode[] = [{ id: 'start', x: 155, y: 470 }];
  const edges: WorldEdge[] = [];
  // Five main stepping stones; side paths preserve optional exploration.
  const layouts = [
    { points: [[330, 440], [500, 330], [680, 410], [850, 300], [1060, 360]], sides: [[330, 275], [680, 235]] },
    { points: [[300, 350], [475, 455], [660, 340], [850, 440], [1060, 300]], sides: [[290, 215], [650, 205]] },
    { points: [[330, 460], [500, 340], [690, 285], [870, 420], [1080, 340]], sides: [[330, 285], [850, 210]] },
    { points: [[320, 320], [495, 430], [675, 350], [855, 460], [1070, 330]], sides: [[300, 195], [680, 210]] },
  ];
  const { points, sides } = layouts[(Number(id.split('-')[1]) - 1) % layouts.length];
  points.forEach(([x, y], i) => {
    const mechanism = mechanisms[i];
    const node: WorldNode = { id: `n${i}`, x, y, mechanism, angle: mechanism === 'reflect' ? (i % 2) + 1 : undefined };
    nodes.push(node);
    edges.push({ from: i === 0 ? 'start' : `n${i - 1}`, to: node.id, gate: i > 0 && mechanisms[i - 1] ? `n${i - 1}` : undefined });
  });
  nodes.push({ id: 'side0', x: sides[0][0], y: sides[0][1] }, { id: 'side1', x: sides[1][0], y: sides[1][1] });
  edges.push({ from: 'n0', to: 'side0' }, { from: 'n2', to: 'side1' });
  ['n0', 'side0', 'n1', 'side1', 'n2', 'n3'].slice(0, count).forEach(key => { nodes.find(n => n.id === key)!.spore = true; });
  return { id, chapter, title, subtitle, nodes, edges, exit: 'n4', rewards };
}

export const LEVELS: Level[] = [
  trail('1-1', 'valley', '初生的孢子', '跟着微光走一走，去看看那朵沉睡的花。', 3, [], ['flowerbud']),
  trail('1-2', 'valley', '第一朵花', '在土地旁播种，让花瓣接住前方的路。', 2, ['grow'], ['flowerbud']),
  trail('1-3', 'valley', '苔藓山谷', '唤醒两段藤蔓，让彼此遥望的石台相连。', 3, ['vine', 'vine'], ['vine']),
  trail('1-4', 'valley', '鼹鼠的家', '让蜜源花盛开，请小伙伴为你让出道路。', 3, ['friend', 'grow'], ['bug', 'arch']),
  trail('2-1', 'pond', '池塘之声', '唤醒睡莲，轻轻跃过安静的水面。', 3, ['lily', 'lily'], ['lilypad']),
  trail('2-2', 'pond', '涟漪之谜', '旋转反光叶，让微光照向下一块石台。', 4, ['reflect', 'reflect'], ['moss']),
  trail('2-3', 'pond', '雨滴节拍', '等水膜亮起时播种，错过也可以等下一场雨。', 4, ['rhythm', 'rhythm'], ['lilypad']),
  trail('2-4', 'pond', '池塘守护者', '依次唤醒三朵蜜源花，让光虫解开藤蔓。', 5, ['friend', 'friend', 'friend'], ['bug']),
  trail('3-1', 'cave', '微光引路', '唤醒三片苔藓，给洞穴留下一盏盏灯。', 4, ['light', 'light', 'light'], ['moss', 'mushroom']),
  trail('3-2', 'cave', '影子的形状', '调整光线，再点亮苔藓，让影子连接成桥。', 4, ['reflect', 'light'], ['arch']),
  trail('3-3', 'cave', '共生之歌', '睡莲、藤蔓与苔藓，会一起带你走向微光。', 6, ['lily', 'vine', 'light'], ['mushroom']),
  {
    id: '3-4', chapter: 'cave', title: '沉睡的守护者', subtitle: '收集八粒孢子，再按 ① → ② → ③ → ④ 点亮星光。',
    nodes: [
      { id: 'start', x: 630, y: 470 },
      { id: 's0', x: 450, y: 500, spore: true }, { id: 's1', x: 280, y: 470, spore: true, mechanism: 'sequence', order: 1 },
      { id: 's2', x: 440, y: 350, spore: true }, { id: 's3', x: 300, y: 250, spore: true, mechanism: 'sequence', order: 2 },
      { id: 's4', x: 800, y: 350, spore: true }, { id: 's5', x: 950, y: 250, spore: true, mechanism: 'sequence', order: 3 },
      { id: 's6', x: 810, y: 500, spore: true }, { id: 's7', x: 980, y: 470, spore: true, mechanism: 'sequence', order: 4 },
      { id: 'end', x: 630, y: 235 },
    ],
    edges: [
      { from: 'start', to: 's0' }, { from: 's0', to: 's1' }, { from: 'start', to: 's2' }, { from: 's2', to: 's3' },
      { from: 'start', to: 's4' }, { from: 's4', to: 's5' }, { from: 'start', to: 's6' }, { from: 's6', to: 's7' },
      { from: 'start', to: 'end', gate: 's7' },
    ], exit: 'end', rewards: ['starflower'], allSpores: true,
  },
];
export const getLevel = (id: string) => LEVELS.find(level => level.id === id) ?? LEVELS[0];
export const totalSpores = (level: Level) => level.nodes.filter(n => n.spore).length;
export const mechanismName: Record<Mechanism, string> = { grow: '萌芽花台', vine: '藤蔓', lily: '睡莲', reflect: '反光叶', rhythm: '雨滴睡莲', light: '发光苔藓', friend: '蜜源花', sequence: '仪式光点' };
