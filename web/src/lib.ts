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

// Spawn previews are raced against a timeout so the selector can never sit on
// "Scouting your arrival" forever. The budget comes from Lua
// (SceneRuntime.spawnPreviewBudgetMs), which derives it from the flight and
// world-streaming config the preview actually obeys -- a constant here would
// have to track four config values it cannot see, which is how the previous
// hardcoded 15s ended up reporting healthy previews as failures.
export const SPAWN_PREVIEW_HEADROOM_MS = 3_000;

// Used only when the payload carries no budget at all, e.g. a Lua side that
// predates the field. Generous on purpose: its whole job is to release the
// selector eventually, not to be accurate.
export const SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS = 90_000;

// SceneRuntime.PREVIEW_SUPERSEDED. A preview the player abandoned by picking
// somewhere else is not a failure and must not raise a toast.
export const SPAWN_PREVIEW_SUPERSEDED = "superseded";

export function spawnPreviewTimeout(budgetMs: unknown): number {
  if (typeof budgetMs !== "number" || !Number.isFinite(budgetMs) || budgetMs <= 0) {
    return SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS;
  }
  return budgetMs + SPAWN_PREVIEW_HEADROOM_MS;
}
