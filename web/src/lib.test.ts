import { describe, expect, it } from "vitest";
import { characterName, isValidBirthdate, normalizeCharacters, wrapIndex } from "./lib";

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
