# A small fix

For changes too small to need a story: a typo, a copy change, a config value, an obvious one-line bug.
If you'd have to explain the change in more than a sentence, it's a [story](story.md).

## Example: a typo in Trailhead's booking confirmation

The confirmation email says "Your reservaton is confirmed."

**1. Declare it.** Write one line saying what and why:

```sh
printf '%s\n' 'Fix "reservaton" typo in the booking confirmation email' > .claude/.small-fix
```

The pipeline gate lets edits through while this file exists, and it repeats the line on every edit so
the bypass stays visible. `touch .claude/.small-fix` also works; the line just makes the reason show.

**2. Ask.**

> **You:** The booking confirmation email says "reservaton". Fix it.

**3. Let the Stop gate run.** The tests still run when the turn ends. A one-line change can break a
test like any other: a mailer test that asserts the exact subject line, for instance. Red keeps the
turn going until it's fixed.

**4. Commit, then remove the marker.**

```sh
rm .claude/.small-fix
```

Leaving it in place lets the next feature skip its story without anyone noticing.

## When it isn't a small fix

Stop and switch to a story when:

- the fix needs a decision ("should cancelled bookings get this email too?");
- it touches more than one behaviour;
- you find yourself writing a new test for new behaviour, not adjusting one.
