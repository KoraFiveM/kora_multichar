export type Grade = { name?: string; level?: number };
export type Role = { name?: string; label?: string; grade?: Grade; onduty?: boolean };
export type Character = {
  citizenid: string;
  cid?: number;
  name?: string;
  charinfo?: { firstname?: string; lastname?: string; birthdate?: string; gender?: number; nationality?: string };
  money?: { cash?: number; bank?: number };
  job?: Role;
  gang?: Role;
};

export type SpawnLocation = {
  id: string;
  label: string;
  description?: string;
  typeLoc?: string;
};

export type SceneDraft = {
  id: string;
  label: string;
  priority: number;
  selectors: unknown[];
  environment?: Record<string, unknown>;
  character: Record<string, unknown>;
  entities: Array<{ id: string; type: string; model: string | number; [key: string]: unknown }>;
  cameras: Array<{ id: string; [key: string]: unknown }>;
  timeline: { durationMs: number; loop: boolean; cues: Array<Record<string, unknown>> };
  [key: string]: unknown;
};

export type NuiMessage = { action?: string; data?: unknown };
