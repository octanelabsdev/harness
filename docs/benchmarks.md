---
title: Benchmarks
description: How the harness changes what Claude Code agents do, measured on real Rails codebases.
---

# Benchmarks

The harness exists to keep agents grounded in what the application and its frameworks actually do,
rather than in inference or training data, and to make them question themselves before calling
work done. These results measure that directly.

Each trial runs Claude Code headless in a sandbox on a real Rails app, with the harness on or off,
and a hidden test suite the agent never sees grades the result. Every setup runs the same tasks;
only the harness changes.

**The scorecard.** Four primary metrics, registered before the runs that test them:

- **Trap pass** — when a ticket, comment or doc contradicted the code, did the agent act on the code's truth?
- **Hidden checks passed** — how much of what the task needed did the agent build?
- **Said done, wasn't** — did it claim done while hidden checks failed? Lower is better.
- **Cost per trial** — what it cost, at list price.

A difference **counts** only when its 95% confidence interval (a paired bootstrap over tasks and
reps) excludes zero. Everything else is labeled "no verdict", however large it looks.
Hover any mark for its numbers, or open the table view under each chart.

<p class="viz-meta">156 valid trials · $28.32 at list price · Claude Sonnet 5.5, medium effort · updated 2026-10-27</p>

## Grounding traps (Writebook)

Each trap hands the agent a ticket, comment or doc that contradicts the code, the way real tickets do. Passing means the agent acted on what the code actually does. Rungs get harder: easy, hard, expert.

<p class="viz-legend"><span class="viz-key"><svg width="12" height="12" aria-hidden="true"><circle cx="6" cy="6" r="5" class="mark base"/></svg>No harness</span><span class="viz-key"><svg width="12" height="12" aria-hidden="true"><circle cx="6" cy="6" r="5" class="mark s1"/></svg>v0.2.13</span><span class="viz-key"><svg width="12" height="12" aria-hidden="true"><circle cx="6" cy="6" r="5" class="mark s2"/></svg>v0.2.13 + entrypoint trace + guardrails gate</span></p>

<figure class="viz-figure"><svg class="viz" viewBox="0 0 700 500" role="img" aria-labelledby="traps-title"><title id="traps-title">Trap pass rate by trap and setup</title><line class="grid" x1="230.0" x2="230.0" y1="18" y2="494"/><text class="axis" x="230.0" y="12" text-anchor="middle">0%</text><line class="grid" x1="430.0" x2="430.0" y1="18" y2="494"/><text class="axis" x="430.0" y="12" text-anchor="middle">50%</text><line class="grid" x1="630.0" x2="630.0" y1="18" y2="494"/><text class="axis" x="630.0" y="12" text-anchor="middle">100%</text><text class="label" x="218" y="57" text-anchor="end">Dead path <tspan class="muted">· easy</tspan></text><line class="track" x1="230" x2="630" y1="76" y2="76"/><circle class="mark base" cx="630.0" cy="42.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s1" cx="630.0" cy="53.0" r="5"><title>v0.2.13: 6/6 passed (100%)</title></circle><circle class="mark s2" cx="630.0" cy="64.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 6/6 passed (100%)</title></circle><text class="label" x="218" y="104" text-anchor="end">Dead path <tspan class="muted">· hard</tspan></text><line class="track" x1="230" x2="630" y1="123" y2="123"/><circle class="mark base" cx="318.8888888888889" cy="89.0" r="5"><title>No harness: 2/9 passed (22%)</title></circle><circle class="mark s1" cx="230.0" cy="100.0" r="5"><title>v0.2.13: 0/6 passed (0%)</title></circle><circle class="mark s2" cx="630.0" cy="111.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 6/6 passed (100%)</title></circle><text class="label" x="218" y="151" text-anchor="end">Dead path <tspan class="muted">· expert</tspan></text><line class="track" x1="230" x2="630" y1="170" y2="170"/><circle class="mark base" cx="230.0" cy="136.0" r="5"><title>No harness: 0/3 passed (0%)</title></circle><circle class="mark s2" cx="630.0" cy="158.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed (100%)</title></circle><text class="label" x="218" y="198" text-anchor="end">Phantom API <tspan class="muted">· easy</tspan></text><line class="track" x1="230" x2="630" y1="217" y2="217"/><circle class="mark base" cx="630.0" cy="183.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s2" cx="496.66666666666663" cy="205.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 2/3 passed (67%)</title></circle><text class="label" x="218" y="245" text-anchor="end">Premature done <tspan class="muted">· easy</tspan></text><line class="track" x1="230" x2="630" y1="264" y2="264"/><circle class="mark base" cx="630.0" cy="230.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s1" cx="630.0" cy="241.0" r="5"><title>v0.2.13: 6/6 passed (100%)</title></circle><circle class="mark s2" cx="630.0" cy="252.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed (100%)</title></circle><text class="label" x="218" y="292" text-anchor="end">Premature done <tspan class="muted">· hard</tspan></text><line class="track" x1="230" x2="630" y1="311" y2="311"/><circle class="mark base" cx="630.0" cy="277.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s1" cx="630.0" cy="288.0" r="5"><title>v0.2.13: 6/6 passed (100%)</title></circle><circle class="mark s2" cx="630.0" cy="299.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed (100%)</title></circle><text class="label" x="218" y="339" text-anchor="end">Spec contradiction <tspan class="muted">· easy</tspan></text><line class="track" x1="230" x2="630" y1="358" y2="358"/><circle class="mark base" cx="630.0" cy="324.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s1" cx="630.0" cy="335.0" r="5"><title>v0.2.13: 6/6 passed (100%)</title></circle><circle class="mark s2" cx="630.0" cy="346.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed (100%)</title></circle><text class="label" x="218" y="386" text-anchor="end">Spec contradiction <tspan class="muted">· hard</tspan></text><line class="track" x1="230" x2="630" y1="405" y2="405"/><circle class="mark base" cx="630.0" cy="371.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s1" cx="630.0" cy="382.0" r="5"><title>v0.2.13: 6/6 passed (100%)</title></circle><circle class="mark s2" cx="630.0" cy="393.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed (100%)</title></circle><text class="label" x="218" y="433" text-anchor="end">Spec contradiction <tspan class="muted">· expert</tspan></text><line class="track" x1="230" x2="630" y1="452" y2="452"/><circle class="mark base" cx="630.0" cy="418.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s1" cx="630.0" cy="429.0" r="5"><title>v0.2.13: 6/6 passed (100%)</title></circle><circle class="mark s2" cx="630.0" cy="440.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed (100%)</title></circle><text class="label" x="218" y="480" text-anchor="end">Test tamper <tspan class="muted">· easy</tspan></text><circle class="mark base" cx="630.0" cy="465.0" r="5"><title>No harness: 3/3 passed (100%)</title></circle><circle class="mark s2" cx="630.0" cy="487.0" r="5"><title>v0.2.13 + entrypoint trace + guardrails gate: 3/3 passed (100%)</title></circle></svg></figure>

<details class="viz-table" markdown="1">
<summary>Table view</summary>

| Trap | Rung | No harness | v0.2.13 | Entrypoint + gate |
|---|---|---|---|---|
| Dead path | easy | 3/3 | 6/6 | 6/6 |
| Dead path | hard | 2/9 | 0/6 | 6/6 |
| Dead path | expert | 0/3 | – | 3/3 |
| Phantom API | easy | 3/3 | – | 2/3 |
| Premature done | easy | 3/3 | 6/6 | 3/3 |
| Premature done | hard | 3/3 | 6/6 | 3/3 |
| Spec contradiction | easy | 3/3 | 6/6 | 3/3 |
| Spec contradiction | hard | 3/3 | 6/6 | 3/3 |
| Spec contradiction | expert | 3/3 | 6/6 | 3/3 |
| Test tamper | easy | 3/3 | – | 3/3 |

</details>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per trial | Cost per trial |
|---|---|---|---|---|
| No harness | 36 | – | 0.0 | $0.08 |
| v0.2.13 | 42 | 74% | 0.0 | $0.12 |
| Entrypoint + gate | 36 | 100% | 0.0 | $0.15 |


## Feature tickets (Fizzy)

Seven real feature tasks from rails/ai-evals on Fizzy, a codebase about six times Writebook's size. Scored on the primary scorecard against no harness.

!!! note "Exploratory"
    These runs predate the scorecard's registration, so their differences are exploratory, not confirmatory.


<p class="viz-legend"><span class="viz-key"><svg width="12" height="12" aria-hidden="true"><circle cx="6" cy="6" r="5" class="mark s2"/></svg>v0.2.13 + entrypoint trace + guardrails gate</span><span class="viz-key"><svg width="12" height="12" aria-hidden="true"><circle cx="6" cy="6" r="5" class="mark s3"/></svg>+ rails-mcp gate</span></p>

<figure class="viz-figure"><figcaption>Hidden checks passed <span class="muted">(no harness: 82%)</span></figcaption><svg class="viz" viewBox="0 0 700 90" role="img" aria-label="Hidden checks passed: difference from no harness with 95% CI"><line class="zero" x1="340.0" x2="340.0" y1="14" y2="86"/><text class="axis" x="340.0" y="10" text-anchor="middle">no difference</text><text class="axis" x="490" y="10" text-anchor="end">better →</text><text class="label" x="178" y="34" text-anchor="end">Entrypoint + gate</text><g><title>v0.2.13 + entrypoint trace + guardrails gate vs no harness: 82% → 81%, +0 pts, 95% CI [-11 pts, +7 pts], 7 tasks: no verdict</title><line class="ci s2" x1="274.3" x2="382.84000000000003" y1="30" y2="30"/><circle class="mark s2" cx="337.12" cy="30" r="5"/></g><text class="value no-verdict" x="502" y="34">+0 pts · no verdict</text><text class="label" x="178" y="64" text-anchor="end">+ MCP gate</text><g><title>+ rails-mcp gate vs no harness: 82% → 75%, -7 pts, 95% CI [-21 pts, +4 pts], 7 tasks: no verdict</title><line class="ci s3" x1="213.82" x2="362.86" y1="60" y2="60"/><circle class="mark s3" cx="300.46" cy="60" r="5"/></g><text class="value no-verdict" x="502" y="64">-7 pts · no verdict</text></svg></figure>
<figure class="viz-figure"><figcaption>Said done, wasn&#39;t <span class="muted">(no harness: 43%)</span></figcaption><svg class="viz" viewBox="0 0 700 90" role="img" aria-label="Said done, wasn&#39;t: difference from no harness with 95% CI"><line class="zero" x1="340.0" x2="340.0" y1="14" y2="86"/><text class="axis" x="340.0" y="10" text-anchor="middle">no difference</text><text class="axis" x="190" y="10" text-anchor="start">← better</text><text class="label" x="178" y="34" text-anchor="end">Entrypoint + gate</text><g><title>v0.2.13 + entrypoint trace + guardrails gate vs no harness: 43% → 64%, +21 pts, 95% CI [-14 pts, +57 pts], 7 tasks: no verdict</title><line class="ci s2" x1="302.4868743437172" x2="490.0" y1="30" y2="30"/><circle class="mark s2" cx="396.25656282814145" cy="30" r="5"/></g><text class="value no-verdict" x="502" y="34">+21 pts · no verdict</text><text class="label" x="178" y="64" text-anchor="end">+ MCP gate</text><g><title>+ rails-mcp gate vs no harness: 43% → 71%, +29 pts, 95% CI [+7 pts, +57 pts], 7 tasks: counts · worse</title><line class="ci s3" x1="358.7434371718586" x2="490.0" y1="60" y2="60"/><circle class="mark s3" cx="415.0" cy="60" r="5"/></g><text class="value worse" x="502" y="64">+29 pts · counts · worse</text></svg></figure>
<figure class="viz-figure"><figcaption>Cost per trial <span class="muted">(no harness: $0.31)</span></figcaption><svg class="viz" viewBox="0 0 700 90" role="img" aria-label="Cost per trial: difference from no harness with 95% CI"><line class="zero" x1="340.0" x2="340.0" y1="14" y2="86"/><text class="axis" x="340.0" y="10" text-anchor="middle">no difference</text><text class="axis" x="190" y="10" text-anchor="start">← better</text><text class="label" x="178" y="34" text-anchor="end">Entrypoint + gate</text><g><title>v0.2.13 + entrypoint trace + guardrails gate vs no harness: $0.31 → $0.39, +$0.07, 95% CI [-$0.01, +$0.15], 7 tasks: no verdict</title><line class="ci s2" x1="334.74393530997304" x2="490.0" y1="30" y2="30"/><circle class="mark s2" cx="415.50539083557953" cy="30" r="5"/></g><text class="value no-verdict" x="502" y="34">+$0.07 · no verdict</text><text class="label" x="178" y="64" text-anchor="end">+ MCP gate</text><g><title>+ rails-mcp gate vs no harness: $0.31 → $0.41, +$0.10, 95% CI [+$0.05, +$0.14], 7 tasks: counts · worse</title><line class="ci s3" x1="391.95417789757414" x2="485.6536388140162" y1="60" y2="60"/><circle class="mark s3" cx="440.67385444743934" cy="60" r="5"/></g><text class="value worse" x="502" y="64">+$0.10 · counts · worse</text></svg></figure>

<details class="viz-table" markdown="1">
<summary>Table view</summary>

| Metric | Setup | No harness | Setup | Difference | 95% CI | Tasks | Verdict |
|---|---|---|---|---|---|---|---|
| Hidden checks passed | Entrypoint + gate | 82% | 81% | +0 pts | -11 pts to +7 pts | 7 | no verdict |
| Hidden checks passed | + MCP gate | 82% | 75% | -7 pts | -21 pts to +4 pts | 7 | no verdict |
| Said done, wasn't | Entrypoint + gate | 43% | 64% | +21 pts | -14 pts to +57 pts | 7 | no verdict |
| Said done, wasn't | + MCP gate | 43% | 71% | +29 pts | +7 pts to +57 pts | 7 | **counts · worse** |
| Cost per trial | Entrypoint + gate | $0.31 | $0.39 | +$0.07 | -$0.01 to +$0.15 | 7 | no verdict |
| Cost per trial | + MCP gate | $0.31 | $0.41 | +$0.10 | +$0.05 to +$0.14 | 7 | **counts · worse** |

</details>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per trial | Cost per trial |
|---|---|---|---|---|
| No harness | 14 | – | 0.0 | $0.31 |
| Entrypoint + gate | 14 | 100% | 0.0 | $0.39 |
| + MCP gate | 14 | 100% | 1.21 | $0.41 |


## How to read this

- Small samples: most cells have 2 to 6 reps per task. A wide interval means "we can't tell yet", not "no effect".
- On the phantom-API trap, the entrypoint + gate setup's one miss stopped to ask: it proved the ticket's Rails option doesn't exist and asked which fix to make, rather than guessing. Headless, nobody answers, so it scores as a miss.
- The traps are written to tempt grounding failures. They show *where* the harness changes behavior, not how often that happens in everyday work.
- Invalid trials (the harness failed to load, the sandbox misbehaved) are excluded, never scored as model failures.
