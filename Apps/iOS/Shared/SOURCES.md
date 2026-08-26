# Provider glyph sources and permitted-use evidence

Evidence file for every image in
[`ProviderAssets.xcassets`](ProviderAssets.xcassets). This is the document to
point App Review at if provider mark provenance is questioned
(`docs/launch-review/submission-package.md` §4 "Content Rights", §5 gates 1–2).

**How Ammo uses these marks.** Each glyph is displayed at 20–28 pt next to the
provider's plain-text name, identifying which of the *user's own* provider
accounts a row, section header, menu item, or widget line belongs to. No mark
appears in the app name, app icon, subtitle, keywords, or in Ammo's own
branding. Nothing on any surface asserts sponsorship, endorsement, or
affiliation. Ammo is not affiliated with any of these companies.

All URLs below were retrieved **2026-08-26**. Per-provider clause quotations,
verdicts, and the operator work still outstanding live in
[`docs/asset-resourcing.md`](../../../docs/asset-resourcing.md); this file is
the per-file index.

## Index

| Asset file | Source | Permission basis | Retrieved | Verdict |
|---|---|---|---|---|
| `logo-cursor.imageset/cursor.png` | `cursor.com/brand` → `cursor-brand-assets.zip` → `General Logos/Cube/PNG/CUBE_25D.png` | Cursor brand guidelines page (public, unauthenticated asset download) | 2026-08-26 | permitted-with-conditions |
| `logo-cursor-menu.imageset/cursor-menu.png` | same as above | same as above | 2026-08-26 | permitted-with-conditions |
| `logo-cursor-monochrome.imageset/cursor-monochrome.png` | `cursor.com/brand` → `cursor-brand-assets.zip` → `General Logos/Cube/PNG/CUBE_2D_DARK.png` | same as above | 2026-08-26 | permitted-with-conditions |
| `logo-openrouter.imageset/openrouter-color.svg` | `openrouter.ai/brand/logos/transparent/glyph/svg/glyph-volt.svg` | `openrouter.ai/brand` ("Every configuration of the OpenRouter mark, ready to use.") | 2026-08-26 | permitted-with-conditions |
| `logo-claude.imageset/claudecode-color.svg` | **Not first-party.** Byte-identical path data to `@lobehub/icons-static-svg` `icons/claudecode-color.svg` | None recorded — Anthropic requires prior written permission | 2026-08-26 | **not-established** |
| `logo-codex.imageset/codex.png` | **Not first-party.** Pixel-extracted from the shipped Codex app icon (pipeline removed in MIK-170) | None recorded — OpenAI publishes no Codex brand asset | 2026-08-26 | **not-established** |
| `logo-codex-menu.imageset/codex-menu.png` | same as above | same as above | 2026-08-26 | **not-established** |
| `logo-openai-monochrome.imageset/openai.svg` | **Not first-party.** Widely mirrored 41×41 OpenAI "Blossom" SVG; original download not identified | None recorded — official download is behind `brand.openai.com` login | 2026-08-26 | **not-established** |

---

## Cursor (Anysphere, Inc.)

- **Brand page:** <https://cursor.com/brand> — retrieved 2026-08-26, HTTP 200.
  The URL guessed in the previous revision of `docs/asset-resourcing.md` was
  correct.
- **Asset bundle:** <https://ptht05hbb1ssoooe.public.blob.vercel-storage.com/assets/brand/cursor-brand-assets.zip>
  (the page's "Download brand assets" link). Public, no login, no click-through
  licence, no LICENSE/README inside the archive.
  `sha256(cursor-brand-assets.zip) = 97488a7751914e60f9ff532bc33810cdeaebdddc017548abe6ca2bc29bbc3928`
- **Clause relied on** — the whole of the brand page's substantive text:
  > "Cursor brand guidelines — Resources to represent Cursor consistently and
  > accurately."
  > "Logos are available in 2D (default) and 2.5D (for larger applications), in
  > horizontal lockup (preferred), vertical lockup, or separately as cube or
  > wordmark."
  > "Name — Refer to us as Cursor. Not Cursor AI or Cursor Code."
- **Contract hook** (Cursor Marketplace Publisher Terms,
  <https://cursor.com/marketplace-publisher-terms>, retrieved 2026-08-26):
  > "\"Brand Guidelines\" means Anysphere's brand usage guidelines available at
  > cursor.com/brand, as may be updated from time to time." (§1.2)
  > "Publisher's use of Anysphere's name, trademarks, or logos in connection with
  > the Plugin must comply with the Brand Guidelines." (§4.6)
  > "Anysphere may revoke your right to use our trademarks at any time." (§4.6)
- **Files installed:**
  - `logo-cursor.imageset/cursor.png` — `General Logos/Cube/PNG/CUBE_25D.png`
    (official, 1401×1600, `sha256 292696a0…7202b`), Lanczos-scaled to 392×448
    and centred on a 512×512 transparent canvas. Aspect ratio preserved
    (1401/1600 = 0.8756; 392/448 = 0.8750, ≤1 px difference). No recolour.
  - `logo-cursor-menu.imageset/cursor-menu.png` — same source, scaled to 282×322
    centred on 512×512. The smaller glyph box is the optical inset the native
    menu variant has always carried (see `ProviderLogo.swift`, `Role.menu`).
  - `logo-cursor-monochrome.imageset/cursor-monochrome.png` — `General
    Logos/Cube/PNG/CUBE_2D_DARK.png` (official single-colour cube, 1401×1597,
    `sha256 944f2b64…272b5`), scaled to 561×640 centred on 640×640. Cursor
    publishes single-colour 2D and WHITE variants itself, so a single-colour
    cube is a shipped Cursor variant rather than a derivation.
- **Conditions Ammo must keep meeting:** refer to the product as "Cursor" only
  (satisfied — `ProviderID.cursor.displayName` is `Cursor`); use published
  variants unmodified; permission is revocable at Anysphere's discretion.

## OpenRouter, Inc.

- **Brand page:** <https://openrouter.ai/brand> — retrieved 2026-08-26,
  HTTP 200, titled "Brand Assets - Official OpenRouter Logos". The URL guessed
  in the previous revision of `docs/asset-resourcing.md` was correct; the note
  that OpenRouter "may not publish a dedicated brand page" was wrong.
- **Clause relied on**, verbatim from that page:
  > "Brand assets — Every configuration of the OpenRouter mark, ready to use.
  > SVG scales anywhere; PNGs are exported at 2×. Please don't stretch,
  > recolor, or remix the marks."
  > "Glyph — The mark alone — avatars, favicons, small sizes."
- **File installed:** `logo-openrouter.imageset/openrouter-color.svg` —
  downloaded verbatim from
  <https://openrouter.ai/brand/logos/transparent/glyph/svg/glyph-volt.svg>,
  unmodified, `sha256 0d22462e4f2835a5a5b9000af0a55fc9238e39996100f54706e41ec45b9d1727`.
  Volt (`#C8FF00`) is OpenRouter's own dark-background glyph colour.
- **Replaced:** the previous `openrouter-color.svg` was a 24×24 redraw whose
  path data is byte-identical to `@lobehub/icons-static-svg`
  `icons/openrouter-color.svg` — a third-party icon library, not an OpenRouter
  asset.
- **Open condition:** "Please don't … recolor". Ammo tints this glyph when
  `widgetRenderingMode == .accented` (`ProviderLogo.swift`, `imageRenderingMode`).
  See `docs/asset-resourcing.md` for the operator decision on that surface.

## Anthropic / Claude — not established

- **Correct URL:** <https://www.anthropic.com/legal/trademark-guidelines>
  (effective August 1, 2024), retrieved 2026-08-26, HTTP 200.
  <https://www.anthropic.com/brand> — the URL guessed in the previous revision
  of `docs/asset-resourcing.md` — returns **HTTP 404**. So do
  `https://www.anthropic.com/press`, `https://www.anthropic.com/brand-guidelines`
  and `https://claude.com/legal/trademark-guidelines`. No public Anthropic brand
  kit or logo download was found.
- **Blocking clauses**, verbatim:
  > "You may only use our trademarks as specifically permitted by us and only in
  > materials we approve beforehand. We may terminate permission to use our
  > trademarks at any time."
  > "We will supply an image (or images) of the trademark(s) for your use and
  > specific requirements regarding size, pixels, spacing, and the like. No
  > alterations of our trademarks (changes to color, font, proportion, or
  > otherwise) are permitted."
- **Claude Code specific**, <https://code.claude.com/docs/en/legal-and-compliance>,
  retrieved 2026-08-26 (`https://docs.anthropic.com/en/docs/claude-code/legal-and-compliance`
  301-redirects here):
  > "**Using the Claude Code name and logo.** You can accurately say, in plain
  > text, that your product has Claude Code preinstalled or that it runs Claude
  > Code. But you can't use the Claude Code or Anthropic names or logos as part
  > of your own product, feature, or company name, in your own logo, or in a way
  > that suggests Anthropic built, endorses, or is partnered with your product.
  > Any other use of Anthropic's names or logos is governed by our Trademark
  > Guidelines and requires our written permission."
- **Shipped file provenance:** `logo-claude.imageset/claudecode-color.svg`
  (`sha256 f231bd90…7d4f`) carries `style="flex:none;line-height:1"` and path
  data identical to `@lobehub/icons-static-svg` `icons/claudecode-color.svg`
  (retrieved 2026-08-26 from
  <https://unpkg.com/@lobehub/icons-static-svg@latest/icons/claudecode-color.svg>);
  the only difference is `<title>Claude Code</title>` → `<title>Claude</title>`.
  It is a third-party icon-library redraw, **not** an Anthropic-supplied image.
- **Not replaced**, because there is no official file to replace it with:
  Anthropic supplies trademark images only to parties it has approved in advance.
- **Permission request address:** marketing@anthropic.com (per the guidelines'
  "Inquiries/Press Releases" section).

## OpenAI / Codex — not established

- **Brand page:** <https://openai.com/brand> — live but returns HTTP 403 to
  scripted fetches; the text quoted below is from the Internet Archive capture
  <https://web.archive.org/web/20260820094316/https://openai.com/brand/>
  (snapshot 2026-08-20), retrieved 2026-08-26.
- **Clauses**, verbatim:
  > "The \"OpenAI\" name, the OpenAI logo, the \"ChatGPT\" and \"GPT\" brands,
  > and other OpenAI trademarks, are property of OpenAI. These guidelines are
  > intended to help our partners, resellers, customers, developers,
  > consultants, publishers, and any other third parties understand how to use
  > and display our trademarks and copyrighted work in their own assets and
  > materials."
  > "How to use our Logos — Do: Use the logo only when it directly relates to
  > OpenAI services. Follow OpenAI's style guides and usage terms. Use the logo
  > exactly as provided and acknowledge that it belongs to OpenAI. Don't: Use
  > the logo without permission or outside OpenAI's terms. Misrepresent your
  > relationship with OpenAI, imply endorsement, or confuse users about
  > sponsorship. Use the logo more prominently than your own or in unrelated
  > contexts. Place the logo on tangible merchandise, promotional items, or
  > modify it in any way. Incorporate the logo into your own branding,
  > trademark, or design a similar logo."
  > "Dos and Don'ts: Blossom — DON'T add any colors to the Blossom."
  > "The term \"Marks\" includes anything we use to identify our goods or
  > services, including our names, logos, icons, and design elements. … Only use
  > our Marks if they adhere to these brand guidelines. … We may terminate
  > permission to use our Marks at any time, and usage must stop promptly."
- **Why no re-source was possible:** the page's "Download logos" control points
  at <https://brand.openai.com/>, which redirects to
  `https://brand.openai.com/auth/?referer=%2F` — an authenticated portal. The
  only publicly downloadable artifact,
  <https://cdn.openai.com/brand/OpenAI-Partnership-Templates-2025.zip>, contains
  two Photoshop `.psb` co-branding templates and no logo files. The brand page
  covers the OpenAI wordmark, the Blossom, ChatGPT and GPT; it does **not**
  publish a Codex mark or any Codex-specific guidance.
- **Shipped file provenance:**
  - `logo-codex.imageset/codex.png` (`sha256 115376e1…0436`) and
    `logo-codex-menu.imageset/codex-menu.png` (`sha256 56a1c564…a72a`) —
    pixel-extracted from the shipped Codex app icon by the (now removed)
    `Scripts/extract-provider-glyphs.py` pipeline. Non-compliant provenance,
    retained only because there is no official asset to replace them with.
  - `logo-openai-monochrome.imageset/openai.svg` (`sha256 c967e13a…69a5`) — the
    OpenAI Blossom on a 41×41 viewBox. This matches the widely mirrored public
    OpenAI logo SVG but is **not** traceable to a first-party download, and the
    first-party download cannot be reached without a `brand.openai.com` account.
    It is also rendered as a template (recoloured) on non-full-colour surfaces,
    which the "DON'T add any colors to the Blossom" clause reads against.
- **Permission request address:** partnercomms@openai.com (per the brand page's
  "Contact" section: "For everything else, including permission requests for the
  use of our logos …").
