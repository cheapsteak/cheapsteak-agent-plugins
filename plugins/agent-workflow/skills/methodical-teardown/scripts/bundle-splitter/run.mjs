// Split every chunk of one bundle into readable files, unminify each with wakaru, then prettier, verify and index.
// usage: node run.mjs <bundleDir> <outDir> [stateDir] [productName]
// Reads the bundle as text and parses it; never executes it.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { parse } from '@babel/parser';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const [, , IN, OUT, STATE_ARG, PRODUCT_ARG] = process.argv;
if (!IN || !OUT) { console.error('usage: node run.mjs <bundleDir> <outDir> [stateDir] [productName]'); process.exit(2); }
const STATE = path.resolve(STATE_ARG || path.join(OUT, '..', 'split-state'));
const WORK = path.join(STATE, 'work');
fs.rmSync(OUT, { recursive: true, force: true });
fs.rmSync(STATE, { recursive: true, force: true });
fs.mkdirSync(WORK, { recursive: true });

// Docs ships part of its code as a string inside virtual-lfile-extras-text-*.js; pull it out as its own input.
let embedded = null;
for (const f of fs.readdirSync(IN)) {
  if (!/^virtual-lfile-extras-text-.*\.js$/.test(f)) continue;
  const ast = parse(fs.readFileSync(path.join(IN, f), 'utf8'), { sourceType: 'module' });
  const d = ast.program.body[0].declarations[0].init;
  const code = d.type === 'TemplateLiteral' ? d.quasis.map((q) => q.value.cooked).join('') : d.value;
  embedded = path.join(WORK, 'lfile-extras.embedded.js');
  fs.writeFileSync(embedded, code);
}
const chunks = fs.readdirSync(IN).filter((f) => f.endsWith('.js') && !/^virtual-lfile-(extras|runtime)-text/.test(f));
const deps = {};
for (const f of chunks) {
  const src = fs.readFileSync(path.join(IN, f), 'utf8');
  deps[f] = [...src.matchAll(/(?:import|export)\s*\{[^}]*\}\s*from\s*["'`]\.\/([^"'`]+)["'`]|import\s*["'`]\.\/([^"'`]+)["'`]/g)].map((m) => m[1] || m[2]).filter((x) => chunks.includes(x));
}
// dependencies first, so each chunk can name its imports after the exporter's renamed locals
const order = [], seen = new Set();
const visit = (f, stack = new Set()) => {
  if (seen.has(f) || stack.has(f)) return;
  stack.add(f);
  for (const d of deps[f]) visit(d, stack);
  seen.add(f); order.push(f);
};
chunks.forEach((f) => visit(f));
const jobs = order.map((f) => [path.join(IN, f), f.replace(/\.js$/, '')]);
if (embedded) jobs.push([embedded, 'lfile_extras_embedded']);
// chunks whose file name already says which library they are: force that vendor label
const FORCE = [[/^react-/, 'react'], [/^shiki-/, 'shiki'], [/^renderableKatex/, 'katex'], [/^(hast|devlop|chat-markdown)-/, 'markdown'], [/^file-selector/, 'file-selector'], [/^(animations|blank|model|claudeWritingSheets)-/, 'data-assets'], [/^(rolldown-runtime|preload)-/, 'bundler-runtime'], [/^cds-/, 'cds']];
for (const [file, tag] of jobs) {
  const force = FORCE.find(([re]) => re.test(tag))?.[1];
  execFileSync('node', ['--max-old-space-size=8192', path.join(HERE, 'split.mjs'), file, OUT, tag, STATE, ...(force ? [force] : [])], { stdio: ['ignore', 'inherit', 'inherit'] });
  process.stderr.write(`${tag} done\n`);
}
// Readability pass: wakaru rewrites each output file in place (unminify, JSX recovery). A file it can't handle is kept as split.
const WAKARU = path.join(HERE, 'node_modules/@wakaru/cli/bin/wakaru');
const walkJs = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walkJs(path.join(d, e.name)) : e.name.endsWith('.js') ? [path.join(d, e.name)] : []));
const kept = [];
for (const f of walkJs(OUT)) {
  const tmp = path.join(WORK, 'wakaru-out.js');
  try {
    execFileSync('node', [WAKARU, f, '-o', tmp, '--force'], { stdio: ['ignore', 'ignore', 'pipe'] });
    fs.renameSync(tmp, f);
  } catch (e) { kept.push(`${path.relative(OUT, f)}: ${String(e.stderr || e.message).split('\n')[0]}`); }
}
process.stderr.write(`wakaru: ${kept.length} file(s) kept unrewritten${kept.length ? '\n  ' + kept.join('\n  ') : ''}\n`);
execFileSync(path.join(HERE, 'node_modules/.bin/prettier'), ['--write', '--log-level', 'warn', '--print-width', '100', `${OUT}/**/*.js`], { stdio: 'inherit' });
execFileSync('node', [path.join(HERE, 'verify.mjs'), OUT], { stdio: 'inherit' });
execFileSync('node', [path.join(HERE, 'lossless.mjs'), OUT, ...jobs.map(([file]) => file)], { stdio: 'inherit' });
execFileSync('node', [path.join(HERE, 'index.mjs'), OUT, STATE, PRODUCT_ARG || path.basename(path.dirname(path.resolve(OUT)))], { stdio: 'inherit' });
