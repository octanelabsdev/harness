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

<p class="viz-meta">362 graded tasks · $150.26 at list price · Claude Sonnet 5.5 at medium effort unless a section says otherwise · updated 2026-10-29</p>

## Confirmatory run

Seven Fizzy feature tasks and the three Writebook traps that separated setups in earlier runs, three runs each, scored on the scorecard registered before this run.

!!! success "Pre-registered"
    The four measures and the verdict rule were fixed before this run, so its verdicts are confirmatory.


<div class="viz-cards">
<div class="viz-card"><div class="viz-card-title">Acted on the code&#39;s truth <span class="hint">traps passed</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">78%</span><span class="vs">vs 22% without</span><span class="delta">+56 pts</span><span class="viz-chip better"><span aria-hidden="true">▲</span> Real improvement</span></div>
<div class="viz-card-row"><span class="viz-swatch s3" aria-hidden="true"></span><span class="who">+ Evidence + terms</span><span class="val">89%</span><span class="vs">vs 22% without</span><span class="delta">+67 pts</span><span class="viz-chip better"><span aria-hidden="true">▲</span> Real improvement</span></div></div>
<div class="viz-card"><div class="viz-card-title">Hidden checks passed <span class="hint">of what the task needed</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">82%</span><span class="vs">vs 75% without</span><span class="delta">+8 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div>
<div class="viz-card-row"><span class="viz-swatch s3" aria-hidden="true"></span><span class="who">+ Evidence + terms</span><span class="val">85%</span><span class="vs">vs 75% without</span><span class="delta">+10 pts</span><span class="viz-chip better"><span aria-hidden="true">▲</span> Real improvement</span></div></div>
<div class="viz-card"><div class="viz-card-title">Said done, but wasn&#39;t <span class="hint">lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">43%</span><span class="vs">vs 47% without</span><span class="delta">-3 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div>
<div class="viz-card-row"><span class="viz-swatch s3" aria-hidden="true"></span><span class="who">+ Evidence + terms</span><span class="val">47%</span><span class="vs">vs 47% without</span><span class="delta">+0 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Cost per task <span class="hint">list price, lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">$0.29</span><span class="vs">vs $0.24 without</span><span class="delta">+$0.05</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div>
<div class="viz-card-row"><span class="viz-swatch s3" aria-hidden="true"></span><span class="who">+ Evidence + terms</span><span class="val">$0.34</span><span class="vs">vs $0.24 without</span><span class="delta">+$0.11</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div></div>
</div>

<p class="viz-legend"><span class="viz-key"><span class="viz-swatch base" aria-hidden="true"></span>No harness</span><span class="viz-key"><span class="viz-swatch s2" aria-hidden="true"></span>v0.2.14: entrypoint trace + guardrails gate</span><span class="viz-key"><span class="viz-swatch s3" aria-hidden="true"></span>+ evidence check + term grounding</span></p>

<figure class="viz-figure"><figcaption>Hidden checks passed, by task</figcaption><svg class="viz" viewBox="0 0 670 508" role="img" aria-label="Hidden checks passed, by task"><text class="label" x="208" y="30" text-anchor="end">Activity feed api</text><g><title>No harness: 91%</title><rect class="bar base" x="220" y="8" width="328.0" height="9" rx="2"/><text class="value" x="553.996" y="16">91%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 93%</title><rect class="bar s2" x="220" y="20" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="28">93%</text></g><g><title>+ evidence check + term grounding: 93%</title><rect class="bar s3" x="220" y="32" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="40">93%</text></g><text class="label" x="208" y="80" text-anchor="end">Cancelled account cleanup</text><g><title>No harness: 40%</title><rect class="bar base" x="220" y="58" width="144.0" height="9" rx="2"/><text class="value" x="370.0" y="66">40%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 47%</title><rect class="bar s2" x="220" y="70" width="168.0" height="9" rx="2"/><text class="value" x="394.0" y="78">47%</text></g><g><title>+ evidence check + term grounding: 40%</title><rect class="bar s3" x="220" y="82" width="144.0" height="9" rx="2"/><text class="value" x="370.0" y="90">40%</text></g><text class="label" x="208" y="130" text-anchor="end">Card stalled quiet clock</text><g><title>No harness: 86%</title><rect class="bar base" x="220" y="108" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="116">86%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 86%</title><rect class="bar s2" x="220" y="120" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="128">86%</text></g><g><title>+ evidence check + term grounding: 86%</title><rect class="bar s3" x="220" y="132" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="140">86%</text></g><text class="label" x="208" y="180" text-anchor="end">Comment reaction live echo</text><g><title>No harness: 89%</title><rect class="bar base" x="220" y="158" width="320.0" height="9" rx="2"/><text class="value" x="545.992" y="166">89%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 83%</title><rect class="bar s2" x="220" y="170" width="300.0" height="9" rx="2"/><text class="value" x="526.0" y="178">83%</text></g><g><title>+ evidence check + term grounding: 89%</title><rect class="bar s3" x="220" y="182" width="320.0" height="9" rx="2"/><text class="value" x="545.992" y="190">89%</text></g><text class="label" x="208" y="230" text-anchor="end">Entropy sweep</text><g><title>No harness: 88%</title><rect class="bar base" x="220" y="208" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="216">88%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 88%</title><rect class="bar s2" x="220" y="220" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="228">88%</text></g><g><title>+ evidence check + term grounding: 88%</title><rect class="bar s3" x="220" y="232" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="240">88%</text></g><text class="label" x="208" y="280" text-anchor="end">Local time human clock</text><g><title>No harness: 83%</title><rect class="bar base" x="220" y="258" width="300.0" height="9" rx="2"/><text class="value" x="526.0" y="266">83%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 89%</title><rect class="bar s2" x="220" y="270" width="320.0" height="9" rx="2"/><text class="value" x="545.992" y="278">89%</text></g><g><title>+ evidence check + term grounding: 83%</title><rect class="bar s3" x="220" y="282" width="300.0" height="9" rx="2"/><text class="value" x="526.0" y="290">83%</text></g><text class="label" x="208" y="330" text-anchor="end">Webhook delivery trust and restart</text><g><title>No harness: 70%</title><rect class="bar base" x="220" y="308" width="253.3" height="9" rx="2"/><text class="value" x="479.332" y="316">70%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 59%</title><rect class="bar s2" x="220" y="320" width="213.3" height="9" rx="2"/><text class="value" x="439.336" y="328">59%</text></g><g><title>+ evidence check + term grounding: 78%</title><rect class="bar s3" x="220" y="332" width="280.0" height="9" rx="2"/><text class="value" x="506.00800000000004" y="340">78%</text></g><text class="label" x="208" y="380" text-anchor="end">Dead path trap <tspan class="muted">· expert</tspan></text><g><title>No harness: 67%</title><rect class="bar base" x="220" y="358" width="240.0" height="9" rx="2"/><text class="value" x="466.01199999999994" y="366">67%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 78%</title><rect class="bar s2" x="220" y="370" width="280.0" height="9" rx="2"/><text class="value" x="506.00800000000004" y="378">78%</text></g><g><title>+ evidence check + term grounding: 89%</title><rect class="bar s3" x="220" y="382" width="320.0" height="9" rx="2"/><text class="value" x="546.004" y="390">89%</text></g><text class="label" x="208" y="430" text-anchor="end">Dead path trap <tspan class="muted">· hard</tspan></text><g><title>No harness: 67%</title><rect class="bar base" x="220" y="408" width="240.0" height="9" rx="2"/><text class="value" x="466.01199999999994" y="416">67%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="420" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="428">100%</text></g><g><title>+ evidence check + term grounding: 100%</title><rect class="bar s3" x="220" y="432" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="440">100%</text></g><text class="label" x="208" y="480" text-anchor="end">Phantom API trap <tspan class="muted">· easy</tspan></text><g><title>No harness: 67%</title><rect class="bar base" x="220" y="458" width="240.0" height="9" rx="2"/><text class="value" x="466.0" y="466">67%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="470" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="478">100%</text></g><g><title>+ evidence check + term grounding: 100%</title><rect class="bar s3" x="220" y="482" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="490">100%</text></g></svg></figure>

<details class="viz-table" markdown="1">
<summary>How sure are we?</summary>

A difference is real only when its whole 95% interval sits on one side of zero. Values here are over the tasks both setups ran.

| Measure | Setup | No harness | Setup | Difference | 95% interval | Tasks | Verdict |
|---|---|---|---|---|---|---|---|
| Acted on the code's truth | v0.2.14 gate | 22% | 78% | +56 pts | +11 pts to +100 pts | 3 | Real improvement |
| Acted on the code's truth | + Evidence + terms | 22% | 89% | +67 pts | +22 pts to +100 pts | 3 | Real improvement |
| Hidden checks passed | v0.2.14 gate | 75% | 82% | +8 pts | -3 pts to +20 pts | 10 | Too close to call |
| Hidden checks passed | + Evidence + terms | 75% | 85% | +10 pts | +0 pts to +22 pts | 10 | Real improvement |
| Said done, but wasn't | v0.2.14 gate | 47% | 43% | -3 pts | -33 pts to +27 pts | 10 | Too close to call |
| Said done, but wasn't | + Evidence + terms | 47% | 47% | +0 pts | -27 pts to +27 pts | 10 | Too close to call |
| Cost per task | v0.2.14 gate | $0.24 | $0.29 | +$0.05 | +$0.01 to +$0.09 | 10 | Real regression |
| Cost per task | + Evidence + terms | $0.24 | $0.34 | +$0.11 | +$0.07 to +$0.15 | 10 | Real regression |

</details>

<details class="viz-table" markdown="1">
<summary>Did the harness engage?</summary>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per task |
|---|---|---|---|
| No harness | 30 | – | 0.0 |
| v0.2.14 gate | 30 | 100% | 0.0 |
| + Evidence + terms | 30 | 100% | 0.0 |

</details>

## Across models

The same ten tasks, no harness vs the v0.2.14 harness (entrypoint trace + guardrails gate), on three models at medium effort. Each model is compared only with itself; Sonnet's runs are the confirmatory run above.

!!! success "Pre-registered"
    The four measures and the verdict rule were fixed before this run, so its verdicts are confirmatory.


<p class="viz-legend"><span class="viz-key"><span class="viz-swatch base" aria-hidden="true"></span>No harness</span><span class="viz-key"><span class="viz-swatch s2" aria-hidden="true"></span>v0.2.14: entrypoint trace + guardrails gate</span></p>

<figure class="viz-figure"><figcaption>Acted on the code&#39;s truth, by model</figcaption><svg class="viz" viewBox="0 0 670 122" role="img" aria-label="Acted on the code&#39;s truth, by model"><text class="label" x="208" y="24" text-anchor="end">Haiku 5.5</text><g><title>No harness: 33%</title><rect class="bar base" x="220" y="8" width="120.0" height="9" rx="2"/><text class="value" x="345.988" y="16">33%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 89%</title><rect class="bar s2" x="220" y="20" width="320.0" height="9" rx="2"/><text class="value" x="546.004" y="28">89%</text></g><text class="label" x="208" y="62" text-anchor="end">Sonnet 5.5</text><g><title>No harness: 22%</title><rect class="bar base" x="220" y="46" width="80.0" height="9" rx="2"/><text class="value" x="305.992" y="54">22%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 78%</title><rect class="bar s2" x="220" y="58" width="280.0" height="9" rx="2"/><text class="value" x="506.00800000000004" y="66">78%</text></g><text class="label" x="208" y="100" text-anchor="end">Opus 5.5</text><g><title>No harness: 100%</title><rect class="bar base" x="220" y="84" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="92">100%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="96" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="104">100%</text></g></svg></figure>

<figure class="viz-figure"><figcaption>Hidden checks passed, by model</figcaption><svg class="viz" viewBox="0 0 670 122" role="img" aria-label="Hidden checks passed, by model"><text class="label" x="208" y="24" text-anchor="end">Haiku 5.5</text><g><title>No harness: 76%</title><rect class="bar base" x="220" y="8" width="272.5" height="9" rx="2"/><text class="value" x="498.484" y="16">76%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 83%</title><rect class="bar s2" x="220" y="20" width="298.0" height="9" rx="2"/><text class="value" x="523.972" y="28">83%</text></g><text class="label" x="208" y="62" text-anchor="end">Sonnet 5.5</text><g><title>No harness: 75%</title><rect class="bar base" x="220" y="46" width="268.9" height="9" rx="2"/><text class="value" x="494.884" y="54">75%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 82%</title><rect class="bar s2" x="220" y="58" width="296.1" height="9" rx="2"/><text class="value" x="522.1" y="66">82%</text></g><text class="label" x="208" y="100" text-anchor="end">Opus 5.5</text><g><title>No harness: 91%</title><rect class="bar base" x="220" y="84" width="326.5" height="9" rx="2"/><text class="value" x="552.484" y="92">91%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 92%</title><rect class="bar s2" x="220" y="96" width="330.4" height="9" rx="2"/><text class="value" x="556.372" y="104">92%</text></g></svg></figure>

<figure class="viz-figure"><figcaption>Said done, but wasn&#39;t, by model (lower is better)</figcaption><svg class="viz" viewBox="0 0 670 122" role="img" aria-label="Said done, but wasn&#39;t, by model (lower is better)"><text class="label" x="208" y="24" text-anchor="end">Haiku 5.5</text><g><title>No harness: 60%</title><rect class="bar base" x="220" y="8" width="216.0" height="9" rx="2"/><text class="value" x="442.0" y="16">60%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 40%</title><rect class="bar s2" x="220" y="20" width="144.0" height="9" rx="2"/><text class="value" x="370.0" y="28">40%</text></g><text class="label" x="208" y="62" text-anchor="end">Sonnet 5.5</text><g><title>No harness: 47%</title><rect class="bar base" x="220" y="46" width="168.0" height="9" rx="2"/><text class="value" x="394.012" y="54">47%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 43%</title><rect class="bar s2" x="220" y="58" width="156.0" height="9" rx="2"/><text class="value" x="381.988" y="66">43%</text></g><text class="label" x="208" y="100" text-anchor="end">Opus 5.5</text><g><title>No harness: 23%</title><rect class="bar base" x="220" y="84" width="84.0" height="9" rx="2"/><text class="value" x="309.988" y="92">23%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 33%</title><rect class="bar s2" x="220" y="96" width="120.0" height="9" rx="2"/><text class="value" x="345.988" y="104">33%</text></g></svg></figure>

<figure class="viz-figure"><figcaption>Cost per task, by model (list price, lower is better)</figcaption><svg class="viz" viewBox="0 0 670 122" role="img" aria-label="Cost per task, by model (list price, lower is better)"><text class="label" x="208" y="24" text-anchor="end">Haiku 5.5</text><g><title>No harness: $0.07</title><rect class="bar base" x="220" y="8" width="16.2" height="9" rx="2"/><text class="value" x="242.176" y="16">$0.07</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: $0.10</title><rect class="bar s2" x="220" y="20" width="24.5" height="9" rx="2"/><text class="value" x="250.456" y="28">$0.10</text></g><text class="label" x="208" y="62" text-anchor="end">Sonnet 5.5</text><g><title>No harness: $0.24</title><rect class="bar base" x="220" y="46" width="56.8" height="9" rx="2"/><text class="value" x="282.76" y="54">$0.24</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: $0.29</title><rect class="bar s2" x="220" y="58" width="69.4" height="9" rx="2"/><text class="value" x="295.408" y="66">$0.29</text></g><text class="label" x="208" y="100" text-anchor="end">Opus 5.5</text><g><title>No harness: $0.95</title><rect class="bar base" x="220" y="84" width="227.1" height="9" rx="2"/><text class="value" x="453.088" y="92">$0.95</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: $1.11</title><rect class="bar s2" x="220" y="96" width="266.5" height="9" rx="2"/><text class="value" x="492.54400000000004" y="104">$1.11</text></g></svg></figure>

<details class="viz-table" markdown="1">
<summary>How sure are we, per model?</summary>

| Model | Measure | No harness | Harness | Difference | 95% interval | Verdict |
|---|---|---|---|---|---|---|
| Haiku 5.5 | Acted on the code's truth | 33% | 89% | +56 pts | +0 pts to +100 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Haiku 5.5 | Hidden checks passed | 76% | 83% | +7 pts | -1 pts to +17 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Haiku 5.5 | Said done, but wasn't | 60% | 40% | -20 pts | -50 pts to +7 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Haiku 5.5 | Cost per task | $0.07 | $0.10 | +$0.03 | -$0.00 to +$0.09 | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Sonnet 5.5 | Acted on the code's truth | 22% | 78% | +56 pts | +11 pts to +100 pts | <span class="viz-chip better"><span aria-hidden="true">▲</span> Real improvement</span> |
| Sonnet 5.5 | Hidden checks passed | 75% | 82% | +8 pts | -3 pts to +20 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Sonnet 5.5 | Said done, but wasn't | 47% | 43% | -3 pts | -33 pts to +27 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Sonnet 5.5 | Cost per task | $0.24 | $0.29 | +$0.05 | +$0.01 to +$0.09 | <span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span> |
| Opus 5.5 | Acted on the code's truth | 100% | 100% | +0 pts | +0 pts to +0 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Opus 5.5 | Hidden checks passed | 91% | 92% | +1 pts | -6 pts to +11 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Opus 5.5 | Said done, but wasn't | 23% | 33% | +10 pts | +0 pts to +27 pts | <span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span> |
| Opus 5.5 | Cost per task | $0.95 | $1.11 | +$0.16 | +$0.02 to +$0.31 | <span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span> |

</details>

## Specialized agents (Opus)

Does routing work through specialized subagents beat one agent? The same ten tasks on Opus 5.5 at medium effort, all with the v0.2.14 harness. The baseline is the harness alone (the Opus runs above); the comparison adds a bundle of Rails specialist agents with rules that delegate every change to them and send every change to a code reviewer.

!!! note "Exploratory"
    One run per task for the agents setup (two on one task) against three for the baseline, and a cut from the registered three-rep design to fit the budget, so these differences are exploratory. Two agents-setup trials scored zero because a pre-existing flaky test (Storage::TotaledTest) failed in the app's own suite; the same test failed in other setups' runs too.


<div class="viz-cards">
<div class="viz-card"><div class="viz-card-title">Acted on the code&#39;s truth <span class="hint">traps passed</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">+ Specialized agents</span><span class="val">67%</span><span class="vs">vs 100% for v0.2.14 gate</span><span class="delta">-33 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Hidden checks passed <span class="hint">of what the task needed</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">+ Specialized agents</span><span class="val">63%</span><span class="vs">vs 92% for v0.2.14 gate</span><span class="delta">-28 pts</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div></div>
<div class="viz-card"><div class="viz-card-title">Said done, but wasn&#39;t <span class="hint">lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">+ Specialized agents</span><span class="val">40%</span><span class="vs">vs 33% for v0.2.14 gate</span><span class="delta">+7 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Cost per task <span class="hint">list price, lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">+ Specialized agents</span><span class="val">$2.99</span><span class="vs">vs $1.11 for v0.2.14 gate</span><span class="delta">+$1.88</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div></div>
</div>

<p class="viz-legend"><span class="viz-key"><span class="viz-swatch s2" aria-hidden="true"></span>v0.2.14: entrypoint trace + guardrails gate</span><span class="viz-key"><span class="viz-swatch s1" aria-hidden="true"></span>+ rails-agents: delegate every change, review every change</span></p>

<figure class="viz-figure"><figcaption>Hidden checks passed, by task</figcaption><svg class="viz" viewBox="0 0 670 388" role="img" aria-label="Hidden checks passed, by task"><text class="label" x="208" y="24" text-anchor="end">Activity feed api</text><g><title>v0.2.14: entrypoint trace + guardrails gate: 93%</title><rect class="bar s2" x="220" y="8" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="16">93%</text></g><g><title>+ rails-agents: delegate every change, review every change: 93%</title><rect class="bar s1" x="220" y="20" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="28">93%</text></g><text class="label" x="208" y="62" text-anchor="end">Cancelled account cleanup</text><g><title>v0.2.14: entrypoint trace + guardrails gate: 73%</title><rect class="bar s2" x="220" y="46" width="264.0" height="9" rx="2"/><text class="value" x="490.0" y="54">73%</text></g><g><title>+ rails-agents: delegate every change, review every change: 0%</title><rect class="bar s1" x="220" y="58" width="1.5" height="9" rx="2"/><text class="value" x="227.5" y="66">0%</text></g><text class="label" x="208" y="100" text-anchor="end">Card stalled quiet clock</text><g><title>v0.2.14: entrypoint trace + guardrails gate: 86%</title><rect class="bar s2" x="220" y="84" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="92">86%</text></g><g><title>+ rails-agents: delegate every change, review every change: 86%</title><rect class="bar s1" x="220" y="96" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="104">86%</text></g><text class="label" x="208" y="138" text-anchor="end">Comment reaction live echo</text><g><title>v0.2.14: entrypoint trace + guardrails gate: 94%</title><rect class="bar s2" x="220" y="122" width="340.0" height="9" rx="2"/><text class="value" x="565.996" y="130">94%</text></g><g><title>+ rails-agents: delegate every change, review every change: 83%</title><rect class="bar s1" x="220" y="134" width="300.0" height="9" rx="2"/><text class="value" x="525.988" y="142">83%</text></g><text class="label" x="208" y="176" text-anchor="end">Entropy sweep</text><g><title>v0.2.14: entrypoint trace + guardrails gate: 88%</title><rect class="bar s2" x="220" y="160" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="168">88%</text></g><g><title>+ rails-agents: delegate every change, review every change: 88%</title><rect class="bar s1" x="220" y="172" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="180">88%</text></g><text class="label" x="208" y="214" text-anchor="end">Local time human clock</text><g><title>v0.2.14: entrypoint trace + guardrails gate: 94%</title><rect class="bar s2" x="220" y="198" width="340.0" height="9" rx="2"/><text class="value" x="565.996" y="206">94%</text></g><g><title>+ rails-agents: delegate every change, review every change: 83%</title><rect class="bar s1" x="220" y="210" width="300.0" height="9" rx="2"/><text class="value" x="525.988" y="218">83%</text></g><text class="label" x="208" y="252" text-anchor="end">Webhook delivery trust and restart</text><g><title>v0.2.14: entrypoint trace + guardrails gate: 89%</title><rect class="bar s2" x="220" y="236" width="320.0" height="9" rx="2"/><text class="value" x="546.004" y="244">89%</text></g><g><title>+ rails-agents: delegate every change, review every change: 0%</title><rect class="bar s1" x="220" y="248" width="1.5" height="9" rx="2"/><text class="value" x="227.5" y="256">0%</text></g><text class="label" x="208" y="290" text-anchor="end">Dead path trap <tspan class="muted">· expert</tspan></text><g><title>v0.2.14: entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="274" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="282">100%</text></g><g><title>+ rails-agents: delegate every change, review every change: 100%</title><rect class="bar s1" x="220" y="286" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="294">100%</text></g><text class="label" x="208" y="328" text-anchor="end">Dead path trap <tspan class="muted">· hard</tspan></text><g><title>v0.2.14: entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="312" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="320">100%</text></g><g><title>+ rails-agents: delegate every change, review every change: 100%</title><rect class="bar s1" x="220" y="324" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="332">100%</text></g><text class="label" x="208" y="366" text-anchor="end">Phantom API trap <tspan class="muted">· easy</tspan></text><g><title>v0.2.14: entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="350" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="358">100%</text></g><g><title>+ rails-agents: delegate every change, review every change: 0%</title><rect class="bar s1" x="220" y="362" width="1.5" height="9" rx="2"/><text class="value" x="227.5" y="370">0%</text></g></svg></figure>

<details class="viz-table" markdown="1">
<summary>How sure are we?</summary>

A difference is real only when its whole 95% interval sits on one side of zero. Values here are over the tasks both setups ran.

| Measure | Setup | v0.2.14 gate | Setup | Difference | 95% interval | Tasks | Verdict |
|---|---|---|---|---|---|---|---|
| Acted on the code's truth | + Specialized agents | 100% | 67% | -33 pts | -100 pts to +0 pts | 3 | Too close to call |
| Hidden checks passed | + Specialized agents | 92% | 63% | -28 pts | -54 pts to -7 pts | 10 | Real regression |
| Said done, but wasn't | + Specialized agents | 33% | 40% | +7 pts | -20 pts to +33 pts | 10 | Too close to call |
| Cost per task | + Specialized agents | $1.11 | $2.99 | +$1.88 | +$0.88 to +$2.90 | 10 | Real regression |

</details>

<details class="viz-table" markdown="1">
<summary>Did the harness engage?</summary>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per task |
|---|---|---|---|
| v0.2.14 gate | 30 | 100% | 0.0 |
| + Specialized agents | 11 | 100% | 0.0 |

</details>

## Grounding traps (Writebook)

Each trap hands the agent a ticket, comment or doc that contradicts the code, the way real tickets do. Passing means the agent acted on what the code actually does. Rungs get harder: easy, hard, expert.

<div class="viz-cards">
<div class="viz-card"><div class="viz-card-title">Acted on the code&#39;s truth <span class="hint">traps passed</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">v0.2.13</span><span class="val">86%</span><span class="vs">vs 89% without</span><span class="delta">-3 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">97%</span><span class="vs">vs 82% without</span><span class="delta">+14 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Cost per task <span class="hint">list price, lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s1" aria-hidden="true"></span><span class="who">v0.2.13</span><span class="val">$0.12</span><span class="vs">vs $0.09 without</span><span class="delta">+$0.03</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">$0.15</span><span class="vs">vs $0.08 without</span><span class="delta">+$0.07</span><span class="viz-chip worse"><span aria-hidden="true">▼</span> Real regression</span></div></div>
</div>

<p class="viz-legend"><span class="viz-key"><span class="viz-swatch base" aria-hidden="true"></span>No harness</span><span class="viz-key"><span class="viz-swatch s1" aria-hidden="true"></span>v0.2.13</span><span class="viz-key"><span class="viz-swatch s2" aria-hidden="true"></span>v0.2.14: entrypoint trace + guardrails gate</span></p>

<figure class="viz-figure"><figcaption>Traps passed, by trap</figcaption><svg class="viz" viewBox="0 0 670 508" role="img" aria-label="Traps passed, by trap"><text class="label" x="208" y="30" text-anchor="end">Dead path <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="8" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="16">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="20" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="28">6/6 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 6/6 passed</title><rect class="bar s2" x="220" y="32" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="40">6/6 passed</text></g><text class="label" x="208" y="80" text-anchor="end">Dead path <tspan class="muted">· hard</tspan></text><g><title>No harness: 2/9 passed</title><rect class="bar base" x="220" y="58" width="80.0" height="9" rx="2"/><text class="value" x="306.0" y="66">2/9 passed</text></g><g><title>v0.2.13: 0/6 passed</title><rect class="bar s1" x="220" y="70" width="1.5" height="9" rx="2"/><text class="value" x="227.5" y="78">0/6 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 6/6 passed</title><rect class="bar s2" x="220" y="82" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="90">6/6 passed</text></g><text class="label" x="208" y="130" text-anchor="end">Dead path <tspan class="muted">· expert</tspan></text><g><title>No harness: 0/3 passed</title><rect class="bar base" x="220" y="108" width="1.5" height="9" rx="2"/><text class="value" x="227.5" y="116">0/3 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="132" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="140">3/3 passed</text></g><text class="label" x="208" y="180" text-anchor="end">Phantom API <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="158" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="166">3/3 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 2/3 passed</title><rect class="bar s2" x="220" y="182" width="240.0" height="9" rx="2"/><text class="value" x="466.0" y="190">2/3 passed</text></g><text class="label" x="208" y="230" text-anchor="end">Premature done <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="208" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="216">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="220" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="228">6/6 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="232" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="240">3/3 passed</text></g><text class="label" x="208" y="280" text-anchor="end">Premature done <tspan class="muted">· hard</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="258" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="266">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="270" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="278">6/6 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="282" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="290">3/3 passed</text></g><text class="label" x="208" y="330" text-anchor="end">Spec contradiction <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="308" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="316">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="320" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="328">6/6 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="332" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="340">3/3 passed</text></g><text class="label" x="208" y="380" text-anchor="end">Spec contradiction <tspan class="muted">· hard</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="358" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="366">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="370" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="378">6/6 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="382" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="390">3/3 passed</text></g><text class="label" x="208" y="430" text-anchor="end">Spec contradiction <tspan class="muted">· expert</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="408" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="416">3/3 passed</text></g><g><title>v0.2.13: 6/6 passed</title><rect class="bar s1" x="220" y="420" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="428">6/6 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="432" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="440">3/3 passed</text></g><text class="label" x="208" y="480" text-anchor="end">Test tamper <tspan class="muted">· easy</tspan></text><g><title>No harness: 3/3 passed</title><rect class="bar base" x="220" y="458" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="466">3/3 passed</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 3/3 passed</title><rect class="bar s2" x="220" y="482" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="490">3/3 passed</text></g></svg></figure>

<details class="viz-table" markdown="1">
<summary>How sure are we?</summary>

A difference is real only when its whole 95% interval sits on one side of zero. Values here are over the tasks both setups ran.

| Measure | Setup | No harness | Setup | Difference | 95% interval | Tasks | Verdict |
|---|---|---|---|---|---|---|---|
| Acted on the code's truth | v0.2.13 | 89% | 86% | -3 pts | -11 pts to +0 pts | 7 | Too close to call |
| Acted on the code's truth | v0.2.14 gate | 82% | 97% | +14 pts | -10 pts to +40 pts | 10 | Too close to call |
| Cost per task | v0.2.13 | $0.09 | $0.12 | +$0.03 | +$0.01 to +$0.05 | 7 | Real regression |
| Cost per task | v0.2.14 gate | $0.08 | $0.15 | +$0.07 | +$0.05 to +$0.09 | 10 | Real regression |

</details>

<details class="viz-table" markdown="1">
<summary>Did the harness engage?</summary>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per task |
|---|---|---|---|
| No harness | 36 | – | 0.0 |
| v0.2.13 | 42 | 74% | 0.0 |
| v0.2.14 gate | 36 | 100% | 0.0 |

</details>

## Feature tickets (Fizzy)

Seven real feature tasks from rails/ai-evals on Fizzy, a codebase about six times Writebook's size. Scored on the primary scorecard against no harness.

!!! note "Exploratory"
    These runs predate the scorecard's registration, so their differences are exploratory, not confirmatory.


<div class="viz-cards">
<div class="viz-card"><div class="viz-card-title">Hidden checks passed <span class="hint">of what the task needed</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">81%</span><span class="vs">vs 82% without</span><span class="delta">+0 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Said done, but wasn&#39;t <span class="hint">lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">64%</span><span class="vs">vs 43% without</span><span class="delta">+21 pts</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
<div class="viz-card"><div class="viz-card-title">Cost per task <span class="hint">list price, lower is better</span></div>
<div class="viz-card-row"><span class="viz-swatch s2" aria-hidden="true"></span><span class="who">v0.2.14 gate</span><span class="val">$0.39</span><span class="vs">vs $0.31 without</span><span class="delta">+$0.07</span><span class="viz-chip unsure"><span aria-hidden="true">≈</span> Too close to call</span></div></div>
</div>

<p class="viz-legend"><span class="viz-key"><span class="viz-swatch base" aria-hidden="true"></span>No harness</span><span class="viz-key"><span class="viz-swatch s2" aria-hidden="true"></span>v0.2.14: entrypoint trace + guardrails gate</span></p>

<figure class="viz-figure"><figcaption>Hidden checks passed, by task</figcaption><svg class="viz" viewBox="0 0 670 274" role="img" aria-label="Hidden checks passed, by task"><text class="label" x="208" y="24" text-anchor="end">Activity feed api</text><g><title>No harness: 93%</title><rect class="bar base" x="220" y="8" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="16">93%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 93%</title><rect class="bar s2" x="220" y="20" width="336.0" height="9" rx="2"/><text class="value" x="561.988" y="28">93%</text></g><text class="label" x="208" y="62" text-anchor="end">Cancelled account cleanup</text><g><title>No harness: 60%</title><rect class="bar base" x="220" y="46" width="216.0" height="9" rx="2"/><text class="value" x="442.0" y="54">60%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 40%</title><rect class="bar s2" x="220" y="58" width="144.0" height="9" rx="2"/><text class="value" x="370.0" y="66">40%</text></g><text class="label" x="208" y="100" text-anchor="end">Card stalled quiet clock</text><g><title>No harness: 86%</title><rect class="bar base" x="220" y="84" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="92">86%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 86%</title><rect class="bar s2" x="220" y="96" width="308.6" height="9" rx="2"/><text class="value" x="534.556" y="104">86%</text></g><text class="label" x="208" y="138" text-anchor="end">Comment reaction live echo</text><g><title>No harness: 83%</title><rect class="bar base" x="220" y="122" width="300.0" height="9" rx="2"/><text class="value" x="526.0060000000001" y="130">83%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 83%</title><rect class="bar s2" x="220" y="134" width="300.0" height="9" rx="2"/><text class="value" x="525.988" y="142">83%</text></g><text class="label" x="208" y="176" text-anchor="end">Entropy sweep</text><g><title>No harness: 88%</title><rect class="bar base" x="220" y="160" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="168">88%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 88%</title><rect class="bar s2" x="220" y="172" width="315.0" height="9" rx="2"/><text class="value" x="541.0" y="180">88%</text></g><text class="label" x="208" y="214" text-anchor="end">Local time human clock</text><g><title>No harness: 83%</title><rect class="bar base" x="220" y="198" width="300.0" height="9" rx="2"/><text class="value" x="525.988" y="206">83%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 100%</title><rect class="bar s2" x="220" y="210" width="360.0" height="9" rx="2"/><text class="value" x="586.0" y="218">100%</text></g><text class="label" x="208" y="252" text-anchor="end">Webhook delivery trust and restart</text><g><title>No harness: 78%</title><rect class="bar base" x="220" y="236" width="280.0" height="9" rx="2"/><text class="value" x="506.00800000000004" y="244">78%</text></g><g><title>v0.2.14: entrypoint trace + guardrails gate: 78%</title><rect class="bar s2" x="220" y="248" width="280.0" height="9" rx="2"/><text class="value" x="506.00800000000004" y="256">78%</text></g></svg></figure>

<details class="viz-table" markdown="1">
<summary>How sure are we?</summary>

A difference is real only when its whole 95% interval sits on one side of zero. Values here are over the tasks both setups ran.

| Measure | Setup | No harness | Setup | Difference | 95% interval | Tasks | Verdict |
|---|---|---|---|---|---|---|---|
| Hidden checks passed | v0.2.14 gate | 82% | 81% | +0 pts | -11 pts to +7 pts | 7 | Too close to call |
| Said done, but wasn't | v0.2.14 gate | 43% | 64% | +21 pts | -14 pts to +57 pts | 7 | Too close to call |
| Cost per task | v0.2.14 gate | $0.31 | $0.39 | +$0.07 | -$0.01 to +$0.15 | 7 | Too close to call |

</details>

<details class="viz-table" markdown="1">
<summary>Did the harness engage?</summary>

| Setup | Trials | Guardrails loaded before the first edit | MCP and bookshelf lookups per task |
|---|---|---|---|
| No harness | 14 | – | 0.0 |
| v0.2.14 gate | 14 | 100% | 0.0 |

</details>

## Caveats

- Small samples: most comparisons have 2 to 6 runs per task, so many gaps are still "too close to call".
- On the phantom-API trap, the entrypoint + gate setup's one miss stopped to ask: it proved the ticket's Rails option doesn't exist and asked which fix to make, rather than guessing. Headless, nobody answers, so it scores as a miss.
- "Said done, but wasn't" didn't move. On the stalled-card task the agents grounded "activity" in the column the code names for it, said in their report that ticking off a step doesn't count, and shipped; the hidden checks count steps. A person reading that report would catch it; a headless run can't.
- The evidence check and term grounding cost about 6¢ a task more than the gate alone, and in this run made no difference anyone could measure on top of it.
- Opus 5.5 passed every trap without the harness, so on Opus the harness had nothing to fix there and only added cost. The traps are tuned to tempt Sonnet; harder ones are needed to see whether Opus slips.
- Haiku 5.5 sometimes walked through the gate: in 4 of 29 runs it retried the refused edit instead of loading the guardrails skill first, and loaded it a few steps later. Sonnet and Opus complied every time. v0.2.15 keeps refusing until the skill loads (at most three times): on the same Haiku tasks, no run edited before loading it (0 of 29), with no measurable change in the four scores or cost.
- In these runs the v0.2.14 gate refused the first edit even when the guardrails skill was already loaded. It looked for the skill in the session transcript, and headless bench runs don't save one; interactive sessions do. So the harness arms above measure "refuse the first edit once", which costs an agent that loaded the skill first one wasted step.
- The traps are written to tempt grounding failures. They show *where* the harness changes behavior, not how often that happens in everyday work.
- Runs where the setup itself failed (the harness didn't load, the sandbox misbehaved) are excluded, never scored as agent failures.
