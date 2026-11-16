import {readdir, readFile, stat} from 'node:fs/promises';
import {dirname, extname, join, posix, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const CORE_TESTS = [
  'rule_reference.gd', 'rule_normalize.gd', 'rule_query_scope.gd',
  'service_save_test.gd', 'service_snapshot_normalizer_test.gd',
  'service_hud_test.gd', 'service_button_test.gd',
  'service_modal_lifecycle_test.gd', 'service_home_navigation_test.gd',
  'session_test.gd', 'rule_input.gd', 'rule_integration.gd', 'rule_application.gd',
];

// Required by docs/50 and the existing collision/placement acceptance reports.
// Discovery may add suites; it must never silently remove these contracts.
export const REQUIRED_SCENE_TESTS = [
  'native_world_render_test.gd', 'native_actor_depth_test.gd',
  'native_first_garden_material_test.gd', 'native_first_garden_structure_test.gd',
  'native_generic_stairs_test.gd', 'native_generic_stair_movement_test.gd',
  'native_stair_lifecycle_test.gd', 'native_prop_collision_test.gd',
  'native_general_prop_collision_test.gd', 'native_scenery_placement_test.gd',
  'native_prop_alignment_test.gd', 'native_route_test.gd',
];

const TEXT_RESOURCES = new Set(['.gd', '.tscn', '.tres', '.godot', '.gdshader', '.gdshaderinc']);

function withoutComments(source, hashComments) {
  let result = '', quote = '', block = false;
  for (let i = 0; i < source.length; i++) {
    const char = source[i], next = source[i + 1];
    if (block) {
      if (char === '*' && next === '/') { result += '  '; i++; block = false; }
      else result += char === '\n' ? '\n' : ' ';
    } else if (quote) {
      result += char;
      if (char === '\\' && next !== undefined) { result += next; i++; }
      else if (char === quote) quote = '';
    } else if (char === '"' || char === "'") {
      quote = char; result += char;
    } else if ((hashComments && char === '#') || (char === '/' && next === '/')) {
      while (i < source.length && source[i] !== '\n') { result += ' '; i++; }
      if (i < source.length) result += '\n';
    } else if (char === '/' && next === '*') {
      result += '  '; i++; block = true;
    } else result += char;
  }
  return result;
}

function resourceReferences(path, source) {
  const extension = extname(path);
  const clean = withoutComments(source, extension === '.gd' || extension === '.godot');
  const expressions = extension === '.gd' ? [
    /\b(?:preload|load)\s*\(\s*["'](res:\/\/[^"'\r\n]+)["']\s*(?:,|\))/g,
    /\bextends\s+["'](res:\/\/[^"'\r\n]+)["']/g,
    /\bFileAccess\.get_file_as_string\s*\(\s*["'](res:\/\/[^"'\r\n]+)["']\s*\)/g,
  ] : extension === '.tscn' || extension === '.tres' ? [
    /^\[ext_resource\b[^\r\n]*\bpath="(res:\/\/[^"\r\n]+)"/gm,
  ] : extension === '.godot' ? [
    /^[^;\r\n=]+\s*=\s*"(res:\/\/[^"\r\n]+)"\s*$/gm,
  ] : [/#include\s+"(res:\/\/[^"\r\n]+)"/g];
  return expressions.flatMap(expression => [...clean.matchAll(expression)].map(match => ({
    source: path,
    line: clean.slice(0, match.index).split('\n').length,
    resource: match[1],
  })));
}

// Inventory paths are relative to godot/. Values are text for text resources;
// other files only need an entry. This also permits isolated in-memory checks.
export function inspectSceneInventory(inventory, filters = []) {
  const errors = [];
  const required = [
    'project.godot', 'main.tscn',
    ...[...CORE_TESTS, ...REQUIRED_SCENE_TESTS].map(file => 'tests/' + file),
    'content/levels.json', 'content/cloud-levels.json', 'content/visual-assets.json',
    'tests/fixtures/reference.json', 'tests/fixtures/cloud-reference.json', 'tests/fixtures/save-cases.json',
  ];
  for (const path of required) {
    if (!inventory.has(path)) errors.push({kind: 'missing-required-file', path});
  }
  let references = 0;
  for (const [path, source] of [...inventory].sort(([a], [b]) => a.localeCompare(b, 'en'))) {
    if (!TEXT_RESOURCES.has(extname(path))) continue;
    for (const reference of resourceReferences(path, source)) {
      references++;
      const target = posix.normalize(reference.resource.slice('res://'.length));
      if (target.startsWith('../../') || target === '..' || posix.isAbsolute(target)) {
        errors.push({kind: 'invalid-resource-path', ...reference});
      } else if (!inventory.has(target)) errors.push({kind: 'missing-resource', ...reference, target});
    }
  }
  const suites = [...inventory.keys()]
    .filter(path => /^tests\/native_.*test\.gd$/.test(path) || CORE_TESTS.some(file => path === 'tests/' + file))
    .map(path => posix.basename(path, '.gd')).sort();
  for (const filter of filters) {
    if (!suites.some(label => label.includes(filter))) errors.push({kind: 'unmatched-test-filter', filter});
  }
  return {passed: errors.length === 0, resources: inventory.size, references, suites, errors};
}

export async function inspectSceneIntegrity(root, filters = []) {
  const inventory = new Map();
  async function visit(directory, relative = '') {
    for (const entry of await readdir(directory, {withFileTypes: true})) {
      const path = relative ? relative + '/' + entry.name : entry.name;
      if (entry.isDirectory()) {
        if (!['.godot', 'build', '.git'].includes(entry.name)) await visit(join(directory, entry.name), path);
      } else if (entry.isFile()) {
        inventory.set(path, TEXT_RESOURCES.has(extname(path)) ? await readFile(join(directory, entry.name), 'utf8') : '');
      }
    }
  }
  await visit(join(root, 'godot'));
  // Legacy visual tests read fixtures from the project's docs/ directory.
  // Validate those explicit inputs without recursively scanning outside godot/.
  const externalInputs = new Set();
  for (const [path, source] of inventory) {
    if (!TEXT_RESOURCES.has(extname(path))) continue;
    for (const reference of resourceReferences(path, source)) {
      const target = posix.normalize(reference.resource.slice('res://'.length));
      if (target.startsWith('../') && !target.startsWith('../../')) externalInputs.add(target);
    }
  }
  for (const target of externalInputs) {
    try {
      if ((await stat(resolve(root, 'godot', target))).isFile()) inventory.set(target, '');
    } catch (error) {
      if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error;
    }
  }
  return inspectSceneInventory(inventory, filters);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
  const filters = (process.argv.find(value => value.startsWith('--only='))?.slice(7) ?? '').split(',').filter(Boolean);
  try {
    const result = await inspectSceneIntegrity(root, filters);
    console.log(JSON.stringify({suite: 'scene-integrity', ...result}, null, 2));
    if (!result.passed) process.exitCode = 1;
  } catch (error) {
    console.error(JSON.stringify({suite: 'scene-integrity', passed: false, failure: String(error)}));
    process.exitCode = 1;
  }
}
