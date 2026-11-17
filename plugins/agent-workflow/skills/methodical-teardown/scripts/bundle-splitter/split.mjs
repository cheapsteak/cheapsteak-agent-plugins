// Split a minified Bun / rolldown bundle into readable files.
// usage: node split.mjs <input.js> <outRoot> <tag> <stateDir> [--single-dir]
import fs from 'node:fs';
import path from 'node:path';
import { parse } from '@babel/parser';
import _traverse from '@babel/traverse';
import _generate from '@babel/generator';
import * as t from '@babel/types';
import { SIGS } from './sigs.mjs';
const traverse = _traverse.default || _traverse;
const generate = _generate.default || _generate;

const [, , INPUT, OUTROOT, TAG, STATE, FORCE] = process.argv;
const APP_MAX = 1200, VENDOR_MAX = 4000;
const src = fs.readFileSync(INPUT, 'utf8');
const t0 = Date.now();
const log = (...a) => console.error(`[${TAG} ${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a);

const ast = parse(src, { sourceType: 'module', allowReturnOutsideFunction: true, errorRecovery: false });
log('parsed');

// ---------- locate top-level statement list (unwrap Bun IIFE) ----------
let bodyOwner = ast.program; // node whose .body is the statement list
{
  const b = ast.program.body;
  if (b.length <= 2 && t.isExpressionStatement(b[0]) && t.isCallExpression(b[0].expression)) {
    const c = b[0].expression.callee;
    if ((t.isArrowFunctionExpression(c) || t.isFunctionExpression(c)) && t.isBlockStatement(c.body)) bodyOwner = c.body;
  }
}
const isIIFE = bodyOwner !== ast.program;

// split multi-declarator top-level var statements
function splitDecls(list) {
  const out = [];
  for (const s of list) {
    if (t.isVariableDeclaration(s) && s.declarations.length > 1) {
      for (const d of s.declarations) out.push(t.variableDeclaration(s.kind, [d]));
    } else if (t.isExportNamedDeclaration(s) && s.declaration && t.isVariableDeclaration(s.declaration) && s.declaration.declarations.length > 1) {
      for (const d of s.declaration.declarations) out.push(t.exportNamedDeclaration(t.variableDeclaration(s.declaration.kind, [d]), []));
    } else out.push(s);
  }
  return out;
}
bodyOwner.body = splitDecls(bodyOwner.body);

const isMinName = (n) => /^[$\w]{1,4}$/.test(n) && !/^(React|init|undefined)$/.test(n);


// ---------- gather facts per top-level statement ----------
function walk(node, fn, parentKey) {
  if (!node || typeof node.type !== 'string') return;
  fn(node, parentKey);
  for (const k in node) {
    if (k === 'loc' || k === 'start' || k === 'end' || k === 'extra' || k === 'leadingComments' || k === 'trailingComments' || k === 'innerComments') continue;
    const v = node[k];
    if (Array.isArray(v)) for (const x of v) walk(x, fn, k);
    else if (v && typeof v.type === 'string') walk(v, fn, k);
  }
}
const stmts = bodyOwner.body;
const facts = stmts.map((s) => {
  const strings = [], props = new Set(), kv = [];
  let jsx = 0;
  walk(s, (n) => {
    if (n.type === 'StringLiteral') strings.push(n.value);
    else if (n.type === 'TemplateElement' && n.value.cooked) strings.push(n.value.cooked);
    else if (n.type === 'MemberExpression' && !n.computed && n.property.type === 'Identifier') {
      props.add(n.property.name);
      if (/^jsxs?$/.test(n.property.name)) jsx++;
    } else if (n.type === 'ObjectProperty' && (t.isStringLiteral(n.value) || (t.isTemplateLiteral(n.value) && n.value.expressions.length === 0))) {
      const k = t.isIdentifier(n.key) ? n.key.name : t.isStringLiteral(n.key) ? n.key.value : null;
      const v = t.isStringLiteral(n.value) ? n.value.value : n.value.quasis[0].value.cooked;
      if (k && v != null) kv.push([k, v]);
    } else if (n.type === 'ObjectMethod' || (n.type === 'ObjectProperty' && t.isIdentifier(n.key))) {
      props.add(n.key.name);
    }
  });
  return { strings, props, kv, jsx };
});
log('facts', stmts.length, 'statements');

// ---------- runtime helper detection ----------
const helpers = {}; // localName -> role
const posOf = (n) => (n.start != null ? n : n.declarations?.[0] ?? n.declaration?.declarations?.[0] ?? n);
const srcOf = (n0) => { const n = posOf(n0); return n.start != null ? src.slice(n.start, n.end) : ''; };
for (const s of stmts.slice(0, 60)) {
  const decls = t.isVariableDeclaration(s) ? s.declarations : [];
  for (const d of decls) {
    if (!t.isIdentifier(d.id) || !d.init || d.init.start == null) continue;
    const code = srcOf(d.init);
    if (code.length > 600) continue;
    if (/exports:\{\}/.test(code)) helpers[d.id.name] = '__commonJS';
    else if (/Dynamic require of/.test(code)) helpers[d.id.name] = '__require';
    else if (/__esModule/.test(code)) helpers[d.id.name] = '__toESM';
    else if (/for\s*\(\s*var \w+ in/.test(code) && /enumerable/.test(code)) helpers[d.id.name] = '__export';
    else if (/=0\)/.test(code) && /=>\s*\(?\)?\s*=>|=>\(\)=>/.test(code) && code.length < 200) helpers[d.id.name] = '__esm';
  }
}
// rolldown runtime import
const importDecls = stmts.filter((s) => t.isImportDeclaration(s));
for (const imp of importDecls) {
  if (/rolldown-runtime/.test(imp.source.value)) {
    for (const sp of imp.specifiers) {
      const role = { n: '__export', r: '__toESM', t: '__commonJS' }[sp.imported?.name];
      if (role) helpers[sp.local.name] = role;
    }
  }
}
const roleName = (r) => Object.keys(helpers).find((k) => helpers[k] === r);
const CJS = roleName('__commonJS'), ESM = roleName('__esm');
log('helpers', JSON.stringify(helpers));

function stmtKind(s) {
  if (t.isImportDeclaration(s)) return 'import';
  if (t.isExportNamedDeclaration(s) && !s.declaration) return 'export';
  if (t.isExportAllDeclaration(s) || t.isExportDefaultDeclaration(s)) return 'export';
  if (t.isVariableDeclaration(s) && s.declarations.length === 1) {
    const init = s.declarations[0].init;
    if (t.isCallExpression(init) && t.isIdentifier(init.callee)) {
      if (init.callee.name === CJS) return 'cjs';
      if (init.callee.name === ESM) return 'esm';
    }
  }
  return 'stmt';
}
const kinds = stmts.map(stmtKind);

// ---------- classification ----------
function scoreStrings(strs, extra = '') {
  const sc = {};
  for (const s of strs) {
    if (s.length > 400) continue;
    for (const [fam, sub, re] of SIGS) {
      if (re.test(s)) { const k = fam + '|' + sub; sc[k] = (sc[k] || 0) + 1; }
    }
  }
  if (extra) for (const [fam, sub, re] of SIGS) if (re.test(extra)) { const k = fam + '|' + sub; sc[k] = (sc[k] || 0) + 1; }
  return sc;
}
const FAMMIN = Object.fromEntries(SIGS.filter((x) => x[3]).map((x) => [x[0], x[3]]));
function best(sc, min = 1) {
  const fam = {};
  for (const k in sc) { const f = k.split('|')[0]; fam[f] = (fam[f] || 0) + sc[k]; }
  let bf = null, bv = 0;
  for (const f in fam) if (fam[f] >= (FAMMIN[f] || 0) && fam[f] > bv) { bf = f; bv = fam[f]; }
  if (!bf || bv < min) return null;
  let bs = null, bsv = 0;
  for (const k in sc) if (k.startsWith(bf + '|') && sc[k] > bsv) { bs = k.split('|')[1]; bsv = sc[k]; }
  return { fam: bf, sub: bs, score: bv };
}

// Build units: Bun lazy ESM modules (pending stmts + init wrapper), CJS wrappers, loose statements.
const units = []; // {idx:[stmt indices], kind}
{
  let pending = [];
  for (let i = 0; i < stmts.length; i++) {
    const k = kinds[i];
    if (k === 'import' || k === 'export') { units.push({ idx: [i], kind: k }); continue; }
    if (k === 'cjs') { units.push({ idx: [i], kind: 'cjs' }); continue; }
    if (k === 'esm') { units.push({ idx: [...pending, i], kind: 'esm' }); pending = []; continue; }
    if (!ESM) { units.push({ idx: [i], kind: 'loose' }); continue; }
    pending.push(i);
  }
  for (const i of pending) units.push({ idx: [i], kind: 'loose' });
}
// sort units by first index for sequential layout
units.sort((a, b) => a.idx[0] - b.idx[0]);
const genLines = new Array(stmts.length);
for (const u of units) {
  const strs = u.idx.flatMap((i) => facts[i].strings);
  let extra = '';
  if (u.kind === 'cjs') {
    const code = srcOf(stmts[u.idx[0]]);
    if (/\.jsxs\s*=|jsxs:/.test(code) && code.length < 4000) extra = 'react.element';
  }
  u.score = scoreStrings(strs, extra);
  u.bytes = u.idx.reduce((a, i) => { const n = posOf(stmts[i]); return a + (n.end != null ? n.end - n.start : 200); }, 0);
  const min = u.kind === 'loose' ? 1 : 2;
  u.label = best(u.score, u.bytes > 20000 ? 2 : min) || (u.kind !== 'loose' ? best(u.score, 1) : null);
  // weak single hit in a large unit: require density
  if (u.label && u.label.score === 1 && u.bytes > 30000) u.label = null;
  if (u.kind === 'import' || u.kind === 'export') u.label = null;
}
// first-party markers (claude.ai frame host) veto any vendor label
const FIRST_PARTY = /__frame_|__fc_|\/api\/frame|frame\.claudeusercontent/;
if (!FORCE) for (const u of units) if (u.label && u.idx.some((i) => FIRST_PARTY.test(srcOf(stmts[i])))) u.label = null;
if (FORCE) for (const u of units) if (u.kind !== 'import' && u.kind !== 'export') u.label = { fam: FORCE, sub: (u.label && u.label.fam === FORCE ? u.label.sub : FORCE), score: 99 };
// smoothing: fill unlabeled runs between same-family labels
{
  const L = units.map((u) => (u.label ? u.label.fam : null));
  let last = -1;
  for (let i = 0; i < units.length; i++) {
    if (!L[i] || units[i].kind === 'import' || units[i].kind === 'export') continue;
    if (last >= 0 && i - last > 1) {
      const gap = units.slice(last + 1, i);
      const gapBytes = gap.reduce((a, u) => a + u.bytes, 0);
      const anyJsx = gap.some((u) => u.idx.some((j) => facts[j].jsx > 0));
      if (L[last] === L[i] && gapBytes < 40000 && !(anyJsx && L[i] !== 'react' && L[i] !== 'base-ui' && L[i] !== 'motion')) {
        for (const u of gap) if (!u.label && u.kind !== 'import' && u.kind !== 'export') u.label = { ...units[last].label, filled: true };
      } else if (L[last] !== L[i] && gapBytes < 1500 && !anyJsx) {
        for (const u of gap) if (!u.label && u.kind !== 'import' && u.kind !== 'export') u.label = { ...units[last].label, filled: true };
      }
    }
    last = i;
  }
}
if (!FORCE) for (const u of units) if (u.label && u.label.filled && u.idx.some((i) => FIRST_PARTY.test(srcOf(stmts[i])))) u.label = null;
log('classified', units.length, 'units');

// ---------- topic naming ----------
const STOP = new Set('div span button true false none auto click string number object function undefined default value label input change error data type name text title item items left right top bottom center start end open close hidden block flex true svg path button img link style class children props content id key ref src href role aria size small large medium base base-ui react'.split(' '));
function tokensOf(idxs) {
  const m = new Map();
  for (const i of idxs) {
    for (const [k, v] of facts[i].kv) {
      if (k === 'data-testid' || k === 'displayName') m.set(v, (m.get(v) || 0) + 6);
    }
    for (const s of facts[i].strings) {
      if (s.length < 4 || s.length > 40 || /\s/.test(s)) continue;
      if (!/^[a-zA-Z][\w:.-]*$/.test(s)) continue;
      if (STOP.has(s.toLowerCase())) continue;
      m.set(s, (m.get(s) || 0) + 1);
    }
  }
  return m;
}
const docFreq = new Map();
const unitTokens = units.map((u) => tokensOf(u.idx));
for (const tk of unitTokens) for (const k of tk.keys()) docFreq.set(k, (docFreq.get(k) || 0) + 1);
function topic(tokMap, n = 2) {
  const N = units.length;
  const arr = [...tokMap.entries()].map(([k, c]) => [k, c * Math.log(N / (docFreq.get(k) || 1))]);
  arr.sort((a, b) => b[1] - a[1]);
  return arr.slice(0, n).map((x) => x[0]);
}
const slug = (s) => s.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'misc';

// ---------- renames ----------
const topNames = new Set();
const allIdents = new Set();
walk(ast.program, (n) => { if (n.type === 'Identifier') allIdents.add(n.name); });
for (const s of stmts) {
  const d = (t.isExportNamedDeclaration(s) || t.isExportDefaultDeclaration(s)) && s.declaration ? s.declaration : s;
  if ((t.isFunctionDeclaration(d) || t.isClassDeclaration(d)) && d.id) topNames.add(d.id.name);
  else if (t.isVariableDeclaration(d)) for (const x of d.declarations) walk(x.id, (n, k) => { if (n.type === 'Identifier' && k !== 'key') topNames.add(n.name); });
  else if (t.isImportDeclaration(d)) for (const sp of d.specifiers) topNames.add(sp.local.name);
}
const renames = []; // [old, new, why]
const plan = new Map();
const used = new Set();
const RESERVED = new Set('default class import export new delete in do if for var let const this super with yield await enum case try catch finally switch while return typeof void instanceof function arguments eval undefined NaN Infinity'.split(' '));
const nm = (x) => plan.get(x) ?? x;
function doRename(oldName, wanted, why, allowSeen = false) {
  if (!topNames.has(oldName) || plan.has(oldName)) return null;
  let nn = wanted.replace(/[^\w$]/g, '_');
  if (/^\d/.test(nn)) nn = '_' + nn;
  let k = 1, cand = nn;
  while (used.has(cand) || (allIdents.has(cand) && !(allowSeen && !topNames.has(cand))) || RESERVED.has(cand)) cand = `${nn}_${++k}`;
  used.add(cand);
  plan.set(oldName, cand);
  renames.push([oldName, cand, why]);
  return cand;
}
for (const [k, role] of Object.entries(helpers)) doRename(k, role, 'runtime helper');

// load export maps of imported chunks
const exportMaps = {};
fs.mkdirSync(STATE, { recursive: true });
for (const imp of importDecls) {
  const base = path.basename(imp.source.value).replace(/\.js$/, '');
  const f = path.join(STATE, base + '.exports.json');
  if (fs.existsSync(f)) exportMaps[base] = JSON.parse(fs.readFileSync(f, 'utf8'));
}
const short = (b) => b.replace(/-[A-Za-z0-9_-]{8}$/, '').replace(/\.[0-9a-f]{8}$/, '');
for (const imp of importDecls) {
  const base = path.basename(imp.source.value).replace(/\.js$/, '');
  if (/rolldown-runtime/.test(base)) continue;
  const em = exportMaps[base] || {};
  for (const sp of imp.specifiers) {
    if (!t.isImportSpecifier(sp)) continue;
    const ex = t.isIdentifier(sp.imported) ? sp.imported.name : sp.imported.value;
    const known = em[ex];
    const want = known && !isMinName(known) ? known : !isMinName(ex) ? ex : `${short(base).replace(/[^\w]/g, '_')}$${ex}`;
    doRename(sp.local.name, want, `import ${ex} from ${short(base)}`, want === known || want === ex);
  }
}
// CJS / ESM wrapper naming
function reexportTarget(s) {
  const f = s.declarations[0].init.arguments[0];
  if (!f || !(t.isArrowFunctionExpression(f) || t.isFunctionExpression(f))) return null;
  const b = t.isBlockStatement(f.body) ? f.body.body : null;
  if (!b || b.length !== 1 || !t.isExpressionStatement(b[0])) return null;
  const e = b[0].expression;
  if (t.isAssignmentExpression(e) && t.isMemberExpression(e.left) && t.isIdentifier(e.left.property, { name: 'exports' }) && t.isCallExpression(e.right) && t.isIdentifier(e.right.callee) && e.right.arguments.length === 0) return e.right.callee.name;
  return null;
}
const cjsCount = {};
for (const u of units) {
  if (u.kind !== 'cjs' && u.kind !== 'esm') continue;
  const s = stmts[u.idx[u.idx.length - 1]];
  const id = s.declarations[0].id.name;
  let base;
  const reexp = u.kind === 'cjs' && reexportTarget(s);
  if (reexp) { u.reexp = reexp; continue; }
  if (u.label) {
    base = u.label.sub;
    if (u.kind === 'cjs' && u.label.fam === 'react') {
      const code = srcOf(s);
      if (/__reactFiber|__reactContainer/.test(code)) base = 'react-dom';
      else if (/unstable_scheduleCallback/.test(code) && code.length < 30000) base = 'scheduler';
      else if (/jsxs/.test(code) && code.length < 6000) base = 'react-jsx-runtime';
      else if (/useState|useEffect/.test(code)) base = 'react';
    }
  } else {
    base = topic(unitTokens[units.indexOf(u)], 1)[0] || 'mod';
  }
  base = base.replace(/[^\w]+/g, '_');
  doRename(id, (u.kind === 'cjs' ? 'require_' : 'init_') + base, u.label ? `${u.kind} wrapper (${u.label.fam})` : `${u.kind} wrapper (app)`);
}
for (const u of units) if (u.reexp) {
  const tn = nm(u.reexp);
  doRename(stmts[u.idx[0]].declarations[0].id.name, /^require_/.test(tn) ? tn + '_entry' : 'require_reexport_' + tn, 'cjs re-export entry');
}
// import_X = __toESM(require_X()) ; X_mod = require_X()
for (const s of stmts) {
  if (!t.isVariableDeclaration(s) || s.declarations.length !== 1) continue;
  const d = s.declarations[0];
  if (!t.isIdentifier(d.id) || !t.isCallExpression(d.init)) continue;
  let c = d.init;
  if (t.isIdentifier(c.callee) && nm(c.callee.name) === '__toESM' && t.isCallExpression(c.arguments[0]) && t.isIdentifier(c.arguments[0].callee) && /^require_/.test(nm(c.arguments[0].callee.name))) {
    doRename(d.id.name, nm(c.arguments[0].callee.name).replace(/^require_/, 'import_').replace(/_entry$/, ''), 'toESM import');
  } else if (t.isIdentifier(c.callee) && /^require_/.test(nm(c.callee.name)) && c.arguments.length === 0 && isMinName(d.id.name)) {
    doRename(d.id.name, nm(c.callee.name).replace(/^require_/, '').replace(/_entry$/, '') + '_mod', 'cjs module instance');
  }
}
// export-name renames
const exportStmts = stmts.filter((s) => t.isExportNamedDeclaration(s) && !s.declaration && !s.source);
for (const s of exportStmts) {
  for (const sp of s.specifiers) {
    const ex = t.isIdentifier(sp.exported) ? sp.exported.name : sp.exported.value;
    if (!isMinName(ex) && isMinName(sp.local.name) && ex !== 'default') doRename(sp.local.name, ex, 'export name', true);
  }
}
// displayName and "useX must be used within" renames
for (let i = 0; i < stmts.length; i++) {
  const s = stmts[i];
  if (t.isExpressionStatement(s) && t.isAssignmentExpression(s.expression) && t.isMemberExpression(s.expression.left) && t.isIdentifier(s.expression.left.object) && t.isIdentifier(s.expression.left.property, { name: 'displayName' }) && t.isStringLiteral(s.expression.right)) {
    const id = s.expression.left.object.name;
    if (isMinName(id)) doRename(id, s.expression.right.value, 'displayName');
  }
  let fnId = null, fnNode = null;
  if (t.isFunctionDeclaration(s) && s.id) { fnId = s.id.name; fnNode = s; }
  else if (t.isVariableDeclaration(s) && t.isIdentifier(s.declarations[0].id) && (t.isArrowFunctionExpression(s.declarations[0].init) || t.isFunctionExpression(s.declarations[0].init))) { fnId = s.declarations[0].id.name; fnNode = s.declarations[0].init; }
  if (fnId && isMinName(fnId)) {
    const strs = facts[i].strings;
    const m = strs.map((x) => /^(use[A-Z]\w*)\b.*(must|should|can only) be (used|called) (within|inside|in)/.exec(x)).find(Boolean);
    if (m && strs.length < 15) doRename(fnId, m[1], 'hook error message');
  }
}
log('renamed', renames.length);

// apply planned renames in one pass (top-level bindings only)
{
  const topBlock = isIIFE ? ast.program.body[0].expression.callee : ast.program;
  traverse(ast, {
    Identifier(p) {
      const nn = plan.get(p.node.name);
      if (!nn) return;
      if (!(p.isReferencedIdentifier() || p.isBindingIdentifier())) return;
      if (p.parentPath.isExportSpecifier() && p.key === 'exported') return;
      const b = p.scope.getBinding(p.node.name);
      if (b && b.scope.block === topBlock) p.node.name = nn;
    },
  });
}
log('applied renames');
// Readability rewrites (unminify, JSX) are done per output file by wakaru, in run.mjs.

// ---------- generate + chunk ----------
const gen = (n) => generate(n, { comments: false, jsescOption: { minimal: true }, retainLines: false }).code;
if (stmts.length !== kinds.length) throw new Error(`statement count changed after classification: ${kinds.length} -> ${stmts.length}`);
const codes = stmts.map((s) => gen(s));
for (let i = 0; i < stmts.length; i++) genLines[i] = codes[i].split('\n').length;
const GIANT = 2500;
const parts = new Map(); // stmt idx -> [{code, lines}]
for (let i = 0; i < stmts.length; i++) {
  if (genLines[i] < GIANT) continue;
  const s0 = stmts[i];
  const s = t.isExportNamedDeclaration(s0) && s0.declaration ? s0.declaration : s0;
  let fn = null, name = null;
  if (t.isFunctionDeclaration(s)) { fn = s; name = s.id?.name; }
  else if (t.isVariableDeclaration(s) && s.declarations.length === 1 && (t.isFunctionExpression(s.declarations[0].init) || t.isArrowFunctionExpression(s.declarations[0].init)) && t.isIdentifier(s.declarations[0].id)) { fn = s.declarations[0].init; name = s.declarations[0].id.name; }
  if (!fn || !t.isBlockStatement(fn.body)) continue;
  const body = [];
  for (const b of fn.body.body) {
    if (t.isVariableDeclaration(b) && b.declarations.length > 1) for (const d of b.declarations) body.push(t.variableDeclaration(b.kind, [d]));
    else body.push(b);
  }
  const bcodes = body.map((b) => gen(b));
  const groups = [];
  let g = [], gl = 0;
  for (const c of bcodes) {
    const l = c.split('\n').length;
    if (gl > 0 && gl + l > APP_MAX) { groups.push(g); g = []; gl = 0; }
    g.push(c); gl += l;
  }
  if (g.length) groups.push(g);
  if (groups.length < 2) continue;
  const params = fn.params.map((p) => gen(p)).join(', ');
  const pre = `${fn.async ? 'async ' : ''}function${fn.generator ? '*' : ''} `;
  parts.set(i, groups.map((gr, k) => {
    const code = `// [giant-function split] ${name}: body part ${k + 1} of ${groups.length}. Original is one function; later parts close over earlier parts' locals.\n${pre}${name}__part${k + 1}_of_${groups.length}(${params}) {\n${gr.join('\n')}\n}`;
    return { code, lines: code.split('\n').length, giant: name };
  }));
}
log('generated');

const files = []; // {dir, name, idxs, label}
let cur = null;
const tagShort = TAG === '.' ? '' : short(TAG);
const flush = () => { if (cur && cur.idxs.length) files.push(cur); cur = null; };
const keyOf = (u) => (u.kind === 'import' || u.kind === 'export' ? 'io' : u.label ? 'v:' + u.label.fam : 'app');
for (const u of units) {
  const k = keyOf(u);
  const max = k === 'app' ? APP_MAX : k === 'io' ? 1e9 : VENDOR_MAX;
  const ulines = u.idx.reduce((a, i) => a + genLines[i], 0);
  if (!cur || cur.key !== k || (k !== 'io' && cur.lines > 0 && (cur.lines + ulines > max * 1.15 || ((u.kind === 'cjs' || u.kind === 'esm') && cur.lines > max / 2)))) {
    flush();
    cur = { key: k, units: [], idxs: [], lines: 0, label: u.label };
  }
  cur.units.push(u);
  for (const i of u.idx) {
    if (parts.has(i)) {
      for (const pc of parts.get(i)) {
        flush();
        cur = { key: k, units: [u], idxs: [i], pieces: [pc.code], lines: pc.lines, label: u.label, giant: pc.giant };
        flush();
      }
      cur = { key: k, units: [u], idxs: [], lines: 0, label: u.label };
      continue;
    }
    if (k !== 'io' && cur.lines > 0 && cur.lines + genLines[i] > max) {
      flush();
      cur = { key: k, units: [u], idxs: [], lines: 0, label: u.label };
    }
    cur.idxs.push(i);
    cur.lines += genLines[i];
  }
}
flush();

const outFiles = [];
let seq = 0;
for (const f of files) {
  seq++;
  const tk = new Map();
  for (const u of f.units) for (const [k, v] of unitTokens[units.indexOf(u)]) tk.set(k, (tk.get(k) || 0) + v);
  let dir, name;
  const num = String(seq).padStart(4, '0');
  if (f.key === 'io') { dir = path.join('app', tagShort); name = `${num}_imports-exports.js`; }
  else if (f.key === 'app') { dir = path.join('app', tagShort); name = f.giant ? `${num}_${slug(f.giant)}__${slug(f.pieces[0].match(/part(\d+_of_\d+)/)[1])}.js` : `${num}_${topic(tk, 2).map(slug).join('__') || 'misc'}.js`; }
  else {
    const subs = {};
    for (const u of f.units) if (u.label) subs[u.label.sub] = (subs[u.label.sub] || 0) + u.bytes;
    const sub = Object.entries(subs).sort((a, b) => b[1] - a[1])[0]?.[0] || f.label.sub;
    dir = path.join('vendor', f.label.fam);
    name = `${tagShort ? tagShort + '_' : ''}${num}_${slug(sub)}.js`;
  }
  const code = (f.pieces ? f.pieces.join('\n\n') : f.idxs.slice().sort((a, b) => a - b).map((i) => codes[i]).join('\n\n')) + '\n';
  const header = `// Extracted from ${path.basename(INPUT)} (statements ${f.idxs[0]}..${f.idxs[f.idxs.length - 1]})\n`;
  fs.mkdirSync(path.join(OUTROOT, dir), { recursive: true });
  fs.writeFileSync(path.join(OUTROOT, dir, name), header + code);
  // top-level names
  const names = [];
  for (const i of f.idxs) {
    const s = stmts[i];
    const d = t.isExportNamedDeclaration(s) && s.declaration ? s.declaration : s;
    if (t.isFunctionDeclaration(d) || t.isClassDeclaration(d)) d.id && names.push(d.id.name);
    else if (t.isVariableDeclaration(d)) for (const x of d.declarations) if (t.isIdentifier(x.id)) names.push(x.id.name);
  }
  outFiles.push({
    file: path.join(dir, name), kind: f.key, lib: f.label?.fam || null, lines: code.split('\n').length,
    names, strings: [...new Set(f.idxs.flatMap((i) => facts[i].strings))].filter((s) => s.length <= 200),
    props: [...new Set(f.idxs.flatMap((i) => [...facts[i].props]))],
    testids: [...new Set(f.idxs.flatMap((i) => facts[i].kv.filter(([k]) => k === 'data-testid').map(([, v]) => v)))],
    jsx: f.idxs.reduce((a, i) => a + facts[i].jsx, 0),
  });
}
// export map for downstream chunks
const myExports = {};
for (const s of exportStmts) for (const sp of s.specifiers) myExports[t.isIdentifier(sp.exported) ? sp.exported.name : sp.exported.value] = sp.local.name;
fs.writeFileSync(path.join(STATE, path.basename(INPUT).replace(/\.js$/, '') + '.exports.json'), JSON.stringify(myExports));
fs.writeFileSync(path.join(STATE, path.basename(INPUT).replace(/\.js$/, '') + '.manifest.json'), JSON.stringify({ input: INPUT, tag: TAG, helpers, renames, files: outFiles }));
log('wrote', outFiles.length, 'files;', outFiles.filter((f) => f.kind === 'app').length, 'app');
