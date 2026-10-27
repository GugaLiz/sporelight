export type Chapter = 'valley' | 'pond' | 'cave';
export type Mechanism = 'grow' | 'vine' | 'lily' | 'reflect' | 'rhythm' | 'light' | 'friend' | 'sequence' | 'switch' | 'water';
export interface WorldNode { id: string; x: number; y: number; spore?: boolean; mechanism?: Mechanism; label?: string; order?: number; angle?: number; targets?: string[]; water?: boolean }
export interface WorldEdge { from: string; to: string; gate?: string; when?: [string, string]; jump?: boolean; beam?: boolean; companion?: string; needs?: string[] }
export interface Level { id: string; chapter: Chapter; title: string; subtitle: string; nodes: WorldNode[]; edges: WorldEdge[]; exit: string; rewards: string[]; allSpores?: boolean; kind: string; seedBudget?: number; required?: string[]; companion?: string[]; melody?: string[]; beam?: [string, string]; fog?: boolean; sequence?: string[] }
export const CHAPTERS = [
  { id: 'valley', title: '苔藓山谷', english: 'THE MOSSY VALE', description: '借一粒种子，让不同的生命相遇。' },
  { id: 'pond', title: '雨滴池塘', english: 'THE DROPLET POND', description: '选好落点，让光、雨与伙伴带路。' },
  { id: 'cave', title: '星光洞穴', english: 'THE STARLIGHT GROTTO', description: '在光影之间，找回星空的记忆。' },
] as const;
const n = (id: string, x: number, y: number, label: string, mechanism?: Mechanism, spore = false, targets?: string[]): WorldNode => ({ id,x,y,label,mechanism,spore,targets });
const e = (from: string, to: string, extra: Partial<WorldEdge> = {}): WorldEdge => ({from,to,...extra});
export const LEVELS: Level[] = [
  { id:'1-1',chapter:'valley',title:'初生的孢子',kind:'自由探索',subtitle:'先熟悉移动。花苞在远处，支路上的微光可以慢慢找。',rewards:['flowerbud'],exit:'end',
    nodes:[n('start',150,470,'起点'),n('fork',360,430,'岔路',undefined,true),n('fern',470,295,'蕨叶小径',undefined,true),n('stone',700,450,'暖石',undefined,true),n('end',980,350,'终点花苞')],edges:[e('start','fork'),e('fork','fern'),e('fork','stone'),e('stone','end')] },
  { id:'1-2',chapter:'valley',title:'第一朵花',kind:'一粒种子 · 回收再种',subtitle:'只有一粒可用种子。先去北边取花粉，回来回收花台，再种到东边。',rewards:['flowerbud'],exit:'end',seedBudget:1,required:['pollen'],
    nodes:[n('start',160,460,'起点'),n('north',390,340,'北边花床','grow'),n('pollen',620,285,'花粉',undefined,true),n('east',410,495,'东边花床','grow'),n('end',930,440,'终点花苞',undefined,true)],edges:[e('start','north'),e('start','east'),e('north','east'),e('north','pollen',{gate:'north'}),e('east','end',{gate:'east',needs:['pollen']})] },
  { id:'1-3',chapter:'valley',title:'苔藓山谷',kind:'藤桥转向 · 往返规划',subtitle:'藤桥一次只能接一边。找到两枚叶印后，再接通归途。',rewards:['vine'],exit:'end',required:['dew','leaf'],
    nodes:[n('start',160,470,'起点'),n('pivot',490,415,'藤桥根部','vine',false,['dew','leaf','end']),n('dew',740,285,'露水叶印',undefined,true),n('leaf',790,490,'苔藓叶印',undefined,true),n('end',1070,390,'归途',undefined,true)],edges:[e('start','pivot'),e('pivot','dew',{when:['pivot','dew']}),e('pivot','leaf',{when:['pivot','leaf']}),e('pivot','end',{when:['pivot','end'],needs:['dew','leaf']})] },
  { id:'1-4',chapter:'valley',title:'鼹鼠的家',kind:'花香引路 · 伙伴让道',subtitle:'伙伴堵在家门口。先用近处花香吸引它，再引到花园；它不会一次走太远。',rewards:['bug','arch'],exit:'end',companion:['home','near','garden'],
    nodes:[n('start',160,460,'起点'),n('home',550,440,'家门'),n('near',390,290,'近处蜜花','friend',true),n('garden',770,280,'安静花园','friend',true),n('end',990,450,'林间出口',undefined,true)],edges:[e('start','home'),e('start','near'),e('near','garden'),e('home','end',{companion:'garden'})] },
  { id:'2-1',chapter:'pond',title:'池塘之声',kind:'睡莲跳跃 · 选择落点',subtitle:'水面没有路。选择睡莲的落点，收集两枚水滴，再跳到彼岸。',rewards:['lilypad'],exit:'end',required:['west','east'],
    nodes:[n('start',180,430,'起岸','lily',false,['west','east','end']),n('west',510,290,'左侧水滴','lily',true,['start','east']),n('east',700,475,'右侧水滴','lily',true,['start','west','end']),n('end',1020,350,'彼岸')],edges:[e('start','west',{jump:true}),e('start','east',{jump:true}),e('west','east',{jump:true}),e('east','end',{jump:true}),e('start','end',{jump:true})] },
  { id:'2-2',chapter:'pond',title:'涟漪之谜',kind:'连续光路 · 双镜反射',subtitle:'把光源 → 第一片叶 → 第二片叶 → 水晶连成一条光路。镜子转走后，光桥也会消失。',rewards:['moss'],exit:'end',beam:['mirrorA','crystal'],
    nodes:[n('start',150,480,'起点'),n('mirrorA',360,330,'第一片反光叶','reflect',true,['pool','mirrorB']),n('pool',600,270,'静水池'),n('mirrorB',680,450,'第二片反光叶','reflect',true,['mirrorA','pool','crystal']),n('crystal',930,285,'接光水晶'),n('end',1070,470,'光桥彼岸',undefined,true)],edges:[e('start','mirrorA'),e('start','mirrorB'),e('mirrorA','pool'),e('mirrorA','mirrorB'),e('mirrorB','end',{beam:true})] },
  { id:'2-3',chapter:'pond',title:'雨滴节拍',kind:'聆听节奏 · 演奏回声',subtitle:'记住「滴 · 咚 · 叮 · 咚」。在水膜亮起时，依次敲响对应的叶片；错过可等下一拍。',rewards:['lilypad'],exit:'end',melody:['滴','咚','叮','咚'],
    nodes:[n('start',180,460,'起点'),n('drum',530,390,'雨滴琴','rhythm',true),n('echo',800,285,'回声池',undefined,true),n('end',1030,445,'雨幕出口')],edges:[e('start','drum'),e('drum','echo'),e('drum','end',{gate:'drum'})] },
  { id:'2-4',chapter:'pond',title:'池塘守护者',kind:'萤火虫护送 · 邻站呼唤',subtitle:'光虫只跟随相邻的花香。沿弯曲的金色轨迹，一站一站带它回到巢穴。',rewards:['bug'],exit:'end',companion:['nest','reed','lotus','bell','home'],
    nodes:[n('start',130,480,'起点'),n('nest',290,300,'迷路光虫'),n('reed',490,470,'芦苇铃','friend',true),n('lotus',580,285,'睡莲铃','friend',true),n('bell',810,465,'风铃花','friend',true),n('home',980,280,'光虫的家','friend',true),n('end',1110,480,'终点')],edges:[e('start','reed'),e('reed','lotus'),e('lotus','bell'),e('bell','home'),e('bell','end',{companion:'home'})] },
  { id:'3-1',chapter:'cave',title:'微光引路',kind:'迷雾探索 · 点亮视野',subtitle:'黑暗里的路要亲自发现。点亮苔灯，留意被照出的支路。',rewards:['moss','mushroom'],exit:'end',fog:true,
    nodes:[n('start',140,470,'洞口'),n('lampA',330,420,'洞口苔灯','light',true),n('quiet',430,285,'藏光石',undefined,true),n('lampB',610,455,'深处苔灯','light',true),n('secret',760,285,'洞中微光',undefined,true),n('lampC',880,455,'最后一盏灯','light'),n('end',1100,345,'星光出口')],edges:[e('start','lampA'),e('lampA','quiet'),e('lampA','lampB'),e('lampB','secret'),e('lampB','lampC'),e('lampC','end')] },
  { id:'3-2',chapter:'cave',title:'影子的形状',kind:'日月切换 · 两种道路',subtitle:'阳光照出上方的桥，月光照出下方的桥。带回日月碎片，再在月光下归来。',rewards:['arch'],exit:'end',required:['sun','moon'],
    nodes:[n('start',150,440,'起点'),n('dial',490,415,'日月石盘','switch',false,['sun','moon']),n('sun',750,280,'日光碎片',undefined,true),n('moon',750,495,'月光碎片',undefined,true),n('end',1060,390,'影桥出口',undefined,true)],edges:[e('start','dial'),e('dial','sun',{when:['dial','sun']}),e('dial','moon',{when:['dial','moon']}),e('dial','end',{when:['dial','moon'],needs:['sun','moon']})] },
  { id:'3-3',chapter:'cave',title:'共生之歌',kind:'引水灌溉 · 组合解谜',subtitle:'把水先送给藤蔓，过桥取得露珠；再引向睡莲，最后选好跳跃落点。',rewards:['mushroom'],exit:'end',required:['dew'],
    nodes:[n('start',130,460,'起点'),n('pump',330,350,'分水花','water',false,['vine','lily']),{...n('vine',530,475,'干渴藤蔓','grow'),water:true},n('dew',780,470,'露珠',undefined,true),{...n('lily',570,280,'干渴睡莲','lily',true,['rest','end']),water:true},n('rest',840,280,'回望石','lily',true,['lily']),n('end',1080,395,'共生花苞')],edges:[e('start','pump'),e('pump','vine'),e('pump','lily'),e('vine','dew',{gate:'vine'}),e('lily','rest',{jump:true}),e('lily','end',{jump:true}),e('rest','lily',{jump:true})] },
  { id:'3-4',chapter:'cave',title:'沉睡的守护者',kind:'星图记忆 · 终章仪式',subtitle:'先找齐八粒孢子。重看星图，记住图案亮起的次序，再点亮四处星座。',rewards:['starflower'],exit:'end',allSpores:true,sequence:['leaf','rain','star','moon'],
    nodes:[n('start',620,440,'星图中心'),n('a',440,480,'西侧小路',undefined,true),n('moon',250,470,'☾ 月','sequence',true),n('b',440,330,'西侧高台',undefined,true),n('leaf',260,280,'❧ 叶','sequence',true),n('c',800,330,'东侧高台',undefined,true),n('star',990,280,'✦ 星','sequence',true),n('d',800,480,'东侧小路',undefined,true),n('rain',990,470,'♢ 雨','sequence',true),n('end',620,270,'水晶花')],edges:[e('start','a'),e('a','moon'),e('start','b'),e('b','leaf'),e('start','c'),e('c','star'),e('start','d'),e('d','rain'),e('start','end',{gate:'ritual'})] },
];
export const getLevel = (id: string) => LEVELS.find(level => level.id === id) ?? LEVELS[0];
export const totalSpores = (level: Level) => level.nodes.filter(n => n.spore).length;
export const mechanismName: Record<Mechanism,string> = {grow:'花床',vine:'藤桥',lily:'跳跃睡莲',reflect:'反光叶',rhythm:'雨滴琴',light:'苔灯',friend:'花香铃',sequence:'星座',switch:'日月石盘',water:'分水花'};
