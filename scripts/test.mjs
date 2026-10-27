import { build } from 'esbuild';
const output = await build({ stdin: { contents: "import './tests/game.test.ts'; import './tests/characterMotion.test.ts'; import './tests/gridWorld.test.ts';", resolveDir: process.cwd() }, bundle: true, platform: 'node', format: 'esm', write: false });
await import(`data:text/javascript;base64,${Buffer.from(output.outputFiles[0].text).toString('base64')}`);
