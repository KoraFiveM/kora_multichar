---
title: Troubleshooting
sidebar_position: 12
---

## Character select never opens

The client waits for a stable player ped and `kora_lib`'s server id, then asks the server to enter selection (up to 8 attempts, 2 s apart, logged as `selection handshake did not answer`). Confirm `kora_lib` and `kora_core` start before this resource. It is skipped if `kora_core:loggedIn` is already true.

## "Scenes could not be loaded from the server"

The scene catalog fetch failed or was empty. Check the server console for `bundled scene ... rejected` lines (a scene failed validation) and that `Config.defaultScene` exists.

## Preview shows a different scene than expected

Highest `priority` wins, ties by id; `Config.defaultScene` is the fallback. Check `job`/`gang` names, grades and `duty`. See [Scenes](./scenes.md).

## Stuck on a loading cover

Run `/closeNUI`. The preview UI times out after `Config.previewWatchdogMs`. If the destination does not stream within `Config.sceneLimits.worldStreamTimeoutMs`, the shot is shown anyway.

## Play does nothing or reports "took too long"

The client waits 20 s for the server to log the character in. Check `kora_core` for errors, and that no other resource intercepts `qb-multicharacter:server:loadUserData`.

## `/logout` or `/multicharscene` refused

Both need the configured permission level and a loaded character, and are refused while a selection, spawn or studio session is active. `/multicharscene` only exists when `Config.creator.enabled` is true.

## Arrival effect not visible to others

Needs `Config.arrival.ptfx.synced = true`, players in the same routing bucket and within `syncRadius`, and at most one effect per 5 s per player.
