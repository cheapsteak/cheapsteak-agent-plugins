// Re-parse every generated file (JSX allowed); reports files that no longer parse.
import fs from 'node:fs'; import path from 'node:path'; import { parse } from '@babel/parser';
const roots = process.argv.slice(2); let ok = 0, bad = [];
const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.js') ? [path.join(d, e.name)] : []);
for (const r of roots) for (const f of walk(r)) {
  try { parse(fs.readFileSync(f, 'utf8'), { sourceType: 'module', plugins: ['jsx'], allowReturnOutsideFunction: true, allowAwaitOutsideFunction: true, allowUndeclaredExports: true }); ok++; }
  catch (e) { bad.push(f + ': ' + e.message); }
}
console.log('ok', ok, 'bad', bad.length); console.log(bad.slice(0, 20).join('\n'));
if (bad.length) process.exitCode = 1;
