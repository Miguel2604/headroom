# Spikes

## S1: Claude Code data source

Checked on 2026-11-04 with Claude Code 2.1.317 on macOS 27.0.

**Decision: option 1, the usage endpoint.** It works, it doesn't need Claude Code to be running, and it returns the same numbers as `/usage`.

### What works

- Claude Code keeps its OAuth credentials in the login Keychain as a generic password, service `Claude Code-credentials`. The value is JSON: `claudeAiOauth.accessToken`, `expiresAt` (Unix ms), `subscriptionType` (`max`, `pro`) and `rateLimitTier` (`default_claude_max_5x`).
- `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <accessToken>` and `anthropic-beta: oauth-2025-04-20` returns:

  ```json
  {
    "five_hour": { "utilization": 29.0, "resets_at": "2026-11-04T04:40:00.336930+00:00" },
    "seven_day": { "utilization": 22.0, "resets_at": "2026-11-08T16:00:00.336950+00:00" },
    "seven_day_opus": null,
    "...": "about 30 other, mostly null, fields"
  }
  ```

  `utilization` is the percentage used. `resets_at` is ISO 8601, with or without fractional seconds.
- Headroom reads the Keychain item by running `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`. Claude Code creates and updates the item through that same tool, so the item's access list already trusts it and macOS doesn't prompt. Reading it with `SecItemCopyMatching` instead would prompt, and the prompt would come back every time Claude Code rewrites the item on a token refresh.
- The plan name comes from `subscriptionType`.

### Freshness

Live. Each call returns the current numbers. Headroom calls it at most every 5 minutes, plus on manual refresh, so it doesn't get rate-limited on an endpoint it doesn't own.

### What breaks it

- **The endpoint is unofficial.** It can change or disappear without notice. The parser fails soft: a missing or renamed field shows "Couldn't update" with the last good numbers, never a crash.
- **An expired access token.** Claude Code refreshes it when it runs. Headroom never refreshes it, because that would rotate the refresh token and could sign Claude Code out. When `expiresAt` has passed or the endpoint returns 401, Headroom says "Open Claude Code to refresh sign-in".
- **API-key users.** Without `claudeAiOauth` there are no plan limits, and Headroom shows "Not set up".
- The token is never logged, written to disk or sent anywhere but `api.anthropic.com`.

### Not chosen

- **Status line hook (option 2).** It works too: in 2.1.317 the JSON passed to a `statusLine` command includes `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` and `resets_at` (Unix seconds). But it only updates while a Claude Code session is open and redrawing, and installing it means editing `~/.claude/settings.json`, which may already have a status line. It is the fallback if the endpoint goes away.
- **Local log estimate (option 3).** Not needed.

## S2: are clear widgets truly transparent?

Checked on 2026-11-04 on macOS 27.0. **Only partly answered.**

### What's known

- System Settings › Desktop & Dock has **"Dim widgets on desktop"**, set to **Automatically** by default. So macOS does change desktop widgets when the desktop isn't focused, which is one of the two things this spike asked about.
- The Fully clear widget uses `.containerBackground(for: .widget) { Color.clear }` plus the content shadow, and the per-widget Background option (Default, Tinted glass, Fully clear) is wired up.
- The Desktop Panel renders as intended: a borderless, transparent `NSPanel` at the desktop-icon window level (`-2147483603`) on every Space, with live data, in both backgrounds.

### What isn't

Whether macOS draws its own plate or blur behind a Fully clear widget, in focused or dimmed mode, has not been observed. Placing widgets needs the desktop's Edit Widgets gallery, and automated computer use couldn't drive it on this Mac: Finder's desktop and the menu bar clock both returned `noWindowsAvailable`.

**To finish it by hand:** add a Large "Headroom" widget, set its Background to Fully clear, and look at it over a busy wallpaper with the desktop focused, then with another app in front.

### Decision

Desktop Panel mode ships, opt-in, in Settings › Desktop panel. macOS dimming widgets is enough reason by itself, and the panel is the one mode that is guaranteed transparent and never dimmed. WidgetKit widgets stay available in both backgrounds. If the manual check shows clear widgets are truly transparent, the panel is still useful for the undimmed look.
