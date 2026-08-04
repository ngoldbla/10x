# OS 26 → OS 27: what changed in Apple's design language

Research digest, August 2026. Compiled for this audit by a research agent working
from Apple's own developer site (WWDC26 session transcripts, the HIG, API
reference) plus Hacker News for community discourse.

**Read the method caveat first.** `WebSearch` returned zero results for every
query in that session, so everything below comes from **direct page fetches of
Apple's own material**. Coverage of third-party press and design-blog commentary
is therefore thin *by construction*, not because it does not exist. The "what I
could not find" section means "could not find with the tools that worked".

**Timing.** OS 27 is at **beta 4** as of this audit. WWDC26 ran June 8–12, 2026;
the HIG's WWDC26 revision is dated June 8, 2026. Public release has not happened.

---

## The headline: OS 27 refines Liquid Glass, it does not replace it

Apple frames 27 as continuation. From the Platforms State of the Union
([WWDC26 session 102](https://developer.apple.com/videos/play/wwdc2026/102/)):

> "Throughout the last year, we've been refining the design, and that journey
> continues with a new set of design updates in the 27 releases."

> "Apps that have already adopted Liquid Glass benefit from many of these
> improvements automatically."

### Material changes, all automatic

| Change | Apple's words | Source |
|---|---|---|
| Better diffusion | "we tuned Liquid Glass so it more effectively diffuses complex content behind it" | SOTU |
| Depth via edges | "a darkened edge along with brighter specular highlights" | SOTU |
| User tint slider | "a new slider in settings to adjust Liquid Glass anywhere from ultra clear to fully tinted" | SOTU |
| No recompile needed | "get these improvements automatically… without even needing to recompile" | SOTU |

**The opt-out is being removed.** `UIDesignRequiresCompatibility` — *"The system
ignores this key when you build for iOS 27 or later… or tvOS 27 or later"*
([API ref](https://developer.apple.com/documentation/BundleResources/Information-Property-List/UIDesignRequiresCompatibility)).
Once built with Xcode 27 there is no going back to the old design.

### Specific surface changes

- **Sidebars extend to window edges; sidebar icons regain colour** via the app's
  accent colour. `List`/`Label` provide this automatically.
- **Scroll-edge `.automatic` changed meaning.** From
  [session 278](https://developer.apple.com/videos/play/wwdc2026/278/): *"the
  `.automatic` style no longer switches between the existing soft and hard styles
  but provides its own visuals… If you have overridden the style from `.automatic`
  previously, that decision should be re-evaluated, especially when set to
  `.soft`, as that no longer matches the default system appearance."*
- **A uniform toolbar appears over scrolled content automatically**, for standard
  toolbars.
- **Menu icons are hidden by default**; opt in per-item with
  `preferredImageVisibility`.
- **App icons render sharper**, with opt-in refraction. Icon Composer 2 shipped
  June 8, 2026.
- **macOS window corner radius tightened** uniformly.

### The one accessibility API change

`accessibilityShowButtonShapes` is **deprecated**; `accessibilityShowBorders`
replaces it. Back-deployed to 26.1, so it can be adopted without raising a
deployment floor. On macOS 27 it is driven by a dedicated Show Borders setting;
on earlier macOS by Increased Contrast.

### The most useful negative finding

**No new Liquid Glass APIs shipped in the OS 27 SwiftUI cycle.** The
[SwiftUI updates page](https://developer.apple.com/documentation/Updates/SwiftUI)
June 2026 section lists `State()` macro, `ContentBuilder`, `reorderable()`,
`swipeActionsContainer()`, `visibilityPriority(_:)`, `ToolbarOverflowMenu`,
`toolbarMinimizeBehavior`, `crossFade`, `Tab(role: .prominent)` and others —
**not one glass API**. `glassEffect`, `GlassEffectContainer`,
`backgroundExtensionEffect`, `ToolbarSpacer`, `scrollEdgeEffectStyle` all remain
dated June 2025. The `Glass` struct still shows `iOS 26.0+ / tvOS 26.0+ /
watchOS 26.0+` with the same members (`.regular`, `.clear`, `.identity`,
`.tint(_:)`, `.interactive(_:)`).

There is also **no WWDC26 session dedicated to Liquid Glass or materials** —
glass content lives inside the SOTU and session 269. Contrast with WWDC25, which
had "Meet Liquid Glass".

---

## Anti-overuse guidance — the strongest material for a critique

All of this is **currently live** HIG text. Note the dating caveat below.

- **Glass does not belong in the content layer.** *"Don't use Liquid Glass in the
  content layer… including it in the content layer can result in unnecessary
  complexity and a confusing visual hierarchy."*
  ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials))
- **Use it sparingly.** *"Use Liquid Glass effects sparingly… overusing this
  material in multiple custom controls can provide a subpar user experience by
  distracting from that content. Limit these effects to the most important
  functional elements in your app."*
- **Don't stack glass on glass.** *"avoid overcrowding or layering Liquid Glass
  elements on top of each other."*
  ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass))
- **Clear glass has a narrow use and a numeric rule.** *"Only use clear Liquid
  Glass for components that appear over visually rich backgrounds… If the
  underlying content is bright, consider adding a dark dimming layer of 35%
  opacity."*
- **Tint is for emphasis, not decoration.** *"Apply color sparingly… reserve it
  for elements that truly benefit from emphasis… Refrain from adding color to the
  background of multiple controls."*
  ([HIG Color](https://developer.apple.com/design/human-interface-guidelines/color))
- **Too much glass is a performance problem too.** *"Creating too many Liquid
  Glass effect containers… can degrade performance."*
- **The two-layer model** ([session 251](https://developer.apple.com/videos/play/wwdc2026/251/)):
  *"Think of your app as two distinct layers: the UI layer, which serves as the
  global navigation, and the content layer… Conceptually, the content layer is
  the best opportunity to express your brand identity."*

**This maps exactly onto Nine's own charter rule 3** ("the pixel aesthetic lives
in the content layer only; the interface layer is pure tvOS 26 / iOS 26"). That
is a point of agreement worth stating rather than re-litigating.

### The reintroduced Design principles page (new at WWDC26)

Eight principles — Purpose, Agency, Responsibility, Familiarity, Flexibility,
Simplicity, Craft, Delight. Three lines are directly usable here:

> "Simplicity isn't minimalism. Aim for a focused, useful experience that keeps
> the important things close by and lets the others fall away."

> "Don't mistake delight for decoration… don't let pursuit of delight for its own
> sake get in the way of your product's core purpose."

> "Maintain your craft. Shipping isn't the finish line."

---

## tvOS 27 — the biggest platform-specific item, and it is not glass

**Dynamic Type arrives on tvOS for the first time.** From
[session 221](https://developer.apple.com/videos/play/wwdc2026/221/): *"This year,
there is great news for accessibility on tvOS 27. Large Text support is now
available, bringing system-wide text scaling to every app on the platform."*
Settings → Accessibility → Display → Text Size, *"starting at Large all the way
up to Accessibility XXXL."*

Concrete obligations from that session:

- Replace hard-coded font sizes with text styles + `adjustsFontForContentSizeCategory`.
- Replace fixed width/height constraints with flexible ones.
- Adapt via `@Environment(\.dynamicTypeSize)` and `AnyLayout` — e.g. reduce grid
  columns when `dynamicTypeSize.isAccessibilitySize`.
- *"Indicate support for Larger Text in your App Store Accessibility Nutrition
  Labels for tvOS."*

**tvOS glass is focus-driven and hardware-gated.** *"Certain interface elements,
like image views and buttons, adopt Liquid Glass when they gain focus"*, and
*"Apple TV 4K (2nd generation) and newer models support Liquid Glass effects. On
older devices, your app maintains its current appearance."* A tvOS design that
relies on glass for resting-state hierarchy degrades on older hardware.

## watchOS 27

Minimal. *"Liquid Glass changes are minimal in watchOS, so they appear
automatically… even if you don't build against the latest SDK."* Reorderable
containers are new to watchOS this cycle.

---

## Community consensus on "too much glass"

The most-cited critique is Nielsen Norman Group, Oct 2025, Raluca Budiu:
["Liquid Glass Is Cracked, and Usability Suffers in iOS 26"](https://www.nngroup.com/articles/liquid-glass/)
(752 HN points). Findings: search bars blending into content (*"Text on top of
text creates an illegible mess"*); semitransparent floating controls obscuring
page content; shrunken tap targets; controls that appear and vanish contextually,
forcing users to *"play hide-and-seek with the navigation controls"*; and on
motion, *"Motion for motion's sake is not usability. It's distraction with a side
of nausea."*

Apple shipped a user-facing transparency control in **iOS 26.1** (Oct 2025). The
OS 27 ultra-clear→fully-tinted slider is that idea's evolution.

Other 2025–26 discourse: [tidbits.com](https://tidbits.com/2025/10/09/how-to-turn-liquid-glass-into-a-solid-interface/),
[ia.net "Liquid Glass Design or Kitsch?"](https://ia.net/topics/liquid-glass),
[The Verge "The unbearable sameness of Liquid Glass"](https://www.theverge.com/apple/778197/liquid-glass-iphone-watch-ipad-mac),
[mjtsai "Liquid Glass Is Permanent"](https://mjtsai.com/blog/2026/03/23/liquid-glass-is-permanent/).

---

## What could not be found — state these as unknown

- **Any Apple statement that developers overused glass in OS 26.** The "use
  sparingly" language is unchanged from 2025. Apple has issued no correction or
  "we went too far" acknowledgement. **Any such claim in a critique would be
  fabricated.**
- **No API to read the user's Liquid Glass tint-slider position.** Checked the
  `Glass` struct and the SwiftUI accessibility environment values.
- **No numeric contrast guidance specific to glass.** The HIG gives WCAG AA
  ratios for foreground-on-background generally, and nothing at all on measuring
  contrast when the background is a live blur of arbitrary content. **This is the
  largest gap for a conformance-focused audit: the obligation is real and Apple
  supplies no method.** Nine's own contrast harness — which samples the
  *composited* pixels rather than computing from theme constants — is therefore
  ahead of the guidance, and that is worth saying.
- **The core HIG foundation pages were NOT revised at WWDC26.** Verified per-page
  changelogs: Materials (Sept 9 2025), Motion (Sept 9 2025), Layout (Sept 9
  2025), Typography (Dec 16 2025), Accessibility (June 9 2025). WWDC26 revised
  Design principles, Siri, Snippets, App Shortcuts, Menus, Sidebars, Scroll
  views, App icons, Search fields, Tab bars, Generative AI, ML, Apple Pay, Wallet.
  **Expect another HIG revision at the OS 27 GM** — Materials was last touched in
  September, not June, last cycle.
- **No tvOS 27 or watchOS 27 release-note entry mentions Liquid Glass.**
- Whether `backgroundExtensionEffect` changed in 27, and whether the new darkened
  edge / brighter speculars are exposed to custom `glassEffect` views or apply
  only to system components.

---

## Implications for Nine

1. **Do not chase new APIs — there are none.** If the app already uses
   `glassEffect`, `GlassEffectContainer` and `backgroundExtensionEffect`, it is on
   current API. OS 27's changes arrive free. A redesign should be about
   **editorial restraint and hierarchy**, not new modifiers.
2. **The compatibility escape hatch is gone.** Remove any
   `UIDesignRequiresCompatibility` — it is dead weight from OS 27.
3. **Re-audit any explicit scroll-edge style override.** `.automatic` changed
   meaning and `.soft` no longer matches the system default. This is the one
   concrete behavioural break Apple flagged.
4. **Rename `accessibilityShowButtonShapes` → `accessibilityShowBorders`.**
   Back-deployed to 26.1; cheap and unambiguous.
5. **tvOS Dynamic Type is a real, non-optional obligation** and it is not about
   glass. Any hard-coded font size or fixed frame in the tvOS target is now a
   defect — text can scale to Accessibility XXXL. It also has a distribution
   consequence via Accessibility Nutrition Labels.
6. **The strongest anti-overwrought ammunition is Apple's own live text**, and it
   has not changed: glass not in the content layer, used sparingly, never stacked,
   tint not on multiple control backgrounds.
7. **Nine's charter already agrees with Apple's two-layer model.** Say so.
8. **On tvOS, glass is focus-driven and hardware-gated.** A design that assumes
   glass is always present, or uses it to convey resting-state hierarchy,
   degrades on pre-2nd-gen Apple TV 4K.
9. **Design for a tint range you no longer control.** Users can set glass from
   ultra-clear to fully tinted. Apple's automatic adaptation covers *system*
   components only — *"Ensure you test your app's custom elements, colors, and
   animations with different configurations of these settings."* Since Apple
   supplies no way to measure contrast against a live blur, the honest engineering
   answer is a test matrix (slider extremes × Reduce Transparency × Increase
   Contrast × light/dark), not a computed conformance claim.
