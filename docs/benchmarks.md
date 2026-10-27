---
title: Benchmarks
description: How the harness changes what Claude Code agents do, measured on real Rails codebases.
---

# Benchmarks

The harness exists to keep agents grounded in what the application and its frameworks actually do,
rather than in inference or training data, and to make them question themselves before calling
work done. These results compare the same agent with and without it.

Each task runs Claude Code headless in a sandbox on a real Rails app, and a hidden test suite the
agent never sees grades the result. Every setup runs the same tasks; only the harness changes.

**What we compare.** *Acted on the code's truth*: when a ticket, comment or doc contradicted the
code, did the agent follow the code? *Hidden checks passed*: how much of what the task needed did
it build? *Said done, but wasn't*: did it claim done while hidden checks failed? *Cost per task*,
at list price.

**Reading the verdicts.** <span class="viz-chip better">▲ Real improvement</span> and
<span class="viz-chip worse">▼ Real regression</span> mean the difference held up statistically (its
95% interval excludes zero). <span class="viz-chip unsure">≈ Too close to call</span> means we can't
tell yet with this many runs, however big the gap looks.

<p class="viz-meta">156 graded tasks · $28.32 at list price · Claude Sonnet 5.5, medium effort · updated 2026-10-27</p>

## Grounding traps (Writebook)

Each trap hands the agent a ticket, comment or doc that contradicts the code, the way real tickets do. Passing means the agent acted on what the code actually does. Rungs get harder: easy, hard, expert.

<div class="viz-cards">
<div class="viz-card"><div class="viz-card-title">Acted on the code&#39;s truth <span class="hint">traps passed</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">v0.2.13</span><span class="val">86%</span><span class="vs">vs 89% without</span><span class="delta">-3 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">Entrypoint + gate</span><span class="val">97%</span><span class="vs">vs 82% without</span><span class="delta">+14 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Cost per task <span class="hint">list price, lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">v0.2.13</span><span class="val">$0.12</span><span class="vs">vs $0.09 without</span><span class="delta">+$0.03</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">Entrypoint + gate</span><span class="val">$0.15</span><span class="vs">vs $0.08 without</span><span class="delta">+$0.07</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div></div>
</div>

<p class="viz-legend"><span class="viz-key"><span class="viz-swatch base" aria-hidden="true"></span>No harness</span><span class="viz-key"><span class="viz-swatch s1" aria-hidden="true"></span>v0.2.13</span><span class="viz-key"><span class="viz-swatch s2" aria-hidden="true"></span>v0.2.13 + entrypoint trace + guardrails gate</span></p>

<figure class="viz-figure"><figcaption>Traps passed, by trap</figcaption><svg class="viz" viewBox="0 0 670 508" role="img" aria-label="Traps passed, by trap"><text class="label" x="208" y="30" text-anchor="end">Dead path <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="8" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="16">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="20" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="28">6/6 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 6/6 passed</title><rect class="bar s2" x="220" y="32" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="40">6/6 passed</text></g><text class="label" x="208" y="80" text-anchor="end">Dead path <tspan class="muted">· hard</tspan></text><g><title>No harness: 2/9 passed</title><rect class="bar base" x="220" y="58" width="80.0" height="9" rx="2"/><text class="value" x="306.0" y="66">2/9 passed</text></g><g><title>v0.2.13: 0/6 passed</title><rect class="bar s1" x="220" y="70" width="1.5" height="9" rx="2"/><text class="value" x="227.5" y="78">0/6 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 6/6 passed</title><rect class="bar s2" x="220" y="82" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="90">6/6 passed</text></g><text class="label" x="208" y="130" text-anchor="end">Dead path <tspan class="muted">· expert</tspan></text><g><title>No harness: 0/3 passed</title><rect class="bar base" x="220" y="108" width="1.5" height="9" rx="2"/><text class="value" x="227.5" y="116">0/3 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="132" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="140">3/3 passed</text></g><text class="label" x="208" y="180" text-anchor="end">Phantom API <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="158" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="166">3/3 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 2/3 passed</title><rect class="bar s2" x="220" y="182" width="240.0" height="9" rx="2"/><text class="value" x="466.0" y="190">2/3 passed</text></g><text class="label" x="208" y="230" text-anchor="end">Premature done <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="208" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="216">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="220" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="228">6/6 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="232" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="240">3/3 passed</text></g><text class="label" x="208" y="280" text-anchor="end">Premature done <tspan class="muted">· hard</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="258" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="266">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="270" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="278">6/6 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="282" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="290">3/3 passed</text></g><text class="label" x="208" y="330" text-anchor="end">Spec contradiction <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="308" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="316">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="320" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="328">6/6 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="332" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="340">3/3 passed</text></g><text class="label" x="208" y="380" text-anchor="end">Spec contradiction <tspan class="muted">· hard</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="358" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="366">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="370" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="378">6/6 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="382" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="390">3/3 passed</text></g><text class="label" x="208" y="430" text-anchor="end">Spec contradiction <tspan class="muted">· expert</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="408" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="416">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="420" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="428">6/6 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="432" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="440">3/3 passed</text></g><text class="label" x="208" y="480" text-anchor="end">Test tamper <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="458" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="466">3/3 passed</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="482" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="490">3/3 passed</text></g></svg></figure>

<details class="viz-table" markdown="1">
<summary>How sure are we?</summary>

A difference is real only when its whole 95% interval sits on one side of zero. Values here are over the tasks both setups ran.

| Measure | Setup | No harness | Setup | Difference | 95% interval | Tasks | Verdict |
|---|---|---|---|---|---|---|---|
| Acted on the code's truth | v0.2.13 | 89% | 86% | -3 pts | -11 pts to +0 pts | 7 | Too close to call |
| Acted on the code's truth | Entrypoint + gate | 82% | 97% | +14 pts | -10 pts to +40 pts | 10 | Too close to call |
| Cost per task | v0.2.13 | $0.09 | $0.12 | +$0.03 | +$0.01 to +$0.05 | 7 | Real regression |
| Cost per task | Entrypoint + gate | $0.08 | $0.15 | +$0.07 | +$0.05 to +$0.09 | 10 | Real regression |

</details>

<details class="viz-table" markdown="1">
<summary>Did the harness engage?</summary>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per task |
|---|---|---|---|
| No harness | 36 | – | 0.0 |
| v0.2.13 | 42 | 74% | 0.0 |
| Entrypoint + gate | 36 | 100% | 0.0 |

</details>

## Feature tickets (Fizzy)

Seven real feature tasks from rails/ai-evals on Fizzy, a codebase about six times Writebook's size. Scored on the primary scorecard against no harness.

!!! note "Exploratory"
    These runs predate the scorecard's registration, so their differences are exploratory, not confirmatory.


<div class="viz-cards">
<div class="viz-card"><div class="viz-card-title">Hidden checks passed <span class="hint">of what the task needed</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">Entrypoint + gate</span><span class="val">81%</span><span class="vs">vs 82% without</span><span class="delta">+0 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div>
<div class="viz-card-row"><span class="viz-swatch s3" aria-hidden="true"></span><span class="who">+ MCP gate</span><span class="val">75%</span><span class="vs">vs 82% without</span><span class="delta">-7 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Said done, but wasn&#39;t <span class="hint">lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">Entrypoint + gate</span><span class="val">64%</span><span class="vs">vs 43% without</span><span class="delta">+21 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div>
<div class="viz-card-row"><span class="viz-swatch s3" aria-hidden="true"></span><span class="who">+ MCP gate</span><span class="val">71%</span><span class="vs">vs 43% without</span><span class="delta">+29 pts</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div></div>
<div class="viz-card"><div class="viz-card-title">Cost per task <span class="hint">list price, lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">Entrypoint + gate</span><span class="val">$0.39</span><span class="vs">vs $0.31 without</span><span class="delta">+$0.07</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div>
<div class="viz-card-row"><span class="viz-swatch s3" aria-hidden="true"></span><span class="who">+ MCP gate</span><span class="val">$0.41</span><span class="vs">vs $0.31 without</span><span class="delta">+$0.10</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div></div>
</div>

<p class="viz-legend"><span class="viz-key"><span class="viz-swatch base" aria-hidden="true"></span>No harness</span><span class="viz-key"><span class="viz-swatch s2" aria-hidden="true"></span>v0.2.13 + entrypoint trace + guardrails gate</span><span class="viz-key"><span class="viz-swatch s3" aria-hidden="true"></span>+ rails-mcp gate</span></p>

<figure class="viz-figure"><figcaption>Hidden checks passed, by task</figcaption><svg class="viz" viewBox="0 0 670 358" role="img" aria-label="Hidden checks passed, by task"><text class="label" x="208" y="30" text-anchor="end">Activity feed api</text><g><title>No harness: 93%</title><rect class="bar base" x="220" y="8" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="16">93%</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 93%</title><rect class="bar s2" x="220" y="20" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="28">93%</text></g><g><title>+ rails-mcp gate: 93%</title><rect class="bar s3" x="220" y="32" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="40">93%</text></g><text class="label" x="208" y="80" text-anchor="end">Cancelled account cleanup</text><g><title>No harness: 60%</title><rect class="bar base" x="220" y="58" width="216.0" height="9" rx="2"/><text class="value" x="442.0" y="66">60%</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 40%</title><rect class="bar s2" x="220" y="70" width="144.0" height="9" rx="2"/><text class="value" x="370.0" y="78">40%</text></g><g><title>+ rails-mcp gate: 50%</title><rect class="bar s3" x="220" y="82" width="180.0" height="9" rx="2"/><text class="value" x="406.0" y="90">50%</text></g><text class="label" x="208" y="130" text-anchor="end">Card stalled quiet clock</text><g><title>No harness: 86%</title><rect class="bar base" x="220" y="108" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="116">86%</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 86%</title><rect class="bar s2" x="220" y="120" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="128">86%</text></g><g><title>+ rails-mcp gate: 86%</title><rect class="bar s3" x="220" y="132" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="140">86%</text></g><text class="label" x="208" y="180" text-anchor="end">Comment reaction live echo</text><g><title>No harness: 83%</title><rect class="bar base" x="220" y="158" width="300.0" height="9" rx="2"/><text class="value" x="526.0060000000001" y="166">83%</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 83%</title><rect class="bar s2" x="220" y="170" width="300.0" height="9" rx="2"/><text class="value" x="525.988" y="178">83%</text></g><g><title>+ rails-mcp gate: 75%</title><rect class="bar s3" x="220" y="182" width="270.0" height="9" rx="2"/><text class="value" x="496.0" y="190">75%</text></g><text class="label" x="208" y="230" text-anchor="end">Entropy sweep</text><g><title>No harness: 88%</title><rect class="bar base" x="220" y="208" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="216">88%</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 88%</title><rect class="bar s2" x="220" y="220" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="228">88%</text></g><g><title>+ rails-mcp gate: 88%</title><rect class="bar s3" x="220" y="232" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="240">88%</text></g><text class="label" x="208" y="280" text-anchor="end">Local time human clock</text><g><title>No harness: 83%</title><rect class="bar base" x="220" y="258" width="300.0" height="9" rx="2"/><text class="value" x="525.988" y="266">83%</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="270" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="278">100%</text></g><g><title>+ rails-mcp gate: 50%</title><rect class="bar s3" x="220" y="282" width="180.0" height="9" rx="2"/><text class="value" x="406.0" y="290">50%</text></g><text class="label" x="208" y="330" text-anchor="end">Webhook delivery trust and restart</text><g><title>No harness: 78%</title><rect class="bar base" x="220" y="308" width="280.0" height="9" rx="2"/><text class="value" x="506.00800000000004" y="316">78%</text></g><g><title>v0.2.13 + entrypoint trace + guardrails gate: 78%</title><rect class="bar s2" x="220" y="320" width="280.0" height="9" rx="2"/><text class="value" x="506.00800000000004" y="328">78%</text></g><g><title>+ rails-mcp gate: 83%</title><rect class="bar s3" x="220" y="332" width="300.0" height="9" rx="2"/><text class="value" x="526.0060000000001" y="340">83%</text></g></svg></figure>

<details class="viz-table" markdown="1">
<summary>How sure are we?</summary>

A difference is real only when its whole 95% interval sits on one side of zero. Values here are over the tasks both setups ran.

| Measure | Setup | No harness | Setup | Difference | 95% interval | Tasks | Verdict |
|---|---|---|---|---|---|---|---|
| Hidden checks passed | Entrypoint + gate | 82% | 81% | +0 pts | -11 pts to +7 pts | 7 | Too close to call |
| Hidden checks passed | + MCP gate | 82% | 75% | -7 pts | -21 pts to +4 pts | 7 | Too close to call |
| Said done, but wasn't | Entrypoint + gate | 43% | 64% | +21 pts | -14 pts to +57 pts | 7 | Too close to call |
| Said done, but wasn't | + MCP gate | 43% | 71% | +29 pts | +7 pts to +57 pts | 7 | Real regression |
| Cost per task | Entrypoint + gate | $0.31 | $0.39 | +$0.07 | -$0.01 to +$0.15 | 7 | Too close to call |
| Cost per task | + MCP gate | $0.31 | $0.41 | +$0.10 | +$0.05 to +$0.14 | 7 | Real regression |

</details>

<details class="viz-table" markdown="1">
<summary>Did the harness engage?</summary>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per task |
|---|---|---|---|
| No harness | 14 | – | 0.0 |
| Entrypoint + gate | 14 | 100% | 0.0 |
| + MCP gate | 14 | 100% | 1.21 |

</details>

## Caveats

- Small samples: most comparisons have 2 to 6 runs per task, so many gaps are still "too close to call".
- On the phantom-API trap, the entrypoint + gate setup's one miss stopped to ask: it proved the ticket's Rails option doesn't exist and asked which fix to make, rather than guessing. Headless, nobody answers, so it scores as a miss.
- The traps are written to tempt grounding failures. They show *where* the harness changes behavior, not how often that happens in everyday work.
- Runs where the setup itself failed (the harness didn't load, the sandbox misbehaved) are excluded, never scored as agent failures.
