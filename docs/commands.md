---
title: "Commands"
sidebar_position: 4
---


# Commands

`/multicharscene` and `/logout` are enabled by default (`Config.creator.enabled` and `Config.logout.enabled` are `true`, both restricted to `admin`) and can be disabled or restricted further in config.lua.

## Built-in commands

### `/multicharscene`

Opens the cinematic scene studio for authoring character-select scenes. Configurable via `Config.creator.command`, `Config.creator.enabled` and `Config.creator.minimumPermission`.

| Field | Details |
| --- | --- |
| Context | In-game · client command (opens a server-gated session) |
| Arguments | No arguments. |
| Access | Requires a loaded character and `Config.creator.minimumPermission` (default `admin`), checked through kora_lib's permission gateway. |

**Example**

```text
/multicharscene
```

**Result**

Enters `creator` mode (own routing bucket), opens a freecam and the Scene Studio NUI.

### `/logout`

Staff-only. Drops the current character but keeps the connection (`exports.kora_core:logout`), returning the player to character select. Refused while a cinematic session (selection/spawn/creator) is already active. Configurable via `Config.logout.command`, `Config.logout.enabled` and `Config.logout.minimumPermission`.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Requires a loaded character and `Config.logout.minimumPermission` (default `admin`). |

**Example**

```text
/logout
```

**Result**

The character is unloaded; the client's `kora_core:loggedIn` watcher sends the player back into character select.

### `/closeNUI`

Stock escape hatch: asks the caller's own client to drop a stuck character-select NUI. Refused while a cinematic session is active (nothing to safely close back to).

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Any player (unrestricted; matches the original qb-multicharacter command). |

**Example**

```text
/closeNUI
```

**Result**

The client closes its own NUI focus and the select screen if one was stuck open.

### `Key: TAB (kora_multichar_creator_toggle)`

While the Scene Studio is open, toggles between the mouse cursor and freecam. It does nothing when the studio is not open.

| Field | Details |
| --- | --- |
| Context | Key binding (rebindable) |
| Arguments | No arguments. |
| Access | Any player with the studio open; the key is rebindable in the FiveM key bindings settings. |

**Example**

```text
Press TAB
```

**Result**

Switches the studio between cursor mode (to use the panels) and freecam mode (to move the camera).

## Permissions and behaviour (from the code)

Commands are registered server-side through `Kora.commands.add`. Staff permission is resolved with `Kora.permissions.hasLevel` using the level order `god`, `admin`, `mod`, `user` and the `kora_core` prefix. A higher level satisfies a lower requirement (a `god` passes an `admin` check). Any mapping that kora_lib's permission gateway resolves to the required level (for example the `kora_core.admin` ace) satisfies it.

| Command | Permission | Registered when |
| --- | --- | --- |
| `/multicharscene` | `Config.creator.minimumPermission` (`admin`) | `Config.creator.enabled`; name from `Config.creator.command`. |
| `/logout` | `Config.logout.minimumPermission` (`admin`) | `Config.logout.enabled`; name from `Config.logout.command`. |
| `/closeNUI` | everyone | Always. |

`/logout` refuses when the player has no character or while a session is open, and otherwise calls `exports.kora_core:logout`. Returning to selection is driven by the `kora_core:loggedIn` state bag turning `false` on the client, not by an event from this resource, so any logout path (admin tool, character delete of a live handle) lands in selection.
