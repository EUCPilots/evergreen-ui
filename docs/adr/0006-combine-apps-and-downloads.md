---
status: accepted
---

# Combine Apps and downloads

The Apps and Download views are one workflow, so combine them into Apps and
remove the separate Download view. Keep batching across applications with a
collapsible queue tray that is hidden when empty, appears collapsed after items
are queued, expands when downloads start, and remembers its resized height.
Show pending and running queue counts on the Apps navigation item; let users
add selected artifacts to the queue or queue and start them immediately. Reduce
Apps clutter by grouping catalog refresh and Evergreen maintenance commands in
a labeled menu, keeping artifact details in the grid with URI actions in a row
context menu, and showing the download destination in the queue tray.

Move folder editing to Settings, where Browse saves changes immediately for
both download and library folders; retain the Library view's existing path
controls. Restore a saved `Download` startup view as `Apps`, and reject
`Download` as a new `StartupView` value.
