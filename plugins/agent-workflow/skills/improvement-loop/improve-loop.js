// improve-loop.js — the project-agnostic engine for a multi-agent improvement round.
//
// Pass this to the Workflow tool via `scriptPath` with:
//   args.root        absolute worktree path (the script is sandboxed — it can't read cwd)
//   args.tasks       the backlog array: [{ id, wave, files, brief }]
//   args.common      the project's CONTEXT block (rules + verify commands) every agent inherits
//   args.backlogPath (optional) where the scout writes the next backlog;
//                    default 'docs/improvement-backlog.json' (a sibling '.md' is written too)
//
// Resume after a death/limit:
//   Workflow({ scriptPath: <this file>, resumeFromRunId: <runId> })
//   — completed agents replay from cache; only the killed tail re-runs.
//
// Nothing project-specific lives here — it's all in args.common and the task briefs.
// See SKILL.md for how to assemble args and run a round.

export const meta = {
  name: "improvement-round",
  description:
    "Implement a file-disjoint waved backlog in parallel, verify, adversarially review (find → refute/judge each finding), fix, document, commit, and scout the next backlog",
  phases: [
    {
      title: "Implement",
      detail: "one wave at a time; agents parallel within a wave",
    },
    {
      title: "Verify",
      detail:
        "full suites + review lenses + per-finding adversarial verification",
    },
    {
      title: "Fix",
      detail: "fix confirmed findings + failing suites, re-verify",
    },
    {
      title: "Finalize",
      detail: "docs refresh + scout next backlog + scoped commits",
    },
  ],
};

const ROOT = args.root;
const TASKS = args.tasks;
const COMMON = args.common;
const BACKLOG = args.backlogPath || "docs/improvement-backlog.json";
const BACKLOG_MD = BACKLOG.replace(/\.json$/, ".md");

if (!ROOT || !Array.isArray(TASKS) || !COMMON) {
  throw new Error(
    "improve-loop: args must include root (string), tasks (array), common (string)",
  );
}

const RESULT = {
  type: "object",
  required: ["status", "summary", "filesTouched", "testsRun"],
  properties: {
    status: { type: "string", enum: ["done", "partial", "blocked"] },
    summary: { type: "string" },
    filesTouched: { type: "array", items: { type: "string" } },
    testsRun: {
      type: "string",
      description: "which suites you ran and their pass/fail",
    },
    notes: {
      type: "string",
      description: "deviations, discovered facts, follow-ups",
    },
  },
};
const SUITES = {
  type: "object",
  required: ["allGreen", "results"],
  properties: {
    allGreen: { type: "boolean" },
    results: {
      type: "array",
      items: {
        type: "object",
        required: ["suite", "passed", "detail"],
        properties: {
          suite: { type: "string" },
          passed: { type: "boolean" },
          detail: {
            type: "string",
            description: "counts, or failing test names + key error lines",
          },
        },
      },
    },
  },
};
const FINDINGS = {
  type: "object",
  required: ["findings"],
  properties: {
    findings: {
      type: "array",
      items: {
        type: "object",
        required: ["title", "file", "severity", "detail"],
        properties: {
          title: { type: "string" },
          file: { type: "string" },
          severity: { type: "string", enum: ["critical", "major", "minor"] },
          detail: {
            type: "string",
            description: "what is wrong, where, and what correct looks like",
          },
        },
      },
    },
  },
};
const VERDICT = {
  type: "object",
  required: ["isReal", "reason"],
  properties: { isReal: { type: "boolean" }, reason: { type: "string" } },
};

const implPrompt = (t) =>
  COMMON +
  `\nYOUR TASK (id: ${t.id}):\n${t.brief}\n\nWhen finished: run your area's verify commands, make them green, and report honestly. status=partial/blocked with a reason beats a false done.`;

// ── Implement: one wave at a time, agents parallel within a wave ──
const results = {};
const waves = [...new Set(TASKS.map((t) => t.wave))].sort((a, b) => a - b);
for (const w of waves) {
  const wt = TASKS.filter((t) => t.wave === w);
  phase("Implement");
  log(`Wave ${w}: ${wt.map((t) => t.id).join(", ")}`);
  const out = await parallel(
    wt.map(
      (t) => () =>
        agent(implPrompt(t), {
          label: t.id,
          phase: "Implement",
          schema: RESULT,
        }),
    ),
  );
  wt.forEach((t, i) => {
    results[t.id] = out[i];
  });
  const bad = wt.filter((t, i) => !out[i] || out[i].status === "blocked");
  if (bad.length)
    log(
      `WARNING — blocked/dead this wave: ${bad.map((t) => t.id).join(", ")} (verify will catch fallout)`,
    );
}

// ── Verify: full suites, then adversarial review (find → verify each finding) ──
phase("Verify");
const suitesPrompt =
  COMMON +
  `\nYOUR TASK: run ALL the project's verify commands (the ones in CONTEXT) and report each suite's TRUE result with failing test names + key error lines. Do NOT fix anything — just run and report.`;
let suites = await agent(suitesPrompt, {
  label: "run-suites",
  phase: "Verify",
  schema: SUITES,
});
log(
  "Suites: " +
    (suites && suites.allGreen
      ? "ALL GREEN"
      : "FAILURES — " +
        (suites
          ? suites.results
              .filter((r) => !r.passed)
              .map((r) => r.suite)
              .join(", ")
          : "suite agent died")),
);

const LENSES = [
  {
    key: "correctness",
    prompt:
      "LENS — correctness: real bugs THIS diff introduces — logic errors, broken edge cases, contract/sync-fence mismatches, fabricated or regressed behavior, silent failures.",
  },
  {
    key: "tests",
    prompt:
      "LENS — test quality: performative/tautological tests (assert-the-mock), missing boundary coverage on new pure logic, weakened/rewritten assertions, tests that read live or non-deterministic sources.",
  },
  {
    key: "quality",
    prompt:
      "LENS — house style + leftovers: dead code, stale comments/docs the diff makes false, UNFIXED SIBLINGS (a flaw fixed in one place but left nearby), style-guide violations, narration comments.",
  },
];
const reviewBase =
  COMMON +
  `\nYOUR TASK: review the UNCOMMITTED working-tree changes only. Use: git -C ${ROOT} status --short; git -C ${ROOT} diff; and READ new untracked files fully (they don't appear in diff). Report only real, specific defects with file+location — no nitpicks, no praise. Empty findings array if clean.\n`;
const reviews = await parallel(
  LENSES.map(
    (l) => () =>
      agent(reviewBase + l.prompt, {
        label: "review:" + l.key,
        phase: "Verify",
        schema: FINDINGS,
      }),
  ),
);
const all = reviews.filter(Boolean).flatMap((r) => r.findings);
const seen = new Set();
const deduped = all.filter((f) => {
  const k = f.file + "|" + f.title.toLowerCase().slice(0, 60);
  if (seen.has(k)) return false;
  seen.add(k);
  return true;
});
log(
  `Findings: ${all.length} raw, ${deduped.length} deduped — verifying each adversarially`,
);

// Each finding is judged by two independent agents (one told to REFUTE, defaulting
// to not-real). A finding survives if EITHER upholds it. This firewalls cheap
// claim-generation from the expensive code-mutation in the fix phase — plausible-
// but-wrong findings die here instead of churning correct code.
const verified = await parallel(
  deduped.map(
    (f) => () =>
      parallel([
        () =>
          agent(
            COMMON +
              `\nADVERSARIALLY REFUTE this code-review finding against the real uncommitted diff — is it a defect a maintainer must fix, or wrong/moot/preference? Read the actual code; default isReal=false if you cannot reproduce the reasoning.\n[${f.severity}] ${f.title} @ ${f.file}\n${f.detail}`,
            {
              label: "refute:" + f.title.slice(0, 22),
              phase: "Verify",
              schema: VERDICT,
            },
          ),
        () =>
          agent(
            COMMON +
              `\nIndependently judge this finding against the real uncommitted diff (read it yourself; don't trust the finding text). Real and worth fixing now?\n[${f.severity}] ${f.title} @ ${f.file}\n${f.detail}`,
            {
              label: "judge:" + f.title.slice(0, 22),
              phase: "Verify",
              schema: VERDICT,
            },
          ),
      ]).then((vs) => ({
        ...f,
        real: vs.filter(Boolean).some((v) => v.isReal),
      })),
  ),
);
const confirmed = verified.filter((f) => f.real);
log(`Confirmed findings: ${confirmed.length} of ${deduped.length}`);

// ── Fix: loop until suites green + confirmed findings addressed (cap 2 rounds) ──
phase("Fix");
if ((suites && !suites.allGreen) || confirmed.length) {
  for (let r = 1; r <= 2; r++) {
    const failText =
      suites && !suites.allGreen
        ? "FAILING SUITES:\n" +
          suites.results
            .filter((x) => !x.passed)
            .map((x) => x.suite + ": " + x.detail)
            .join("\n")
        : "All suites green.";
    const findText =
      confirmed.length && r === 1
        ? "CONFIRMED FINDINGS to fix:\n" +
          confirmed
            .map((f) => `- [${f.severity}] ${f.title} @ ${f.file}: ${f.detail}`)
            .join("\n")
        : "No outstanding findings.";
    await agent(
      COMMON +
        `\nFix the following in the uncommitted working tree (round ${r}). Work sequentially, smallest correct change first, keep all hard rules, re-run affected suites as you go.\n\n${failText}\n\n${findText}`,
      { label: "fixer-" + r, phase: "Fix", schema: RESULT },
    );
    suites = await agent(suitesPrompt, {
      label: "rerun-" + r,
      phase: "Fix",
      schema: SUITES,
    });
    if (suites && suites.allGreen) break;
  }
}
log(
  "Final suites: " +
    (suites && suites.allGreen ? "ALL GREEN" : "STILL FAILING — reported"),
);

// ── Finalize: docs refresh + SCOUT next backlog (parallel), then scoped commits ──
phase("Finalize");
const filesByTask = Object.entries(results)
  .map(([id, r]) => id + ": " + ((r && r.filesTouched) || []).join(", "))
  .join("\n");

const [docs, scout] = await parallel([
  () =>
    agent(
      COMMON +
        `\nYOUR TASK: refresh the project's docs to match the code as it NOW is (uncommitted working tree). Read git -C ${ROOT} status/diff and enumerate ONLY what actually shipped; correct any doc claim the diff makes false; re-run the suites for real counts. 9th-grade reading level; never invent features you can't see in the diff. Do NOT edit ${BACKLOG} / ${BACKLOG_MD} (the scout owns them).`,
      { label: "docs", phase: "Finalize", schema: RESULT },
    ),
  () =>
    agent(
      COMMON +
        `\nYOUR TASK: you are the improvement SCOUT for the NEXT round. Audit the project as it now stands — the uncommitted diff, the docs, and any live signals worth checking — and OVERWRITE the backlog:\n1. ${BACKLOG} — an array of {id, wave, files, brief} in EXACTLY the shape this engine consumes (waves = file-disjoint parallel groups; a task that consumes another's output goes in a LATER wave). 5-10 tasks, each concrete enough for a zero-context engineer (paths, evidence, the precise change, the TDD steps, the verify command).\n2. ${BACKLOG_MD} — the human-readable version: the task list with rationale + priorities, "what shipped last round" VERIFIED against the diff (not the task list), and your audit findings.\nStart from the CURRENT backlog if one exists: drop tasks that shipped, carry forward partials (note what remains), add what your audit surfaces (correctness gaps, honesty/contract violations, stale docs, sibling defects, operational fragility). Rank by value. Keep the json and md in lockstep.`,
      { label: "scout", phase: "Finalize", schema: RESULT },
    ),
]);

await agent(
  COMMON +
    `\nYOUR TASK: create scoped git commits for the uncommitted work. Rules: git -C ${ROOT} status --short FIRST; ONE commit per logical cluster below; add files by EXPLICIT path (never git add . / -A); conventional-commit style matching the branch history; do NOT push, do NOT open a PR. If pre-commit hooks auto-fix formatting, re-add the fixed files and retry once.\nClusters (verify against status; include closely-related untracked files each created):\n${filesByTask}\ndocs: the project docs + ${BACKLOG} + ${BACKLOG_MD}\nCommit the docs/backlog last. Report the commit SHAs + subjects.`,
  { label: "commits", phase: "Finalize", schema: RESULT },
);

return {
  tasks: Object.fromEntries(
    Object.entries(results).map(([id, r]) => [
      id,
      r ? { status: r.status, summary: r.summary } : "agent-died",
    ]),
  ),
  suites,
  reviewFindings: { raw: all.length, confirmed: confirmed.length },
  docs: docs ? docs.summary : "docs agent died",
  scout: scout ? scout.summary : "scout agent died",
};
