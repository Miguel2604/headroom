# Headroom: implementation plan

Headroom is a macOS menu bar app with desktop widgets that answer one question: **which coding plan should I use right now?** It reads the Claude Code and Codex quota limits, shows how much is left in each window, compares that with an even pace, and gives a one-line verdict ("USE CODEX until 12:12").

The design (monochrome, dot-matrix, translucent or fully clear) lives in [`design/`](../design) as Claude Design canvas sources. This plan turns it into a native app.

## Scope of v1

- Menu bar item: a two-row dot glyph (Claude on top, Codex below) plus optional text (`38%`, `OUT ~11:13`, `BACK 12:12`). Clicking it opens a panel with the verdict, four meters and the actions Refresh, Open Claude usage, Open Codex usage, Settings and Quit.
- Desktop widgets in four layouts:
  - Small: one plan's 5-hour limit.
  - Medium, verdict: the verdict plus both 5-hour meters.
  - Medium, all limits: all four meters.
  - Large: the verdict plus both plans and both windows.
- **Background switch** with two options:
  - **Tinted glass**: a dark or light translucent fill with blur.
  - **Fully clear**: no fill at all, with a soft shadow behind the content for legibility.

  The switch can be set globally in Settings and per widget in the widget's Edit menu.
- Dark and light follow the system appearance.
- Widget states:
  - On pace
  - Running out
  - Limit reached
  - Unused quota about to reset
  - Couldn't update (with Retry)
  - Not set up

Not in v1: other providers (Cursor, Gemini), history charts, notifications. Notifications are the obvious v1.1, e.g. "Claude runs out in 30 min".

## Architecture

```
Headroom.app (menu bar app, LSUIElement, not sandboxed, Developer ID)
├─ HeadroomCore (local Swift package)
│   ├─ Model: Plan, LimitWindow, Snapshot, Verdict
│   ├─ Pace: evenLeft, projectedRunout, verdict rules
│   └─ Providers: CodexProvider, ClaudeProvider
├─ MenuBarExtra (.window style) + Settings scene
├─ Optional DesktopPanel (fallback for true transparency, see Spike S2)
└─ writes Snapshot JSON to the App Group container
HeadroomWidget.appex (WidgetKit, sandboxed)
└─ reads the Snapshot from the App Group; never touches ~/.codex or the Keychain
```

- Swift 6, SwiftUI, minimum macOS 14 (the first version with desktop widgets).
- The app does all the reading because the widget extension is sandboxed. It writes `snapshot.json` to the shared App Group container and calls `WidgetCenter.shared.reloadAllTimelines()` whenever the data changes.
- The widget timeline takes one snapshot and generates entries every 5 minutes for the next hour, because even pace and "runs out at" change with time even when usage doesn't. Entries stop at the next reset.
- Refresh:
  - A 60-second timer in the app.
  - An FSEvents watch on `~/.codex/sessions`, so Codex updates show up instantly.
  - Manual refresh with ⌘R.

## Data sources

### Codex: verified

Codex CLI writes `rate_limits` into its session logs at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. This was checked on this machine on 2026-11-04:

```json
"rate_limits": {
  "primary":   { "used_percent": 24.0, "window_minutes": 300,   "resets_at": 1793771977 },
  "secondary": { "used_percent": 73.0, "window_minutes": 10080, "resets_at": 1793812838 }
}
```

- `primary` is the 5-hour window and `secondary` is the weekly window. `resets_at` is a Unix timestamp.
- The provider reads the newest file in reverse, line by line, and stops at the first `rate_limits`.
- Caveats:
  - This is an undocumented format, so the parser must fail soft.
  - The data is only as fresh as the last Codex run, so always show "as of HH:MM".
  - Once `resets_at` has passed, treat that window as 100% left until new data arrives.

### Claude Code: Spike S1 decides

There is no documented local source of Claude Code's plan limits. Try these in order and keep the first that works:

1. **The usage endpoint behind Claude Code's `/usage`.** It reports 5-hour and weekly use, authenticated with the OAuth token Claude Code stores in the Keychain (item `Claude Code-credentials`).
   - It is unofficial and could change without notice.
   - Reading another app's Keychain item makes macOS ask the user for permission.
   - Never log or copy the token.
2. **The Claude Code status line hook.** Check whether the JSON passed to a `statusLine` command includes rate-limit data. If it does, a tiny script can write it to `~/Library/Application Support/Headroom/claude.json`.
3. **An estimate from the local logs** in `~/.claude/projects/**/*.jsonl` (token counts, like ccusage). There is no official limit to divide by, so this only yields an estimate, and the UI must label it as one.

The spike's output is a short note in `docs/` covering what works, how fresh the data is, and what breaks it.

## Pace and verdict (HeadroomCore, unit-tested)

For each window, with `window`, `resetsAt`, `usedPercent` and `now`:

- `elapsed = clamp(1 - (resetsAt - now) / window, 0, 1)`
- `left = 100 - usedPercent`
- `evenLeft = 100 × (1 - elapsed)`: where the hollow pace dot goes.
- `runningOut = left < evenLeft - 5 && projectedRunout < resetsAt`, where `projectedRunout = now + left / (usedPercent / elapsedTime)`.
- `limitReached = left <= 0`; show "BACK <resetsAt>".
- `expiringUnused = elapsed > 0.9 && left > 25`; show "EXPIRES IN <time>".

Verdict rules, first match wins:

1. One plan has hit its limit or is running out and the other isn't: "USE <other> UNTIL <first plan's 5h reset>".
2. Both are out: "BOTH OUT · BACK <earliest reset>".
3. A weekly window is expiring unused: "USE <that plan> · <n>% EXPIRES <time>".
4. Otherwise: "ON PACE".

Tests use Swift Testing, with fixed `now` values and fixtures copied from real Codex log lines (secrets stripped).

## Visual spec

Every token below comes from the mockups.

| Token | Dark | Light |
|---|---|---|
| Ink | `#FFFFFF` | `#000000` |
| Secondary text | ink at 68% opacity | ink at 62% opacity |
| Dot, off | ink at 22% opacity | ink at 16% opacity |
| Tinted background | `rgba(12,12,12,0.46)` + blur 28 | `rgba(255,255,255,0.50)` + blur 28 |
| Tinted edge | inner 1px, white at 10% | inner 1px, white at 60% |
| Clear background | none, `shadow(radius 8, black 55%)` | none, `shadow(radius 8, white 70%)` |
| Warning | inverted pill: ink fill, background-coloured text | same |

- Type:
  - **Doto** (900) for numbers and the verdict.
  - **Fragment Mono** (400) in uppercase with 0.06em tracking for labels.
  - Both are under the SIL Open Font License. Bundle the static font files in the app and in the widget extension, and register them with `CTFontManagerRegisterFontsForURL`, or `ATSApplicationFontsPath` in the extension.
- Meters: lit dots show what's left, off dots show what's used, and one hollow dot marks even pace. Dot counts per meter: 14 on small, 12 or 16 on medium, 16 in the menu, 24 on large.
- Sizes: small 170×170, medium 364×170, large 364×382, corner radius 24.
- Menu bar glyph: a template `NSImage` of 2 rows × 5 dots, rendered at runtime so macOS tints it. Never use colour in the menu bar.
- Every meter gets an accessibility label, e.g. "Claude Code 5-hour limit: 38% left, runs out around 11:13".

## Backgrounds: tinted and fully clear

- Setting: `BackgroundStyle { tinted, clear }` in App Group `UserDefaults`. Each widget can override it through a `WidgetConfigurationIntent` parameter, offering Default, Tinted or Clear.
- Tinted: `.containerBackground(for: .widget) { ZStack { Material.ultraThin; Color.black.opacity(0.46) } }`.
- Clear: `.containerBackground(for: .widget) { Color.clear }` plus the shadow on the content.
- **Spike S2.** macOS may still draw its own backing behind desktop widgets, or desaturate them when the desktop is not focused. Test this on the current macOS:
  - If clear isn't truly transparent, add **Desktop Panel** mode. The app renders the same SwiftUI views in a borderless, transparent, click-through `NSPanel` at desktop-icon window level, on every Space and draggable when unlocked.
  - That mode is guaranteed to be transparent, and the WidgetKit widgets stay available for the tinted look.

## Phases

Each phase is built test-first and committed and pushed as its own slice.

1. **Spikes S1 and S2.** Settle the Claude data source and whether clear widgets are truly transparent. Write the findings in `docs/`.
2. **Core.** `HeadroomCore` package covering the model, pace math, verdict and Codex parser, with tests.
3. **Menu bar app.** `MenuBarExtra` with the dot glyph and the panel UI, running on live Codex data with a placeholder for Claude.
4. **Claude provider.** Implement whatever S1 chose, including the empty and error states.
5. **Widget extension.** Small, both mediums and large; App Group snapshot; timeline with pace entries.
6. **Backgrounds.** The tinted/clear setting and per-widget intent, plus Desktop Panel mode if S2 requires it.
7. **States and polish.** Stale, not set up, limit reached, expiring, light/dark, fonts, accessibility, launch at login (`SMAppService`).
8. **Release.** Developer ID signing, notarisation, a DMG via GitHub Releases, and a README with screenshots.

Then one review over the whole branch.

## Open questions

- **Apple Developer account:** App Groups and notarised distribution need a paid team ID. Without one, the widget can only be tested locally.
- **Plan names:** "Max" and "Pro" in the mockups are guesses. Show the plan name only if the data source provides it.
- **Claude data:** if S1 lands on option 3, the Claude numbers are estimates, and the UI has to say so.
