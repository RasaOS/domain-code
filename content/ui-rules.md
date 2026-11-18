# UI rules (universal)

What every screen must meet, on any platform. Read before planning or
building anything a person sees. `/develop` holds a task to these when
it carries `x-ui: true`; the plan and the request audit have a slot for
each rule below.

**Size classes: the numbers live in your conventions file**
(`web-conventions.md`, `ios-conventions.md`). This file names the
classes and the rules; it does not fix widths.

## Size classes

Three classes: **compact** (mobile), **medium** (tablet), **expanded**
(desktop). Design and check every screen at all three. Layout reflows
between them: text wraps, containers grow, nothing is cut off or
scrolls sideways. A control that works with a finger also works with a
pointer and a keyboard.

**Evidence is per size class:** a screenshot, or a described layout
when no screenshot can be taken. A screen is not done with one class
shown. The five states below are **described**, not screenshotted.
Screenshots are of seed or fixture data only: never of production,
and never committed; attach them to the PR.

## Targets

Touch and click targets are large enough to hit without error and are
spaced so neighbours are not hit by mistake. The conventions file sets
the minimum.

## Five states

Every screen that loads or changes data handles all five, each
designed on purpose:

1. **Loading**: something shows that work is in progress.
2. **Empty**: nothing yet, with the next step offered.
3. **Error**: what failed, and a way to retry or leave.
4. **Populated**: the normal case, including very long and very short
   content.
5. **No permission**: the person may not see or do this; say so.

## Interaction feedback

Every action shows **pending**, then **success** or **failure**.
Destructive actions confirm first. Nothing happens silently, and a
failure is never swallowed.

## Accessibility

- Text and controls have enough contrast.
- Focus order follows reading order.
- Everything is reachable by keyboard and by assistive technology.
- Every control and image has a label.
- Colour is never the only signal; pair it with text or a shape.

## Navigation back stack

Navigation discipline is in `craft-rules.md` ("Navigation
discipline"); this section is what a screen must do on top of it.

- Every screen has an address (a URL, or a typed path value).
- Back returns to the previous screen **with its state**: scroll
  position, filters, selected tab.
- A deep link or a reload lands on the same screen, and back from it
  goes to a sensible parent, not out of the app.
- Overlays (sheets, dialogs, drawers) close on back without leaving
  the screen beneath.
- After create or delete, **replace** the entry; do not push, so back
  never returns to a form that no longer applies.
- No dead ends: every screen has a way out.
- Where the platform has tabs, each tab keeps its own stack.

## Uniform with the product

Reuse the project's **Design source** (its tokens, theme and
component library) for every colour, spacing and type value and every
control. No new hard-coded colour, spacing or type value where a token
exists. A new token or component is a plan item with a reason. If the
project declares no Design source, that is an open question to raise,
not a licence to invent one.

## Visualise data

Where a picture reads better than a number, draw it. Which chart is
**guidance**:

- **Proportion** of a few parts: pie or donut.
- **Comparison**: bar.
- **Trend** over time: line.
- **Status or category**: colour plus a label.
- **Headline numbers**: stat tiles.

The rules, which a reviewer can check:

- **Label and legend, always.**
- **Colour plus a second signal** (a label, glyph or position); colour
  is never the only encoding (`output-rules.md`, "Glyph and color
  discipline").
- **Palette from the Design source**, colour-blind safe.
- **A table when exact values matter**, or when there are many
  columns.

## What the plan and the task carry

- **Per size class:** the layout and its evidence.
- **Back stack, states, feedback, accessibility, visuals.**
- **Design source:** the files the project uses as its style source,
  or `none declared` as an open question.
- A slot that does not apply is filled with one line:
  `Not touched: <why>`.
