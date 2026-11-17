# Bundle splitter

Turns a minified JS bundle (Bun or rolldown output) into a readable tree that agents can search and read in bounded pieces.

**Safety.** It reads the bundle as text and parses it with Babel; wakaru parses each output file. Nothing imports or runs bundle code.

## Run

```sh
# copy into the project first, so the tool survives the session:
cp -R ~/.claude/skills/methodical-teardown/scripts/bundle-splitter <project>/tools/
cd <project>/tools/bundle-splitter && npm install
node run.mjs <project>/sources/<name>@<ver> <project>/sources/<name>@<ver>-readable [stateDir] [productName]
# a 10 MB, 7-chunk bundle takes about 40 s
```

`outDir` and `stateDir` are deleted and recreated on every run.
- `stateDir` defaults to `<outDir>/../split-state`. It holds the per-chunk `*.exports.json` and `*.manifest.json`, including every rename and why.
- For a single-file bundle such as Slides' `app.js`, run `split.mjs` directly, then `verify.mjs` and `index.mjs`:
  `node split.mjs <app.js> <out> . <state>`.

## Output

- `app/<chunk>/NNNN_<topic>.js`: first-party code, packed in about 1,200-line files in source order.
- `vendor/<library>/<chunk>_NNNN_<sublib>.js`: library code, in files of up to 4,000 lines.
- `MODULES.md`: per-file purpose guess, exports and key strings.
- `IDENTIFIERS.md`: the renamed identifiers.
- `STRINGS_INDEX.tsv`: every literal, categorised (code, event, attr, testid, cssvar, msg and so on).

## Why it's shaped this way

- **Custom splitting.** Bun and rolldown inline modules into one shared scope ("scope hoisting"). The only module boundaries left are the `__commonJS`/`__esm` wrappers and the chunk files.
  - On a 10 MB Docs bundle, webcrack 2.16 didn't split at all: one 157k-line file for `app-core`.
  - wakaru 1.14's heuristic unpacker covered 100% of the input. But it left `app-core` as 483 small files plus one 112k-line `entry.js`, and the Bun-built `lfile-runtime` as mostly one 237k-line file. It also skipped two of the seven chunk files, and had no vendor separation or indexes.
  - Hence our own splitter: split at the wrappers, then pack statements in source order.
- **Line caps (about 1,200 app, 4,000 vendor).** An agent reads a file whole. Bounded files let a reader trace a flow without loading a 100k-line file, and file numbers keep source order.
- **Vendor separation by string signatures.** Most of a bundle is libraries (React, ProseMirror, Yjs, …). Moving them to `vendor/` lets readers skip them. Library error and identifier strings survive minification, so they make reliable signatures.
- **Renames limited to top-level bindings and cross-chunk imports.** These can be done safely in one scoped pass, and chunks are processed dependencies first so importers reuse the exporter's names. Local names stay minified; renaming them needs guessing (an LLM-based renamer such as humanify), which we haven't tried.
- **wakaru for readability, run per output file.** It unminifies, turns ternary chains into `if`s, and recovers JSX. Our earlier hand-written rewrites did less, and one of them silently dropped statements. Running wakaru after the split keeps our file boundaries.
- **Indexes.** `MODULES.md` gives readers a hot list per subsystem. `STRINGS_INDEX.tsv` makes UI copy, error messages, test ids and telemetry names searchable, which is also evidence for jobs-to-be-done.
- **Proof that nothing was lost.** `lossless.mjs` checks every input string against the output. A readability tool that drops code silently is worse than no tool.

## How it works

1. **`run.mjs` (driver).**
   - Unwraps code shipped as a string (Docs' `virtual-lfile-extras-text-*.js`).
   - Orders the chunks by their `./x.js` imports, dependencies first.
   - Forces a vendor label on chunks whose file name already names the library (`react-*`, `shiki-*`, and so on).
   - Runs `split.mjs` on each chunk, then wakaru on every output file (in place), then prettier, `verify.mjs`, `lossless.mjs` and `index.mjs`.
2. **`split.mjs` (one chunk).** It uses `@babel/parser`, `@babel/traverse` and `@babel/generator`.
   1. Unwrap Bun's top-level IIFE, and split `var a=…,b=…` into one statement per name.
   2. Gather facts for each top-level statement: string literals, object keys, `data-testid`s and the amount of JSX.
   3. Detect the bundler runtime helpers (`__commonJS`, `__esm`, `__toESM`, `__export`) by their shape.
   4. Group statements into units at each `__commonJS`/`__esm` wrapper.
   5. **Vendor classification.** `sigs.mjs` holds a regex signature list over string literals for each library family and sub-library: react, react-dom, prosemirror-*, tiptap, yjs, zod, base-ui, katex and others.
      - Each unit gets the family with the most hits; some families need a minimum number of hits.
      - Unlabeled stretches between units of the same family are filled in.
      - Any unit containing first-party host markers (`__frame_`, `__fc_`, `/api/frame`) is vetoed back to app.
   6. **Renames** apply to top-level bindings only, and are planned and then applied in one scoped pass:
      - helpers get their role names;
      - `require_X`, `import_X` and `X_mod` get CJS/ESM wrapper names;
      - exports get their export names;
      - imports get the exporter's local names, from the state directory.
   7. **Generate and pack.** A guard throws if the statement count changed. Statements are packed into app or vendor files under the line caps. Functions over 2,500 lines are cut into `NAME__partK_of_N` files.
      - App files are named by their top TF-IDF tokens. A file named `0080_unrowed__caller.js`, for example, is a heuristic name, not a real module.
3. **wakaru** (`@wakaru/cli`, a native binary) rewrites each output file. A file it can't handle is kept as split and listed.
4. **`verify.mjs`** re-parses every output file with Babel (JSX allowed).
5. **`lossless.mjs`** checks that every input string survives. A string counts if it's an output literal, sits inside a longer output string (rewrites merge concatenations), or appears in the output text. It exits 1 if any are missing.
6. **`index.mjs`** writes `MODULES.md`, `STRINGS_INDEX.tsv` and `IDENTIFIERS.md`.

## Caveats

- File numbers and topic names change between bundle versions. Cite by minified symbol or string, not by file number.
- The output is for reading only. Files are not runnable, and giant-function parts close over earlier parts' locals.
- wakaru ships prebuilt binaries for macOS arm64, Linux and Windows only.

## Adapting to a new bundle

- `sigs.mjs`: add regex signatures for libraries that are not yet recognised; check `vendor/` against `app/` in `MODULES.md`.
- `run.mjs` `FORCE`: chunk-name prefixes that already name a library.
- `split.mjs` `FIRST_PARTY`: markers that veto a vendor label for the target's own code (currently tuned for the claude.ai frame host).
- After any change, check `verify.mjs` reports `bad 0`, `lossless.mjs` reports 0 missing, and the statement-count guard did not throw.
