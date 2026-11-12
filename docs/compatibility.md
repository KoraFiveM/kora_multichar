---
title: Compatibility
sidebar_position: 11
---

The manifest `provide`s `qb-multicharacter` and `qb-spawn`. Do not run the stock resources alongside it.

The character data endpoints (`setupCharacters`, `GetNumberOfCharacters`, `getSkin`, `loadUserData`, `createCharacter`, `deleteCharacter`, `getOwnedHouses`) are not defined in this resource; the client uses them and `kora_core`'s compatibility layer serves them (verified in `kora_core`'s `compat/server/qb-multicharacter.lua` and `compat/server/qb-spawn.lua`).

## Protocol used

```lua
'qb-multicharacter:server:setupCharacters'
'qb-multicharacter:server:GetNumberOfCharacters'
'qb-multicharacter:server:getSkin'
'qb-multicharacter:server:loadUserData'
'qb-multicharacter:server:createCharacter'
'qb-multicharacter:server:deleteCharacter'
'qb-multicharacter:server:disconnect'
'qb-spawn:server:getOwnedHouses'
'qb-multicharacter:client:chooseChar'
'qb-multicharacter:client:closeNUI'
'qb-multicharacter:client:closeNUIdefault'
'qb-multicharacter:client:spawnLastLocation'
'qb-spawn:client:setupSpawns'
'qb-spawn:client:openUI'
```

This resource itself answers `qb-multicharacter:server:GetServerLogs` (always an empty table) and handles the client events above.

## qb-apartments

`qb-spawn:client:setupSpawns(cData, true, apps)` builds the carousel from the apartment list; choosing one triggers `apartments:server:CreateApartment`. While `qb-apartments` is started, a returning player's `setupSpawns(cData, false)` is first routed through `apartments:client:setupSpawnUI`, with a 5 s timeout back to the normal picker.

## Other resources

- `kora_clothing`: preview appearance and starter outfit (optional).
- `kora_lib`: `Kora.callback`, `Kora.commands`, `Kora.permissions`, `Kora.config`, `Kora.freecam`, `Kora.keybind`, `Kora.nui.copyToClipboard`.
- `kora_theme`: client bridge.
- `kora_voice`: on servers without the `kora_core` bucket export, the fallback bucket change triggers `kora_voice:server:bucketChanged`.
- `kora_qa`: `qa_feature 'tests/*.feature'` declares the Gherkin scenarios in `tests/`.
