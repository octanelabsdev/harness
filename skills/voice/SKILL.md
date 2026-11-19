---
name: voice
description: Draft messages the user will send under their own name (texts, chat posts, email, social, tracker comments, pitches, status reports) in their voice, from a voice profile — and set that profile up with them when none exists. Load before drafting any such message. Not for code, commits, PRs, chat with the user, sub-agent prompts, or notes. Stack-agnostic.
---

# Voice

Default model voice is not the user's voice: hedged openers, generic enthusiasm, marketing phrasing,
throat-clearing. When the user will paste your text under their name, that costs them credibility.

## Find the profile
The profile path is the `Voice profile: <path>` line in the user's global CLAUDE.md. Read it once per
session, before the first draft. No such line, or the file is missing? Run **Setup** before drafting —
never fall back to default voice.

## Draft
- Follow the profile: its openers, structure, what to include, and its banned phrases. It outranks your
  default style.
- Every draft follows **ASD-STE100 Simplified Technical English (STE)**: one idea per sentence; 20 words
  or fewer per instruction or question, 25 per description; 6 sentences or fewer per paragraph; active
  voice and simple tenses; direct commands and direct questions, one question per bullet; one word for
  one meaning and the same name for a thing every time; no idioms, slang, or phrasal verbs where a single
  verb exists; keep the articles. STE governs sentence structure and word choice; the profile governs
  tone and content. Only an explicit `Sentence standard: none` line in the profile turns STE off.
- Before showing the draft, check it against the STE list line by line and fix every miss.
- The profile is silent on this case? Match its closest documented pattern and tell the user the gap,
  so they can extend it.

## Setup (no profile yet)
Tell the user there is no voice profile and offer to build one now. Then:

1. **Samples.** Ask for 3–5 messages they actually sent, covering different audiences (a peer, a
   client or customer, a manager or status update). Pasted text is fine.
2. **Questions** (one per bullet, via AskUserQuestion where available):
   - How do you open a message to a peer? To a client?
   - Headline first, or context first?
   - Words or phrases you never use?
   - How do you state a commitment or a date — with a caveat, or flat?
   - Drafts follow Simplified Technical English by default. Do you need to turn that off?
3. **Write the profile** from the samples and answers only — nothing invented. Sections: audiences and
   their openers, structure, phrases they use, banned phrases, how they commit, and
   2–3 short example messages taken from their samples.
4. **Show it, get approval, then save** where they choose (suggest their notes folder). Add
   `Voice profile: <path>` to their global CLAUDE.md, or give them the line to add.
5. Draft the original message with the new profile.

## Do not
Do not draft in default voice because the profile is missing. Do not invent traits the samples do not
show. Do not apply this to text that is not going out under the user's name.
