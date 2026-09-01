import type { Character } from "./types";

export function isCharacter(value: unknown): value is Character {
  return !!value && typeof value === "object" && typeof (value as Character).citizenid === "string";
}

export function normalizeCharacters(value: unknown): Character[] {
  if (Array.isArray(value)) return value.filter(isCharacter);
  if (!value || typeof value !== "object") return [];
  const values = Object.values(value);
  return values.every(isCharacter) ? values : [];
}

export function characterName(character: Character): string {
  const first = character.charinfo?.firstname ?? "";
  const last = character.charinfo?.lastname ?? "";
  return `${first} ${last}`.trim() || character.name || (character.cid ? `Character ${character.cid}` : "Unnamed Character");
}

export function money(value: unknown): string {
  return `$${Math.max(0, typeof value === "number" ? value : 0).toLocaleString()}`;
}

export function isValidBirthdate(value: string, today = new Date()): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  const valid = parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day;
  const current = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  return valid && parsed.getTime() <= current;
}

export function wrapIndex(index: number, delta: number, count: number): number {
  return count ? (index + delta + count) % count : 0;
}
