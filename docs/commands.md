---
title: Commands
sidebar_position: 6
---

Commands are registered server-side through `Kora.commands.add`. Staff permission is resolved with `Kora.permissions.hasLevel` using the level order `god`, `admin`, `mod`, `user` and the `kora_core` prefix. A higher level satisfies a lower requirement (a `god` passes an `admin` check). Any mapping that kora_lib's permission gateway resolves to the required level (for example the `kora_core.admin` ace) satisfies it.

| Command | Permission | Description |
| --- | --- | --- |
| `/multicharscene` | `Config.creator.minimumPermission` (`admin`) | Opens the scene studio. Requires a loaded character. Registered only when `Config.creator.enabled`. The name comes from `Config.creator.command`. |
| `/logout` | `Config.logout.minimumPermission` (`admin`) | Drops the staff member's character and returns to character select. Registered only when `Config.logout.enabled`. The name comes from `Config.logout.command`. |
| `/closeNUI` | everyone | Closes a stuck character screen. Refused while a selection, spawn or studio session is open. |

`/logout` refuses when the player has no character or while a session is open, and otherwise calls `exports.kora_core:logout`. Returning to selection is driven by the `kora_core:loggedIn` state bag turning `false` on the client, not by an event from this resource, so any logout path (admin tool, character delete of a live handle) lands in selection.

## Key binding

`kora_multichar_creator_toggle` (default `TAB`, "Scene Studio: Toggle Cursor / Freecam") switches the studio between inspector and freecam.
