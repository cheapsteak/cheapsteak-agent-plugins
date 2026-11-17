// Build MODULES.md, STRINGS_INDEX.tsv, IDENTIFIERS.md for a readable/<product> tree.
// usage: node index.mjs <productRoot> <stateDir> <productName>
import fs from 'node:fs';
import path from 'node:path';
import { parse } from '@babel/parser';

const [, , ROOT, STATE, PRODUCT] = process.argv;
const walkDir = (d) => (fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walkDir(path.join(d, e.name)) : e.name.endsWith('.js') ? [path.join(d, e.name)] : [])) : []);
const appFiles = walkDir(path.join(ROOT, 'app')).sort();
const vendorFiles = walkDir(path.join(ROOT, 'vendor')).sort();

function walk(node, fn, parent, key) {
  if (!node || typeof node.type !== 'string') return;
  fn(node, parent, key);
  for (const k in node) {
    if (k === 'loc' || k === 'start' || k === 'end' || k === 'extra' || k.endsWith('Comments')) continue;
    const v = node[k];
    if (Array.isArray(v)) for (const x of v) walk(x, fn, node, k);
    else if (v && typeof v.type === 'string') walk(v, fn, node, k);
  }
}
const CATS = [
  ['selection', /^(setSelection|selection|\$from|\$to|\$anchor|\$head|anchor|head|TextSelection|NodeSelection|AllSelection|getSelection|addRange|removeAllRanges|domAtPos|posAtCoords|coordsAtPos|posAtDOM|nodeDOM|selectionchange|caret|selectNode|collapse)$/, /^(selectionchange|caret|selection)/i],
  ['transactions', /^(tr|docChanged|steps|setMeta|getMeta|mapping|replaceWith|replaceRangeWith|insertText|addMark|removeMark|setNodeMarkup|dispatch|dispatchTransaction|maybeStep|step|scrollIntoView|setStoredMarks|deleteSelection|filterTransaction|appendTransaction)$/, /^(addToHistory|appendedTransaction|transaction)$/i],
  ['collab', /^(awareness|getStates|setLocalStateField|clientID|encodeStateAsUpdate|applyUpdate|transact|observeDeep|doc|rebase|confirmed|unconfirmed|version|sendable|receiveTransaction)$/, /awareness|ySync|y-sync|yjs|presence|collab|rebase|peer|room|remote|conflict|merge|theirs|mine|superseded/i],
  ['editing-commands', /^(chainCommands|toggleMark|wrapIn|setBlockType|lift|joinBackward|splitBlock|insertContent|commands|keymap|inputRules|handleKeyDown|handleTextInput|handlePaste|handleDrop|handleDOMEvents)$/, /^(Mod-|Shift-|Enter$|Backspace$|Delete$|Tab$)/],
  ['dom-input', /^(clipboardData|dataTransfer|inputType|isComposing|getData|setData)$/, /^(keydown|keyup|beforeinput|input|compositionstart|compositionend|paste|copy|cut|drop|dragstart|dragover|dragend|focusin|focusout)$/],
  ['pointer/drag', /^(setPointerCapture|clientX|clientY|pointerId|movementX)$/, /^(pointerdown|pointermove|pointerup|pointercancel|mousedown|mousemove|mouseup|touchstart|touchmove|wheel|lostpointercapture)$/],
  ['render/layout', /^(getBoundingClientRect|getContext|requestAnimationFrame|ResizeObserver|IntersectionObserver|offsetHeight|offsetWidth|scrollTop|getClientRects|drawImage|fillRect|measureText)$/, /^(canvas|2d|resize|scroll|layout|measure)/],
  ['schema/doc-model', /^(parseDOM|toDOM|nodeSize|childCount|firstChild|descendants|nodesBetween|textContent|marks|attrs|isBlock|isInline|isTextblock|createAndFill|fromJSON|toJSON)$/, /^(paragraph|heading|listItem|bulletList|orderedList|blockquote|codeBlock|hardBreak|table|tableRow|tableCell|image|horizontalRule|doc|text)$/],
  ['comments', /^(comments|thread|threads|replies)$/, /comment|thread|reply|annotation|mention/i],
  ['undo/history', /^(undo|redo|undoDepth|redoDepth)$/, /^(undo|redo|history|addToHistory)/i],
  ['export/import', /^(writeFile|generateAsync|addSlide|addText|addImage)$/, /pptx|\.pdf|docx|export|import|download|markdown|html/i],
  ['host-bridge/network', /^(postMessage|fetch|WebSocket|EventSource|onmessage|subscribe|unsubscribe)$/, /capability|bridge|postMessage|room\.|host-|claude\.ai|artifact|appifact/i],
  ['telemetry/errors', /^(captureException|report|emit)$/, /health|telemetry|metric|sentry|_failed$|^failed|error$/i],
];
const TW = /^(text|bg|border|rounded|flex|grid|gap|p[xytrbl]?|m[xytrbl]?|w|h|min|max|items|justify|self|place|inset|top|left|right|bottom|z|opacity|shadow|ring|outline|font|leading|tracking|overflow|cursor|select|pointer|transition|duration|ease|animate|translate|scale|rotate|size|col|row|space|divide|fill|stroke|object|aspect|line|whitespace|break|truncate|sr|not|group|peer|hover|focus|dark|motion|backdrop|blur|underline|decoration|list|order|shrink|grow|basis|content|indent|align|table|caption|scroll|snap|touch|will|appearance|resize|accent|caret|from|via|to|tabular|focus-visible|data|aria|first|last|odd|even|disabled|starting|before|after|placeholder|file|marker|selection|in|is|has)\b/;
function classify(s) {
  if (s.length < 3 || s.length > 160 || /\n/.test(s)) return null;
  if (/^[a-z][a-z0-9]*(_[a-z0-9]+)+$/.test(s)) return 'code';
  if (/^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$/.test(s)) return 'const';
  if (/^[a-z][\w-]*(:[\w.-]+)+$/.test(s)) return 'event';
  if (/^[a-z][a-z0-9]*(\.[a-z][\w-]*)+$/i.test(s) && !/\.(js|css|png|svg)$/.test(s)) return 'dotted';
  if (/^data-[a-z0-9-]+$/.test(s)) return 'attr';
  if (/^\[data-[^\]]+\]$/.test(s)) return 'selector';
  if (/^--[a-z0-9-]+$/.test(s)) return 'cssvar';
  if (/^[a-z][a-z0-9]*(-[a-z0-9]+)+$/.test(s)) return TW.test(s) ? null : 'kebab';
  if (/^[a-z]+[A-Z][a-zA-Z0-9]+$/.test(s) && s.length >= 6) return 'camel';
  if (/\s/.test(s)) {
    const toks = s.split(/\s+/);
    if (toks.length >= 2 && toks.filter((x) => /[-:\[\]\/]/.test(x) || /^[a-z0-9-]+$/.test(x)).length / toks.length > 0.8 && !/[A-Z.,!?']/.test(s)) return 'classes';
    if (/[a-zA-Z]{3}/.test(s) && s.length >= 12) return 'msg';
  }
  return null;
}
const recs = [];
for (const f of appFiles) {
  const src = fs.readFileSync(f, 'utf8');
  let ast;
  try { ast = parse(src, { sourceType: 'module', plugins: ['jsx'], allowReturnOutsideFunction: true, allowUndeclaredExports: true, errorRecovery: true }); } catch { continue; }
  const strings = [], props = new Set(), testids = new Set(), names = [], exportsL = [];
  let jsx = 0;
  for (const s of ast.program.body) {
    const d = s.type === 'ExportNamedDeclaration' && s.declaration ? s.declaration : s;
    if ((d.type === 'FunctionDeclaration' || d.type === 'ClassDeclaration') && d.id) names.push(d.id.name);
    else if (d.type === 'VariableDeclaration') for (const x of d.declarations) if (x.id.type === 'Identifier') names.push(x.id.name);
    if (s.type === 'ExportNamedDeclaration' && !s.declaration) for (const sp of s.specifiers) exportsL.push(sp.exported.name ?? sp.exported.value);
  }
  walk(ast.program, (n, parent, key) => {
    if (n.type === 'StringLiteral') {
      strings.push(n.value);
      if (parent?.type === 'ObjectProperty' && key === 'value') {
        const k = parent.key.type === 'Identifier' ? parent.key.name : parent.key.value;
        if (k === 'data-testid') testids.add(n.value);
      }
      if (parent?.type === 'JSXAttribute' && parent.name.name === 'data-testid') testids.add(n.value);
    } else if (n.type === 'TemplateElement' && n.value.cooked) strings.push(n.value.cooked);
    else if (n.type === 'JSXText') { const v = n.value.trim(); if (v) strings.push(v); }
    else if (n.type === 'JSXElement') jsx++;
    else if (n.type === 'JSXAttribute' && n.name.type === 'JSXIdentifier' && /^(data|aria)-/.test(n.name.name)) strings.push(n.name.name);
    else if (n.type === 'MemberExpression' && !n.computed && n.property.type === 'Identifier') { props.add(n.property.name); if (/^jsxs?$/.test(n.property.name)) jsx++; }
    else if (n.type === 'Identifier') props.add(n.name);
  });
  const cats = {};
  for (const [c, pre, sre] of CATS) {
    let sc = 0;
    for (const p of props) if (pre.test(p)) sc += 1;
    for (const s of new Set(strings)) if (s.length < 60 && sre.test(s)) sc += 1;
    if (sc) cats[c] = sc;
  }
  const lines = src.split('\n').length;
  const giant = /\[giant-function split\] ([\w$]+): body part (\d+) of (\d+)/.exec(src);
  recs.push({ file: path.relative(ROOT, f), lines, strings: [...new Set(strings)], testids: [...testids], names, exports: exportsL, cats, jsx, giant });
}
// distinctiveness
const df = new Map();
for (const r of recs) for (const s of r.strings) df.set(s, (df.get(s) || 0) + 1);
const tsv = [];
for (const r of recs) {
  r.distinct = [];
  for (const s of r.strings) {
    let c = classify(s);
    if (!c) continue;
    if (c === 'classes') {
      for (const tok of s.split(/\s+/)) if (/^[a-zA-Z][\w-]*$/.test(tok) && tok.includes('-') && !TW.test(tok) && !/^(cds|tb)-reset$/.test(tok)) r.distinct.push(['css', tok]);
      continue;
    }
    if (df.get(s) > 6 && c !== 'msg') continue;
    r.distinct.push([c, s]);
  }
  for (const t of r.testids) r.distinct.push(['testid', t]);
  const seen = new Set();
  r.distinct = r.distinct.filter(([c, s]) => (seen.has(c + s) ? false : seen.add(c + s)));
  for (const [c, s] of r.distinct.slice(0, 400)) tsv.push(`${r.file}\t${c}\t${s.replace(/\t/g, ' ')}`);
}
fs.writeFileSync(path.join(ROOT, 'STRINGS_INDEX.tsv'), '# file\tcategory\tstring   (categories: code=snake_case codes/reasons, const, event=ns:event, dotted=capability/op names, attr=data-*, selector, cssvar, kebab, camel, css=custom class token, testid, msg=UI/error message)\n' + tsv.join('\n') + '\n');

// MODULES.md
const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/`/g, "'").replace(/\n/g, ' ');
const CATNAME = (cats) => Object.entries(cats).sort((a, b) => b[1] - a[1]).filter(([, v]) => v >= 3).slice(0, 3).map(([k]) => k);
const rows = [];
for (const r of recs) {
  const cs = CATNAME(r.cats);
  let purpose = r.file.includes('imports-exports') ? 'chunk imports/exports (cross-chunk symbol map)' : '';
  if (!purpose) {
    const ui = r.jsx > 15 ? 'React UI' : r.jsx > 0 ? 'logic + some JSX' : 'logic';
    purpose = `${ui}${cs.length ? ': ' + cs.join(', ') : ''}`;
    if (r.giant) purpose = `giant fn ${r.giant[1]} part ${r.giant[2]}/${r.giant[3]}; ` + purpose;
  }
  const keyStr = r.distinct.filter(([c]) => c !== 'css' && c !== 'msg').slice(0, 6).map(([, s]) => s);
  const msg = r.distinct.filter(([c]) => c === 'msg').slice(0, 1).map(([, s]) => s.slice(0, 60));
  const names = (r.exports.length ? r.exports : r.names.filter((n) => n.length > 4)).slice(0, 8);
  rows.push(`| ${esc(r.file)} | ${r.lines} | ${esc(purpose)} | ${esc([...keyStr, ...msg].map((s) => '"' + s + '"').join(', '))} | ${esc(names.join(', '))} |`);
}
const vend = {};
for (const f of vendorFiles) {
  const lib = path.relative(path.join(ROOT, 'vendor'), f).split(path.sep)[0];
  vend[lib] = vend[lib] || { files: 0, lines: 0 };
  vend[lib].files++; vend[lib].lines += fs.readFileSync(f, 'utf8').split('\n').length;
}
const md = `# ${PRODUCT}: module map

Generated by \`tools/index.mjs\` from the split tree. **app/** = first-party code (${recs.length} files), **vendor/** = libraries identified by string signatures (${vendorFiles.length} files; safe to ignore when tracing).

Purpose column is a heuristic guess: "React UI"/"logic" from JSX-call density, then the top categories by keyword hits
(selection, transactions, collab, editing-commands, dom-input, pointer/drag, render/layout, schema/doc-model, comments, undo/history,
export/import, host-bridge/network, telemetry/errors). Key strings are the most distinctive literals in the file
(see STRINGS_INDEX.tsv for the full per-file list). Names are exports (if any) else non-minified top-level names.

Split boundaries: Bun bundles are cut at \`__esm\`/\`__commonJS\` wrapper boundaries, rolldown chunks at top-level
statements; consecutive statements are packed up to ~1200 lines. Functions over ~2500 lines are cut into
\`NAME__partK_of_N\` files (body statements in order; later parts reference locals declared in earlier parts).

## Vendor libraries

| lib | files | lines |
|---|---|---|
${Object.entries(vend).sort().map(([k, v]) => `| ${k} | ${v.files} | ${v.lines} |`).join('\n')}

## App files

| file | lines | purpose (guess) | key strings | names / exports |
|---|---|---|---|---|
${rows.join('\n')}
`;
fs.writeFileSync(path.join(ROOT, 'MODULES.md'), md);

// IDENTIFIERS.md
const manifests = fs.readdirSync(STATE).filter((f) => f.endsWith('.manifest.json')).map((f) => JSON.parse(fs.readFileSync(path.join(STATE, f), 'utf8')));
let idm = `# ${PRODUCT}: identifier mappings\n\nAll renames below were applied in the split files (minified name -> new name). Scope: top-level bindings of each bundle/chunk only.\nConventions: \`require_<lib>\` = CJS wrapper, \`init_<lib|topic>\` = Bun lazy ESM init, \`import_<lib>\` = __toESM(require_x()), \`<chunk>$<Export>\` = binding imported from another rolldown chunk whose export name was minified (look up \`<Export>\` in that chunk's imports-exports file).\n\nWakaru-lite rewrites applied everywhere: \`!0/!1\`->true/false, \`void 0\`->undefined, no-expression template literals -> strings, \`typeof x > "u"\` -> \`=== "undefined"\`, \`(0, f.g)(...)\` -> \`f.g(...)\`, statement-level sequences/\`&&\`/\`||\`/\`?:\` -> statements/if, arrow sequence bodies -> blocks.\n\n`;
idm += fs.existsSync(path.join(ROOT, 'IDENTIFIERS.manual.md')) ? fs.readFileSync(path.join(ROOT, 'IDENTIFIERS.manual.md'), 'utf8') + '\n' : '';
for (const m of manifests.sort((a, b) => a.tag.localeCompare(b.tag))) {
  if (!m.renames.length) continue;
  idm += `\n## ${path.basename(m.input)}\n\nRuntime helpers: ${Object.entries(m.helpers).map(([k, v]) => `\`${k}\`=${v}`).join(', ') || 'none'}\n\n| minified | renamed | why |\n|---|---|---|\n`;
  idm += m.renames.map(([a, b, w]) => `| \`${a}\` | \`${b}\` | ${esc(w)} |`).join('\n') + '\n';
}
fs.writeFileSync(path.join(ROOT, 'IDENTIFIERS.md'), idm);
fs.writeFileSync(path.join(STATE, 'index-recs.json'), JSON.stringify(recs.map((r) => ({ file: r.file, lines: r.lines, cats: r.cats, jsx: r.jsx, testids: r.testids.slice(0, 10), exports: r.exports }))));
console.log(PRODUCT, 'app', recs.length, 'vendor', vendorFiles.length, 'tsv rows', tsv.length);
