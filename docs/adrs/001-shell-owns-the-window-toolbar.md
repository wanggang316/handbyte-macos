# 001: The shell owns the window toolbar

Status: Accepted

## Context

The window toolbar holds the shell: the wordmark at the leading edge and
`SectionTabs` in the principal position. The sections below it are one column
with no sidebar.

The Clean review screen (`ReviewView`) used `NavigationSplitView` with its own
column toolbar (sort, rescan, sidebar toggle) and `.searchable(placement: .toolbar)`.
A split view divides the window toolbar into column toolbars. With the list
column shown, the wordmark and the tabs moved into the detail column and the
tabs overflowed into a `>>` menu. With the list column hidden, they returned to
their usual positions. The toolbar did not match before and after the toggle.

## Decision

- Only the shell adds items to the window toolbar: `Wordmark` and `SectionTabs`.
- A section does not add toolbar items, does not use `NavigationSplitView`, and
  does not use `.searchable(placement: .toolbar)`.
- A section puts its controls (filters, sort, search, refresh) in a header
  inside its content.
- A list with a detail pane uses the Apps layout: header, then
  `HStack(list | 1 pt divider | inspector)`, with a fixed-width inspector that
  is always visible, then an optional footer.

## Reasons

- The toolbar stays in the same place in every section and every state.
- All sections share one layout and one visual language (`HB` tokens).

## Trade-offs

- The inspector cannot collapse, so the list gets less width in a narrow window.
- Behavior that system containers give for free (collapsible sections, `⌘F`
  focus for search) must be built with the shared design controls.

## Reconsider when

- The app adopts a real sidebar for navigation, which changes the toolbar
  layout of every section.
- A section needs a resizable or collapsible inspector that the shared layout
  cannot give.
