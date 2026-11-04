# Headroom

A macOS menu bar app and set of desktop widgets that show how much of your **Claude Code** and **Codex** quota is left, whether you're burning it faster than an even pace, and which one to use right now.

Monochrome, dot-matrix, with tinted-glass or fully clear backgrounds.

- **Status:** planning. See [docs/PLAN.md](docs/PLAN.md).
- **Design:** [design/](design) holds the Claude Design canvas sources for the mockups: the desktop, widget sizes, widget states and menu bar states.

## How it reads your quotas

- **Codex:** reads the `rate_limits` entries Codex CLI writes to `~/.codex/sessions`. This happens locally, and nothing is uploaded.
- **Claude Code:** the source is still being decided (see the plan, Spike S1).

## Fonts

[Doto](https://fonts.google.com/specimen/Doto) and [Fragment Mono](https://fonts.google.com/specimen/Fragment+Mono), both under the SIL Open Font License.
