import type { Character, SpawnLocation } from "./types";

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

export type SlotTarget = { slot: number; label: string; empty: boolean };

export function slotTarget(characters: Character[], canCreate: boolean, index: number, delta: number): SlotTarget | null {
  const count = characters.length + (canCreate ? 1 : 0);
  if (count <= 1) return null;
  const next = wrapIndex(index, delta, count);
  const character = characters[next];
  return character
    ? { slot: next + 1, label: characterName(character), empty: false }
    : { slot: next + 1, label: "Create New Character", empty: true };
}

/**
 * Which arrival point is selected when a character's list arrives: the one the
 * player already had selected if this character also offers it, otherwise
 * their last location, otherwise the first entry.
 */
export function defaultArrivalId(list: SpawnLocation[], preferred?: string | null): string | null {
  if (preferred && list.some((entry) => entry.id === preferred)) return preferred;
  return list.find((entry) => entry.typeLoc === "current")?.id ?? list[0]?.id ?? null;
}

export function parseArrivalList(value: unknown): SpawnLocation[] {
  const rows = (value && typeof value === "object" ? (value as { locations?: unknown }).locations : null);
  if (!Array.isArray(rows)) return [];
  return rows.flatMap((row): SpawnLocation[] => {
    if (!row || typeof row !== "object") return [];
    const { id, label, description, typeLoc } = row as Record<string, unknown>;
    if (typeof id !== "string" || !id || typeof label !== "string" || !label) return [];
    return [{
      id, label,
      description: typeof description === "string" ? description : undefined,
      typeLoc: typeof typeLoc === "string" ? typeLoc : undefined,
    }];
  });
}

export const SPAWN_PREVIEW_HEADROOM_MS = 3_000;

export const SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS = 90_000;

export const SPAWN_PREVIEW_SUPERSEDED = "superseded";

export function spawnPreviewTimeout(budgetMs: unknown): number {
  if (typeof budgetMs !== "number" || !Number.isFinite(budgetMs) || budgetMs <= 0) {
    return SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS;
  }
  return budgetMs + SPAWN_PREVIEW_HEADROOM_MS;
}

export type EntityKind = "ped" | "vehicle" | "prop";
export type ModelRow = [model: string, label: string];
export type ModelLibrary = Partial<Record<EntityKind, ModelRow[]>>;
export const KIND_LABEL: Record<EntityKind, string> = { ped: "Ped", vehicle: "Vehicle", prop: "Prop" };

const MODEL_NAME = /^[A-Za-z0-9_-]{1,64}$/;

export function parseLibrary(raw: unknown): ModelLibrary {
  const source = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const library: ModelLibrary = {};
  for (const kind of ["ped", "vehicle", "prop"] as const) {
    const rows = Array.isArray(source[kind]) ? source[kind] as unknown[] : [];
    library[kind] = rows.flatMap((row): ModelRow[] => {
      if (!Array.isArray(row) || typeof row[0] !== "string" || !row[0]) return [];
      return [[row[0], typeof row[1] === "string" && row[1] ? row[1] : row[0]]];
    });
  }
  return library;
}

export function filterLibrary(library: ModelLibrary, kind: EntityKind, query: string): { matches: ModelRow[]; custom: string | null } {
  const needle = query.trim().toLowerCase();
  const rows = library[kind] ?? [];
  const matches = needle ? rows.filter(([model, label]) => model.toLowerCase().includes(needle) || label.toLowerCase().includes(needle)) : rows;
  const typed = query.trim();
  const exact = rows.some(([model]) => model.toLowerCase() === needle);
  return { matches, custom: typed && MODEL_NAME.test(typed) && !exact ? typed : null };
}
