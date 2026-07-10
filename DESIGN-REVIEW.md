# Clarion iOS — Synthesized Design Critique

## 1. Top 5 premium signals already present

1. **Serif display numerals** — the forest-green "86" (Report) and "82" (readiness ring) are the app's signature asset: editorial, distinctive, nothing like Whoop/Oura's geometric sans. All four critiques flagged this as the most "Clarion" pixels in the app.
2. **Serif coaching line on Vitals** ("You're well-recovered — a strong day to push.") — reads like a human coach, the most on-brand sentence in the product.
3. **Tracked-caps micro-label tier** ("READINESS", "WORTH A LOOK", "IN RANGE") — a consistent, quiet labeling system across Vitals/Report.
4. **Restrained semantic palette** — sage "Optimal", amber "Low/Suboptimal", red held in reserve; calm tonal chips instead of alarmist bars.
5. **Trust-earning copy** — privacy lines ("reads your sleep, HRV… nothing else", "never uses health data for advertising") and Plan card specificity ("ferritin (34) is below the endurance floor of 50") outwrite Function Health.

## 2. Top 8 startup tells, ranked by how much they cheapen the product

1. **Stock SF Pro Bold large titles on every screen** ("Clarion", "Vitals", "Report", "Plan", "Settings") — the biggest glyphs in the app are the least branded; the serif never appears at the top of any screen. Flagged by all four lenses as the #1 template tell.
2. **Content smears under the floating tab bar** — ghost "0.1 / Optimal" fragments behind the blur on Report, Readiness sparkline sliced mid-curve on Vitals. Missing bottom inset/fade; the most screenshot-able "unfinished" defect.
3. **Home is a ~55–70% empty void whose only secondary CTA punts to clarionlabs.tech** — first screen of a $200/yr app reads as a companion stub that says "the real product lives on the web."
4. **Settings is an exit-only stock list** — red "Sign out" as the first row, default grouped-list idioms broken (28pt radii, no chevrons, green web-link labels), and zero identity/membership presence (no name, email, plan tier).
5. **Four numeral treatments for one content class** — serif hero 82/86, sans dashboard 82, mono "$20"/"25 mg", small gray sans "~$12/mo". Numbers are the entire product; the data layer looks undesigned.
6. **Stock, mixed-metaphor tab icons** — heavy black droplet-for-Report(?), Android-ish gear, inconsistent weights, grey selected capsule; the most persistent generic element, visible on every screen.
7. **Duplicate "Readiness 82"** (serif ring, then sans card one scroll below) **plus a mathematically perfect sine-wave sparkline with a flat rectangular fill** — redundant hierarchy + obviously synthetic charting on the flagship screen.
8. **Readiness ring rendering artifact** — arc cap seams against a lighter track segment (~10 o'clock), track nearly invisible on white; a visible bug at the center of the hero element.

## 3. Prioritized fix list

### Quick wins (do first)

| # | Fix | Effort |
|---|-----|--------|
| 1 | Set all five nav large-titles (and the "Clarion" wordmark) in the serif display face — one font swap, largest perceived-quality jump per hour | S |
| 2 | Add bottom scrim/fade (~80pt, canvas-color gradient) + proper contentInset so nothing clips or smears behind the tab bar | S |
| 3 | Fix the ring: full even background track, single round-cap arc on top with a deliberate gap at 12 o'clock, higher-contrast track, animate-in sweep | S |
| 4 | Kill the duplicate "Readiness 82" card — repurpose as a 7-day trend card with the sparkline as hero, no repeated number | S |
| 5 | Replace the sine-wave sample data with plausibly noisy demo data and swap the flat-rectangle fill for a curve-following gradient area fill; add a 7d/30d label | S |
| 6 | Pick one numeral system: serif reserved for hero scores; SF tabular figures (drop the mono) for every dose/price/value — fix "$20", "25 mg", "2000 IU", "~$12/mo" first | S |
| 7 | Tab bar: consistent single-weight SF Symbols set (replace the droplet and gear), unselected at ~40% muted ink, green-tint selected state instead of grey capsule | S |
| 8 | Recolor "2 to review" from dusty-rose/red to the existing amber family; derive amber + clay-red semantic tokens from the forest-green system (also for destructive rows) | S |
| 9 | Reorder Settings: Sign out moves to bottom near (but separated from) Delete; only Delete stays red; unify section headers on the tracked-caps style ("ACCOUNT", "HEALTH DATA") | S |
| 10 | Demote the "Sample data" banner on Vitals to a small chip below the coaching line so the ring sits above the fold's midline | S |

### Structural

| # | Fix | Effort |
|---|-----|--------|
| 11 | One surface system across all five tabs: single warm paper canvas (kill the per-tab drift incl. Settings' systemGray6), white cards with one shadow recipe (e.g. y=8/blur=24 at ~6% forest green) and one radius token; kill the recessed grey Home card | M |
| 12 | Adopt real NavigationStack large titles (collapse on scroll); mount the Vitals filter as a trailing toolbar item instead of a floating white circle | M |
| 13 | Rebuild Settings as a native inset-grouped list (~10pt corners, chevrons on Privacy/Terms rows) with an identity/membership header — avatar, name, email, "Clarion Member · renews Mar 2027" | M |
| 14 | Rework Plan cards: supplement name on its own line (no inline chip mid-title), dose right-aligned, "Ferritin · ~$12/mo" metadata row; add one action per card (why-this-form disclosure, Reorder / Mark as taking) | M |
| 15 | Make Report range bars honest instruments: band boundary values + units on the track (e.g. 50–150 ng/mL), labeled user marker, per-marker geometry (ApoB ≠ HDL), disclosure affordance if rows navigate | M |
| 16 | Rebuild Home as the daily front door: post-connect readiness snapshot, top Report flag, next dose, last-sync time; pre-connect, a blurred preview skeleton under the Connect card; clarionlabs.tech link demoted to a quiet footer row | L |
