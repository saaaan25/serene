# Design System: Editorial Dark Mode Specification

## 1. Overview & Creative North Star

This design system is built upon the Creative North Star of **"The Ethereal Guardian."** In a digital landscape often defined by aggressive, sharp-edged security aesthetics, this system takes a counter-intuitive approach: protection through serenity. We move away from the "industrial bunker" look of traditional dark modes, opting instead for a sophisticated, editorial experience that feels like a premium private gallery.

The aesthetic breaks the "template" look through:
*   **Intentional Asymmetry:** Strategic use of whitespace (the "breathing room" principle) and off-grid element placement to guide the eye.
*   **Curated Contrast:** A deep, obsidian-navy foundation paired with soft, candy-toned pastels that act as high-visibility beacons.
*   **Soft Power:** Extreme corner rounding (`ROUND_FULL`) and layered glass textures that signal approachability without sacrificing authority.

## 2. Colors

The palette is a high-contrast study in depth. We use a deep navy foundation to ensure the pastel accents "glow" with a neon-like softness, ensuring readability and visual soul.

### The Foundation (Neutrals)
*   **Surface (Base):** `#060e20` — The anchor. A deep, ink-like navy.
*   **Surface Bright:** `#1f2b49` — Used for high-level interaction areas.
*   **On-Surface:** `#dee5ff` — High-contrast text to ensure WCAG compliance.
*   **Outline-Variant:** `#40485d` — Reserved for low-opacity "ghost" borders.

### The Accents (Vibrant Protective Tones)
*   **Primary (Vibrant Blue):** `#a1d1fe` — Core actions and primary security indicators.
*   **Secondary (Lavender):** `#f1d6ff` — Informational highlights and secondary navigation.
*   **Tertiary (Vibrant Pink):** `#ffc1d6` — High-priority status and interactive feedback.

### Architectural Rules
*   **The "No-Line" Rule:** 1px solid borders are strictly prohibited for sectioning. Boundaries must be defined solely through background color shifts. For example, a `surface-container-low` card sitting on a `surface` background creates a natural, sophisticated edge.
*   **Surface Hierarchy & Nesting:** UI elements are treated as stacked sheets of fine paper. Use the tiers (`Lowest` to `Highest`) to define importance. An inner module should always be one tier higher than its parent container to create "soft depth."
*   **Signature Textures:** Use subtle linear gradients for primary CTAs (e.g., `#a1d1fe` to `#75a5d0`). This provides a "custom-molded" feel that flat color cannot replicate.

## 3. Typography: The Editorial Voice

We utilize **Manrope** for its geometric clarity and modern humanist touch. The typography hierarchy is designed to feel like a high-end periodical.

*   **Display (L/M/S):** 3.5rem down to 2.25rem. Use these for high-impact brand moments. Tighten letter-spacing slightly (-2%) to add an authoritative, "locked-in" feel.
*   **Headline (L/M/S):** 2rem down to 1.5rem. Used for section headers. Ensure generous top-margin to provide the "breathing room" required by the Ethereal Guardian aesthetic.
*   **Body (L/M/S):** 1rem down to 0.75rem. Set with a slightly increased line-height (1.6) to maximize legibility against the dark background.
*   **Label (M/S):** 0.75rem. Used for metadata and button text. Always uppercase for a "technical but elegant" look.

## 4. Elevation & Depth: Tonal Layering

Traditional drop shadows are too "heavy" for this system. We achieve lift through light and glass.

*   **The Layering Principle:** Place a `surface-container-lowest` card on a `surface-container-low` section. This creates a subtle, recessed effect that feels structural rather than decorated.
*   **Glassmorphism:** For floating menus or high-level overlays, use semi-transparent surface colors (80% opacity) with a `20px` backdrop-blur. This allows underlying colors to bleed through, creating a "frosted glass" effect.
*   **Ambient Shadows:** If a floating element requires a shadow, it must be extra-diffused. Use a blur of `32px` or higher at `6%` opacity. The shadow color must be a tinted navy (`#000814`), never pure black.
*   **The Ghost Border:** For input fields or cards requiring absolute containment, use the `outline-variant` token at **15% opacity**. This provides a "hint" of a border that vanishes into the background, maintaining the "No-Line" philosophy.

## 5. Components

### Buttons
*   **Primary:** Solid `primary` color, `ROUND_FULL` (pill-shaped). Text is `on-primary`. Use a subtle inner-glow (white at 10% opacity) on the top edge to mimic 3D curvature.
*   **Secondary:** Ghost-style with a `primary` label. No border. Hover state introduces a `surface-container-high` background.

### Cards & Lists
*   **Structure:** Forbid divider lines. Use `1.5rem` (MD Spacing) to separate list items.
*   **Interaction:** On hover, a card should transition from `surface-container` to `surface-container-highest` with a slight 2px vertical lift.

### Input Fields
*   **Visuals:** Fill-only. Use `surface-container-low` as the base.
*   **Focus State:** A 2px "Ghost Border" using the `primary` color at 40% opacity. Avoid high-contrast glow; keep it a "soft pulse."

### Chips & Status Indicators
*   **Logic:** Use `ROUND_FULL`. Indicators for "Secure" or "Active" should use the `secondary` (Lavender) or `primary` (Blue) palettes. Reserve `tertiary` (Pink) for cautionary or attention-required states.

## 6. Do’s and Don’ts

### Do
*   **Do** use asymmetrical margins (e.g., 24px left, 48px right) for hero sections to create an editorial flow.
*   **Do** lean heavily on the `ROUND_FULL` token for all interactive elements to reinforce the "protective/soft" brand soul.
*   **Do** use the pastel accents sparingly as "light-sources" in the dark environment.

### Don’t
*   **Don’t** use pure `#000000` for backgrounds. It kills the depth and creates harsh "ink-bleed" against the text.
*   **Don’t** use 100% opaque borders. They create a "grid-locked" feel that violates the Ethereal Guardian North Star.
*   **Don’t** stack more than three levels of surface containers. It leads to visual clutter and "nesting fatigue."