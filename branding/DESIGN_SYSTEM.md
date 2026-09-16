# ShreeOS Design System & Visual Specification

**Design Philosophy:** Calm, minimal, intentional, coherent, highly polished, smooth, visually balanced, consistent, native, and understated.

---

## 1. Color System & Surface Hierarchy

ShreeOS avoids pure black or overly saturated backgrounds. Surfaces are organized into clear physical depths.

### Light Mode

| Token | Value | Purpose |
| :--- | :--- | :--- |
| `--desktop-bg` | `#F5F5F7` | Wallpaper background canvas |
| `--surface-primary` | `#FFFFFF` | Main window content, document canvas |
| `--surface-secondary` | `#F5F5F7` | Sidebars, utility trays, toolbar panels |
| `--surface-elevated` | `rgba(255, 255, 255, 0.82)` | Menus, popovers, quick settings, dock |
| `--text-primary` | `#1D1D1F` | Primary headings, body copy, active controls |
| `--text-secondary` | `#6E6E73` | Subheadings, sidebar labels, metadata |
| `--text-muted` | `#86868B` | Placeholder text, disabled labels |
| `--border-subtle` | `rgba(0, 0, 0, 0.10)` | Window borders, row dividers |

### Dark Mode

| Token | Value | Purpose |
| :--- | :--- | :--- |
| `--desktop-bg` | `#0F0F10` | Desktop backdrop canvas |
| `--surface-primary` | `#1C1C1E` | Main window surfaces |
| `--surface-secondary` | `#242426` | Sidebars, tab strips, grouped list rows |
| `--surface-elevated` | `rgba(35, 35, 38, 0.88)` | Translucent dock, menus, search launcher |
| `--text-primary` | `#F5F5F7` | Primary text |
| `--text-secondary` | `#A1A1A6` | Secondary metadata |
| `--text-muted` | `#86868B` | Disabled / timestamp labels |
| `--border-subtle` | `rgba(255, 255, 255, 0.10)` | Window rims, dividers |

### Accent Color

- **ShreeOS Cool Blue:** `#2878FF` (`#3A88FF` light accent / `#1A62E8` active click)
- **Usage Rule:** Reserved strictly for active selections, focused borders, toggles, and progress indicators. Never applied across large surface backgrounds.

---

## 2. Typography Scale

ShreeOS relies on open-source, high-legibility system fonts: **Inter** / **Geist Sans** for UI, and **JetBrains Mono** / **Geist Mono** for code and terminal.

```text
Display / Settings Hero:     24–28px / Semibold (weight: 600)
Window Title / Section Head: 15–16px / Semibold (weight: 600)
Primary UI & Button Label:   13–14px / Regular (400) or Medium (500)
Sidebar & Menu Items:        13px / Regular (400)
Supporting Metadata / Hints: 11–12px / Regular (400)
Monospace Code & Terminal:   12–13px / Regular (400)
```

---

## 3. Geometry, Elevation & Radii

```text
Window Radius:    10–12px (subtle rounded corners, crisp 1px rim)
Control Radius:   6–8px (buttons, input fields, segmented pills)
Dock Radius:      14–18px (subtle glass border + blur)
Menu Radius:      8–10px
Shadows:          Soft realistic ambient falloff (e.g. 0 8px 24px rgba(0,0,0,0.24))
```

---

## 4. Window System & Controls

- **Titlebar Height:** Compact 28–32px with unified toolbar styling.
- **Window Controls (Left-Aligned Original ShreeOS Monograms):**
  - Close: Subtle Crimson `#E54D2E` on hover
  - Minimize: Subtle Amber `#F7B955` on hover
  - Maximize: Subtle Teal/Green `#30A46C` on hover
- **Inactive State:** Unfocused windows subtly dim titlebar contrast and soften border prominence.

---

## 5. Animation Curves & Responsiveness

- **Duration:** 120ms to 200ms maximum.
- **Timing Curve:** `cubic-bezier(0.16, 1, 0.3, 1)` (ease-out quint).
- **Target Frame Rate:** 60 FPS minimum, 120 FPS high-refresh where supported.
