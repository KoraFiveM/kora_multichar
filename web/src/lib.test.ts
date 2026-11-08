import { describe, expect, it } from "vitest";
import {
  characterName, filterLibrary, isValidBirthdate, normalizeCharacters, parseLibrary, SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS,
  SPAWN_PREVIEW_HEADROOM_MS, slotTarget, spawnPreviewTimeout, wrapIndex,
} from "./lib";

describe("arrow targets", () => {
  const jane = { citizenid: "A", charinfo: { firstname: "Jane", lastname: "Doe" } };
  const bob = { citizenid: "B", charinfo: { firstname: "Bob", lastname: "Ray" } };
  it("names the neighbouring character or the free slot, wrapping around", () => {
    expect(slotTarget([jane, bob], true, 0, 1)).toEqual({ slot: 2, label: "Bob Ray", empty: false });
    expect(slotTarget([jane, bob], true, 0, -1)).toEqual({ slot: 3, label: "Create New Character", empty: true });
    expect(slotTarget([jane, bob], false, 1, 1)).toEqual({ slot: 1, label: "Jane Doe", empty: false });
  });
  it("has no target when there is only one slot", () => {
    expect(slotTarget([jane], false, 0, 1)).toBeNull();
    expect(slotTarget([], true, 0, -1)).toBeNull();
  });
});

describe("character payloads", () => {
  it("normalizes Lua empty objects and rejects malformed objects", () => {
    expect(normalizeCharacters({})).toEqual([]);
    expect(normalizeCharacters({ one: { citizenid: "A" } })).toHaveLength(1);
    expect(normalizeCharacters({ state: "pending" })).toEqual([]);
  });
  it("uses identity names and safe fallbacks", () => {
    expect(characterName({ citizenid: "A", charinfo: { firstname: "Jane", lastname: "Doe" } })).toBe("Jane Doe");
    expect(characterName({ citizenid: "B", cid: 2 })).toBe("Character 2");
  });
});

describe("identity and navigation", () => {
  it("validates real, non-future calendar dates", () => {
    const today = new Date("2026-08-31T00:00:00Z");
    expect(isValidBirthdate("2000-02-29", today)).toBe(true);
    expect(isValidBirthdate("2001-02-29", today)).toBe(false);
    expect(isValidBirthdate("2099-01-01", today)).toBe(false);
  });
  it("wraps carousel indexes", () => {
    expect(wrapIndex(0, -1, 4)).toBe(3);
    expect(wrapIndex(3, 1, 4)).toBe(0);
  });
});

describe("spawn preview timeout", () => {
  it("derives the timeout from the budget Lua reports, never from a constant of its own", () => {
    expect(spawnPreviewTimeout(73_250)).toBe(73_250 + SPAWN_PREVIEW_HEADROOM_MS);
    // The whole point: a longer Lua budget produces a longer timeout with no
    // edit here. The old hardcoded 15s could not do that, which is why a slow
    // world stream looked like a failed preview.
    expect(spawnPreviewTimeout(120_000)).toBeGreaterThan(spawnPreviewTimeout(73_250));
    expect(spawnPreviewTimeout(73_250)).toBeGreaterThan(73_250);
  });

  it("falls back to a bounded timeout for a missing or nonsensical budget", () => {
    for (const value of [undefined, null, 0, -1, NaN, Infinity, "30000"]) {
      expect(spawnPreviewTimeout(value)).toBe(SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS);
    }
  });
});

describe("studio model picker", () => {
  const library = parseLibrary({ ped: [["s_m_y_cop_01", "Police officer"], ["a_m_y_skater_01", "Skater"], [7, "bad"]], prop: [] });
  it("keeps well-formed rows and defaults missing kinds to empty", () => {
    expect(library.ped).toEqual([["s_m_y_cop_01", "Police officer"], ["a_m_y_skater_01", "Skater"]]);
    expect(library.vehicle).toEqual([]);
    expect(parseLibrary(undefined).ped).toEqual([]);
  });
  it("searches model and label, and offers a typed model name only when it is not an exact entry", () => {
    expect(filterLibrary(library, "ped", "").matches).toHaveLength(2);
    expect(filterLibrary(library, "ped", "skat")).toEqual({ matches: [["a_m_y_skater_01", "Skater"]], custom: "skat" });
    expect(filterLibrary(library, "ped", "S_M_Y_COP_01").custom).toBeNull();
    expect(filterLibrary(library, "ped", "not a model!").custom).toBeNull();
  });
});
