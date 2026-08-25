# Provider asset resourcing checklist

Ammo displays a small glyph for each AI provider it integrates with
(`Apps/iOS/Shared/ProviderAssets.xcassets`). None of those glyphs may be
extracted from a competitor's or partner's shipped app icon — see
[`docs/launch-review/app-review.md`](launch-review/app-review.md) (§L1/§L4)
for why the previous `Apps/iOS/Assets/Official/*.png` +
`Scripts/extract-provider-glyphs.py` pipeline was removed (MIK-170).

Before adding, replacing, or re-licensing a provider glyph, the operator
must work through this checklist per provider. **All URLs below are
operator-verify** — this document was written without live web access and
the URLs have not been confirmed to resolve or to still be current.

## OpenAI / Codex

- Official brand resources: `https://openai.com/brand/` — operator-verify
- Usage-terms question: does OpenAI's brand policy permit third-party apps
  to display the Codex/OpenAI mark to indicate integration with the OpenAI
  API, and under what conditions (unmodified mark, no implied endorsement,
  attribution, etc.)?
- Current shipped glyph provenance: `logo-codex.imageset/codex.png` and
  `logo-codex-menu.imageset/codex-menu.png` — previously extracted from a
  vendored Codex app icon (`Apps/iOS/Assets/Official/codex-app-icon.png`,
  now deleted). **Needs re-sourcing** from an OpenAI-provided brand asset
  before these can be treated as compliant.
- `logo-openai-monochrome.imageset/openai.svg` — vector, template-rendering
  intent; provenance not documented at extraction time. Confirm source and
  license before next release.

## Anthropic / Claude

- Official brand resources: `https://www.anthropic.com/brand` — operator-verify
- Usage-terms question: does Anthropic's brand/trademark policy permit
  displaying the Claude Code mark in a third-party client app, and does it
  require a specific mark variant (e.g. the "color" lockup already in use)?
- Current shipped glyph provenance: `logo-claude.imageset/claudecode-color.svg`
  — vector asset, not derived from an app icon crop. Provenance (which
  Anthropic asset it was sourced from, and under what license) is not
  documented in-repo; confirm and record it.

## Cursor

- Official brand resources: `https://cursor.com/brand` — operator-verify
  (URL unconfirmed; Cursor's brand/press page may live at a different path)
- Usage-terms question: does Cursor's brand policy permit third-party apps
  to display the Cursor mark to indicate integration with Cursor's usage
  API, and does it restrict modification (color, cropping, monochrome
  derivation)?
- Current shipped glyph provenance: `logo-cursor.imageset/cursor.png`,
  `logo-cursor-menu.imageset/cursor-menu.png`, and
  `logo-cursor-monochrome.imageset/cursor-monochrome.png` — previously
  extracted from a vendored Cursor app icon
  (`Apps/iOS/Assets/Official/cursor-app-icon.png`, now deleted). **Needs
  re-sourcing** from a Cursor-provided brand asset before these can be
  treated as compliant.

## OpenRouter

- Official brand resources: `https://openrouter.ai/brand` — operator-verify
  (URL unconfirmed; OpenRouter may not publish a dedicated brand page)
- Usage-terms question: does OpenRouter permit third-party apps to display
  its mark to indicate integration with the OpenRouter API, and are there
  restrictions on color/format?
- Current shipped glyph provenance: `logo-openrouter.imageset/openrouter-color.svg`
  — vector asset, not derived from an app icon crop. Provenance not
  documented in-repo; confirm and record it.

## Follow-up

`Apps/iOS/Assets/Official/*` was removed from HEAD but **remains in git
history** on this public repository (PLAN.md decision D2). Rewriting
history (e.g. `git filter-repo` + force-push) is a separate, explicit
operator decision — not taken as part of MIK-170.
