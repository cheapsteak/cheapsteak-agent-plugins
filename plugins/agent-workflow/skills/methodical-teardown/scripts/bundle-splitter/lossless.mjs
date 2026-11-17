// Check that every string in the input bundle survives into the readable tree.
// usage: node lossless.mjs <outDir> <input.js>...
// A string counts as kept if it is an output literal, sits inside a longer output string (rewrites merge
// concatenations), or appears in the output text (e.g. numeric or JSX forms). Exits 1 if any string is gone.
import fs from 'node:fs';
import path from 'node:path';
import { parse } from '@babel/parser';
import _traverse from '@babel/traverse';
const traverse = _traverse.default || _traverse;

const [, , OUT, ...INPUTS] = process.argv;
const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.js') ? [path.join(d, e.name)] : []));
function strings(files) {
  const s = new Set();
  let fns = 0;
  for (const f of files) {
    const ast = parse(fs.readFileSync(f, 'utf8'), { sourceType: 'module', plugins: ['jsx'], allowReturnOutsideFunction: true, allowUndeclaredExports: true });
    traverse(ast, {
      StringLiteral(p) { s.add(p.node.value); },
      TemplateElement(p) { if (p.node.value.cooked) s.add(p.node.value.cooked); },
      JSXText(p) { const v = p.node.value.trim(); if (v) s.add(v); },
      JSXAttribute(p) { if (typeof p.node.name.name === 'string') s.add(p.node.name.name); },
      Function() { fns++; },
    });
  }
  return { s, fns };
}
const outFiles = walk(OUT);
const raw = strings(INPUTS), out = strings(outFiles);
const blob = [...out.s].join('\u0000');
const text = outFiles.map((f) => fs.readFileSync(f, 'utf8')).join('\n');
const gone = [...raw.s].filter((k) => !out.s.has(k) && !blob.includes(k) && !text.includes(k));
console.log(`lossless: ${raw.s.size} input strings, ${gone.length} missing; functions in ${raw.fns} -> out ${out.fns}`);
if (gone.length) { console.log(JSON.stringify(gone.slice(0, 20))); process.exitCode = 1; }
