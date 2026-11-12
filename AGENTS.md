# kora_multichar agent guide

`kora_multichar` is the Kora cinematic character select, spawn select and scene studio resource; it provides `qb-multicharacter` and `qb-spawn`. Layout: `fxmanifest.lua`, `config.lua` and `scenes.lua` (config and bundled scenes), `shared/` (scene schema, config registration), `server.lua` (modes, buckets, scene registry, commands), `client.lua`, `spawn.lua`, `scene.lua` (runtime), `creator.lua` (scene studio), `fft_hooks.lua`, `web/` (React NUI, compiled to `web/build`), `test/` (offline Lua smoke tests) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and database usage.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
