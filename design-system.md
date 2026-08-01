# Yozgat Design System

A self-hosted deployment platform built with restraint. Every decision favors
clarity, maintenance, and longevity over novelty.

This document is the single source of truth for how the Yozgat UI looks and
behaves. It is derived from two reference pages:

- `docs/design-system.html` — principles, tokens, typography, components, status
- `docs/components.html` — the component library in isolation

---

## 1. Principles

> Trust comes from predictability, not decoration.

- **Quiet before expressive.**
- **Readable before stylish.**
- **Stable before exciting.**
- **Simple before clever.**
- **Built to age gracefully.**
- **Visual confidence through consistency.**

Yozgat is not rustic or nostalgic. It is modern because it removes everything
that does not help the operator accomplish their work.

---

## 2. Design tokens

All tokens are CSS custom properties on `:root`. Use them directly — do not
hardcode colors or radii.

```css
:root {
  --bg:             #f6f4ef;
  --surface:        #fcfbf8;
  --surface-2:      #f1eee7;

  --text:           #1f2320;
  --muted:          #5f665f;

  --border:         #d7d2c8;
  --border-strong:  #b8b1a5;

  --primary:        #2f4d38;
  --primary-hover:  #26412f;

  --warning:        #9d6d2d;
  --danger:         #8d3c34;
  --success:        #40684d;

  --shadow:         0 1px 2px rgba(0, 0, 0, .05);
  --radius:         8px;

  --font:
    Inter,
    ui-sans-serif,
    system-ui,
    sans-serif;
}
```

### 2.1 Color roles

| Token | Value | Use |
|---|---|---|
| `--bg` | `#f6f4ef` | Page background (warm paper) |
| `--surface` | `#fcfbf8` | Cards, panels, nav bars |
| `--surface-2` | `#f1eee7` | Hover fills on secondary controls |
| `--text` | `#1f2320` | Primary copy |
| `--muted` | `#5f665f` | Secondary copy, descriptions |
| `--border` | `#d7d2c8` | Default hairlines |
| `--border-strong` | `#b8b1a5` | Secondary button borders, emphasis |
| `--primary` | `#2f4d38` | Primary actions, focus, active states |
| `--primary-hover` | `#26412f` | Primary action hover |
| `--warning` | `#9d6d2d` | Warning/updating status |
| `--danger` | `#8d3c34` | Destructive actions, offline status |
| `--success` | `#40684d` | Healthy/live status |

The greens (`--primary`, `--success`) are deliberately close. `--primary` is
for **actions and structure**; `--success` is for **status**.

### 2.2 Semantics

- **Radius:** `--radius: 8px` for cards and containers; `6px` for controls
  (buttons, inputs, badges are `999px`).
- **Elevation:** one shadow only — `0 1px 2px rgba(0,0,0,.05)`. Hierarchy
  comes from borders and whitespace, not shadows.
- **Borders:** thin (1px) hairline borders, never heavy shadows.
- **Motion:** `transition: .12s` everywhere. No bouncing, no spring.

### 2.3 Background treatment

The page background uses two layers over `--bg`:

```css
body {
  background:
    radial-gradient(circle at top, rgba(255, 255, 255, .55), transparent 65%),
    repeating-linear-gradient(
      0deg,
      rgba(0, 0, 0, .012), rgba(0, 0, 0, .012) 1px,
      transparent 1px, transparent 6px
    ),
    var(--bg);
}
```

---

## 3. Typography

- **Stack:** `Inter, ui-sans-serif, system-ui, sans-serif`
- **Code stack:** `ui-monospace, SFMono-Regular, Consolas, monospace`
- **Line height:** `1.55` — generous, built for dashboards operators read for
  hours rather than minutes.
- **Headings:** weight `700`, letter-spacing slightly tightened
  (`-.04em` for the page title, `-.02em` for section headings).

| Style | Spec |
|---|---|
| Page title `h1` | `38px`, `700`, `letter-spacing: -.04em` |
| Section heading `h2` | `22px` (overview page) / `18px` (component page), `-.02em` |
| Subheading `h3` | `16px` |
| Body | `16px`, `--muted` for `p`, `line-height: 1.55` |
| Code | `ui-monospace, SFMono-Regular, Consolas, monospace` |
| Labels | `font: inherit` on controls; `.field` uses a `label` above the input |

---

## 4. Components

### 4.1 Buttons

```html
<button class="primary">Deploy</button>
<button class="secondary">Settings</button>
<button class="btn-danger">Delete</button>
```

```css
button {
  font: inherit;
  border-radius: 6px;
  cursor: pointer;
  transition: .12s;
  padding: 10px 18px;
}

.primary {
  background: var(--primary);
  color: white;
  border: 1px solid var(--primary);
}
.primary:hover { background: var(--primary-hover); }

.secondary {
  background: var(--surface);
  color: var(--text);
  border: 1px solid var(--border-strong);
}
.secondary:hover { background: var(--surface-2); }

.btn-danger {
  background: #fff;
  color: var(--danger);
  border: 1px solid #d8b3af;
}
.btn-danger:hover { background: var(--surface-alt); }
```

Three tones, one shape: **primary** (one per view), **secondary** (default),
**danger** (destructive confirmation).

### 4.2 Form fields

```html
<div class="field">
  <label>Application Name</label>
  <input placeholder="my-api">
</div>

<div class="field">
  <label>Region</label>
  <select><option>Germany</option></select>
</div>

<div class="field">
  <label>Description</label>
  <textarea rows="4"></textarea>
</div>

<label class="checkbox">
  <input type="checkbox">
  <span>Enable automatic deployments</span>
</label>
```

```css
input:not([type="checkbox"]), textarea, select {
  width: 100%;
  padding: 11px 12px;
  border-radius: 6px;
  border: 1px solid var(--border);
  background: white;
  font: inherit;
}

input:not([type="checkbox"]):focus,
textarea:focus, select:focus {
  outline: none;
  border-color: var(--primary);
}

/* Checkboxes opt out of the full-width field styling */
input[type="checkbox"] {
  width: 16px;
  height: 16px;
  margin: 0;
  flex-shrink: 0;
  accent-color: var(--primary);
}

.field { display: grid; gap: 8px; margin-bottom: 18px; }

.checkbox {
  display: flex;
  gap: 10px;
  align-items: flex-start; /* checkbox aligns to the first line of text */
  cursor: pointer;         /* whole row is clickable via <label> */
}
.checkbox input[type="checkbox"] { margin-top: 3px; }
```

Focus = primary border, no glow, no ring. The checkbox keeps its native focus
indicator and uses `accent-color` so the checked state follows the palette.

The `<label>` wrapper makes the entire row a click target (large hit area) and
ties the text to the control for screen readers. `align-items: flex-start`
keeps the box optically aligned to the first line when the label wraps.

### 4.3 Status badges

```html
<span class="badge success">Healthy</span>
<span class="badge warning">Deploying</span>
<span class="badge danger">Offline</span>
```

```css
.badge {
  display: inline-flex;
  padding: 4px 10px;
  border-radius: 999px;
  font-size: 13px;
  font-weight: 600;
}
.success { background: #e6efe8; color: var(--success); }
.warning { background: #f4ebdd; color: var(--warning); }
.danger  { background: #f3e4e2; color: var(--danger); }
```

Status labels are human verbs: `Healthy`, `Deploying`, `Offline`.

### 4.4 Cards

```html
<div class="card">
  <h3>API Gateway</h3>
  <p>Production deployment.</p>
  <span class="badge success">Running</span>
</div>
```

```css
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 20–24px;
  box-shadow: var(--shadow);
}
```

### 4.5 Navigation

```html
<div class="nav">
  <strong>YOZGAT</strong>
  <div class="nav-links">
    <a href="#">Applications</a>
    <a href="#">Deployments</a>
    <a href="#">Servers</a>
    <a href="#">Settings</a>
  </div>
</div>
```

```css
.nav {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14px 18px;
  background: white;
  border: 1px solid var(--border);
  border-radius: var(--radius);
}
.nav-links { display: flex; gap: 18px; }
.nav-links a { text-decoration: none; color: var(--muted); }
```

### 4.6 Tables

```html
<table class="table">
  <thead>
    <tr><th>Name</th><th>Status</th><th>Version</th></tr>
  </thead>
  <tbody>
    <tr>
      <td>Frontend</td>
      <td><span class="badge success">Healthy</span></td>
      <td>v2.4.1</td>
    </tr>
  </tbody>
</table>
```

```css
.table { width: 100%; border-collapse: collapse; }
.table th {
  text-align: left;
  font-weight: 600;
  padding: 12px;
  border-bottom: 1px solid var(--border);
}
.table td {
  padding: 12px;
  border-bottom: 1px solid var(--border);
}
```

### 4.7 Alerts

```html
<div class="alert">
  Deployment completed successfully. Configuration has been synchronized
  across all nodes.
</div>
```

```css
.alert {
  padding: 16px;
  border-left: 4px solid var(--primary);
  background: #f4f2ec;
}
```

Left-rule alert, no icon, no color box.

### 4.8 Progress

```html
<div class="progress"><div></div></div>
```

```css
.progress {
  width: 320px;
  height: 8px;
  background: #e5e1d9;
  border-radius: 999px;
  overflow: hidden;
}
.progress div {
  height: 100%;
  width: 68%;              /* value */
  background: var(--primary);
}
```

### 4.9 Statistics

```html
<div class="stats">
  <div class="stat">
    <p>Applications</p>
    <h3>42</h3>
  </div>
</div>
```

```css
.stats { display: flex; gap: 16px; flex-wrap: wrap; }
.stat {
  background: white;
  border: 1px solid var(--border);
  padding: 18px;
  border-radius: var(--radius);
  width: 180px;
}
.stat h3 { font-size: 28px; }
.stat p  { color: var(--muted); }
```

### 4.10 Code blocks

```css
.code {
  background: #242824;
  color: #e6e7e5;
  padding: 18px;
  border-radius: var(--radius);
  font-family: ui-monospace, monospace;
  overflow: auto;
}
```

Dark block is the one place the light theme inverts — keep it monochrome.

### 4.11 Blockquote

```css
blockquote {
  border-left: 4px solid var(--primary);
  padding-left: 16px;
  color: var(--text);
  font-weight: 500;
}
```

---

## 5. Interaction & motion rules

- Fast transitions under **150ms** (`.12s` used consistently).
- **No bouncing animations.**
- **No floating elements.**
- **No glass effects.**
- Small radius between **6px** and **8px**.
- **Thin borders** instead of heavy shadows.
- **Whitespace defines hierarchy.**

---

## 6. Layout

- Content max-width: `1200px`, centered.
- Page padding: `48px` (or `48px` on `body`).
- Card grid: `repeat(auto-fit, minmax(320px, 1fr))` with `24px` gaps.
- Vertical rhythm: sections spaced `28–48px`, headings carry `8–20px` bottom
  margin.

---

## 7. Usage rules

1. **Always use the CSS variables.** Never inline a hex value that has a token.
2. **One primary button per view.** Everything else secondary or danger.
3. **Badges carry status, colors carry intent.** Don't use a green button to
   mean "healthy".
4. **No spinners.** Loading is skeletons or nothing.
5. **Sentence case everywhere:** `Deployments`, `Environment variables`,
   `Sign out`. Never `deployments`.
6. **No trailing ellipses.** The skeleton is the loading signal.
7. **Table-less layout decisions:** prefer whitespace and hairlines over
   shadow depth.

---

## 8. Do / Don't

| Do | Don't |
|---|---|
| Use `--primary` for the one main action | Stack multiple primary buttons |
| Hairline borders + one soft shadow | Drop shadows on every element |
| `6–8px` radii | Pill-shaped buttons |
| Whitespace to separate | Floating cards / glassmorphism |
| Muted copy for descriptions | Grey text that can't be read |
| Skeletons for loading | Spinners, bouncing dots |
| `var(--danger)` for destructive text | Red buttons for non-destructive actions |
