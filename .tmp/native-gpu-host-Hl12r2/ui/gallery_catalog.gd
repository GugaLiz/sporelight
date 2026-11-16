extends RefCounted
class_name GardenGalleryCatalog

# Text and image identities retained from src/app/scenes/galleryData.ts.
const CATEGORIES := ["全部", "植物", "生物", "建筑", "奇物"]
const ITEMS := [
	{"id": "flowerbud", "title": "萌芽花台", "category": "植物", "image": "production/bloom.png", "habitat": "苔藓湿地、遗迹花园", "levels": ["1-1", "1-2"], "desc": "在古老的土地上，沉睡的种子悄然萌发。柔嫩的花瓣承接着第一缕微光，治愈着每一寸疲惫的心灵。", "story": ["雨停之后，旧石阶上只剩一小块干涸的土地。{name}在这里停下，把一粒孢子轻轻放进裂缝。", "花朵没有立刻回答。直到第一缕阳光穿过遗迹，它才展开花瓣，替小小的旅人接住了前方的路。"], "poem": "一朵花开的地方，也可以是一段归途。"},
	{"id": "moss", "title": "发光苔藓", "category": "植物", "image": "production/light.png", "habitat": "潮湿岩壁、洞穴石阶", "levels": ["2-2", "3-1"], "desc": "把白天的温暖藏进柔软的叶片，在夜里替旅人点亮脚边。越是安静的地方，越能看见它的光。", "story": ["大家都抬头寻找星星时，苔藓却低着头，把微光留给脚下。它知道，有些路只能一步一步地照亮。", "{name}点亮第一片苔藓后，黑暗里浮现出一条从未被看见的小径。原来希望也可以长得这样低、这样近。"], "poem": "小小的光，也能照见下一步。"},
	{"id": "vine", "title": "藤蔓桥", "category": "奇物", "image": "gallery-journal/vine.png", "habitat": "苔藓峡谷、断裂的石台", "levels": ["1-3"], "desc": "从一粒孢子舒展开的绿色桥梁，让彼此遥望的石台重新相连。它记得每一次温柔的回头。", "story": ["两座石台已经遥望彼此很久。风能越过它们之间的空隙，种子却总是落不到对岸。", "后来，{name}带来了一粒愿意伸展的孢子。藤蔓用一整个清晨慢慢生长，终于把等待变成了一座桥。"], "poem": "有些连接，来自一次小小的伸手。"},
	{"id": "bug", "title": "发光小虫", "category": "生物", "image": "production/bug.png", "habitat": "花香小径、池塘芦苇边", "levels": ["1-4", "2-4"], "desc": "藏在花园与芦苇间的点点微光。花藤桥接通后，它们会重新照亮安静的归途。", "story": ["门闩打开时，花园里沉睡的小虫也醒来了。它们沿着藤蔓一盏一盏亮起，照见还留在踏板旁的小小蘑菇。", "{name}没有独自走向终点，而是回过头，接上认真等候的小苔灵。重新相连的路上，点点微光替它们留着回家的方向。"], "poem": "陪伴，就是愿意等一等。"},
	{"id": "lilypad", "title": "睡莲", "category": "植物", "image": "production/lily-open.png", "habitat": "雨滴池塘、静水浅滩", "levels": ["2-1", "2-3"], "desc": "安静漂浮在水面，等一滴雨唤醒花心。舒展的叶片会轻轻托起旅人，把勇气送往彼岸。", "story": ["睡莲总说自己并不擅长远行。它只是在原地听雨，看水纹一次次走向远方。", "直到{name}站上它的叶片，睡莲才发现：留在原地的生命，也可以把别人的旅程轻轻托起。"], "poem": "轻轻一跃，便是新的风景。"},
	{"id": "mushroom", "title": "光菇", "category": "植物", "image": "gallery-journal/mushroom.png", "habitat": "星光洞穴、湿润的树根下", "levels": ["3-1", "3-3"], "desc": "洞穴里不需要火的小灯。菌盖下藏着一圈暖金色的光，让安静的夜晚也有家的温度。", "story": ["洞穴深处，光菇从不问旅人为什么来到这里。它只是亮着，像一扇愿意一直等人归来的窗。", "{name}在菌盖旁歇了一会儿。远处的水声变得很轻，连那些还没说出口的担心，也慢慢安静下来。"], "poem": "总有一盏灯，愿意为你留着。"},
	{"id": "arch", "title": "遗迹拱门", "category": "建筑", "image": "production/arch.png", "habitat": "古苔原遗迹、山谷石阶", "levels": ["1-4", "3-2"], "desc": "旧石头记得很久以前的回声。苔藓和小花沿着裂缝生长，让经过这里的脚步都有了温柔的回响。", "story": ["没有人记得这座拱门通向过哪里。它只留下半圈天空，和被风吹得很慢的旧名字。", "当{name}穿过门下，新生的藤蔓轻轻摇了一下。也许石头并不需要恢复从前，它只想继续迎接新的相遇。"], "poem": "时间留下的空隙，后来长满了花。"},
	{"id": "starflower", "title": "星花", "category": "植物", "image": "reference-scenes/plant-cave-bloom.png", "habitat": "星光洞穴最深处", "levels": ["3-4"], "desc": "只在被温柔照亮的夜里开放。花瓣记得叶、雨、星与月的次序，也记得每一粒被找回的微光。", "story": ["人们说，星花睡着的时候，会梦见整片苔原。山谷里的花香、池塘的雨声，都安静地停在它的花瓣上。", "{name}找回八粒孢子，循着星图点亮最后一束光。花开时，曾经被帮助过的生命都在微光里回应：你走过的地方，已经有了家的模样。"], "poem": "你也是这片星光的一部分。"}
]


static func unlocked(item: Dictionary, store: Dictionary) -> bool:
	if store.get("gallery", {}).get(item.id, false):
		return true
	var records: Dictionary = store.get("mainline", store).get("records", {})
	for level_id in item.levels:
		if records.get(level_id, {}).get("completed", false):
			return true
	return false
