import { FormEvent, type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import {
  Box, Camera, CheckCircle2, ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Clapperboard, Copy,
  Crosshair, LoaderCircle, LogOut, MapPin, MousePointer2,
  Play, Plus, Save, Sparkles, Trash2, X,
} from "lucide-react";
import { fetchNui } from "./nui";
import {
  characterName, isValidBirthdate, money, normalizeCharacters, slotTarget, SPAWN_PREVIEW_SUPERSEDED, spawnPreviewTimeout, wrapIndex,
} from "./lib";
import type { Character, NuiMessage, SceneDraft, SpawnLocation } from "./types";

type Stage = "hidden" | "characters" | "spawn" | "creator";
type CreatorPayload = { draft?: SceneDraft; scenes?: Record<string, SceneDraft>; cursor?: boolean; error?: string };
type UiSettings = {
  brandName: string; showNewSlotBadge: boolean; nationalities: string[]; defaultNationality: string; allowFreeTextNationality: boolean;
  profile: ProfileText;
};
type ProfileCard = "career" | "affiliation" | "finances" | "birthDate" | "nationality" | "citizenId";
type ProfileText = Record<ProfileCard, { label: string; description: string }>;
const DEFAULT_PROFILE: ProfileText = {
  career: { label: "Career", description: "" },
  affiliation: { label: "Affiliation", description: "" },
  finances: { label: "Finances", description: "" },
  birthDate: { label: "Birth date", description: "" },
  nationality: { label: "Nationality", description: "Place of origin" },
  citizenId: { label: "Citizen ID", description: "" },
};
const DEFAULT_UI: UiSettings = { brandName: "Kora", showNewSlotBadge: false, nationalities: [], defaultNationality: "", allowFreeTextNationality: false, profile: DEFAULT_PROFILE };

function parseProfile(raw: unknown): ProfileText {
  const source = (raw && typeof raw === "object" ? raw : {}) as Record<string, { label?: unknown; description?: unknown } | undefined>;
  const profile = { ...DEFAULT_PROFILE };
  for (const key of Object.keys(DEFAULT_PROFILE) as ProfileCard[]) {
    const entry = source[key];
    const label = typeof entry?.label === "string" ? entry.label.trim() : "";
    profile[key] = {
      label: label || DEFAULT_PROFILE[key].label,
      description: typeof entry?.description === "string" ? entry.description.trim() : DEFAULT_PROFILE[key].description,
    };
  }
  return profile;
}

function parseUi(raw: unknown): UiSettings {
  const ui = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const nationalities = Array.isArray(ui.nationalities)
    ? Array.from(new Set(ui.nationalities.filter((entry): entry is string => typeof entry === "string").map((entry) => entry.trim()).filter(Boolean)))
    : [];
  const brandName = typeof ui.brandName === "string" ? ui.brandName.trim() : "";
  return {
    brandName: brandName || DEFAULT_UI.brandName,
    showNewSlotBadge: ui.showNewSlotBadge === true,
    nationalities,
    defaultNationality: typeof ui.defaultNationality === "string" ? ui.defaultNationality.trim() : "",
    allowFreeTextNationality: ui.allowFreeTextNationality === true,
    profile: parseProfile(ui.profile),
  };
}

type SpawnHints = { previous: string; next: string; preview: string; flying: string; spawn: string };
const DEFAULT_SPAWN_HINTS: SpawnHints = { previous: "Previous", next: "Next", preview: "Preview location", flying: "Flying to location…", spawn: "Spawn" };
type SpawnPayload = { locations?: SpawnLocation[]; visible?: boolean; previewBudgetMs?: number; switchCooldownMs?: number; settleMs?: number; lockWhileMoving?: boolean; hints?: Partial<SpawnHints> };

function parseSpawnHints(value: Partial<SpawnHints> | undefined): SpawnHints {
  const pick = (key: keyof SpawnHints) => (typeof value?.[key] === "string" && value[key]!.trim() ? value[key]! : DEFAULT_SPAWN_HINTS[key]);
  return { previous: pick("previous"), next: pick("next"), preview: pick("preview"), flying: pick("flying"), spawn: pick("spawn") };
}

function roleLabel(role: Character["job"], fallback: string) {
  return role?.label || role?.name || fallback;
}

function gradeLabel(role: Character["job"]) {
  return role?.grade?.name || `Grade ${role?.grade?.level ?? 0}`;
}

function characterInitials(character: Character) {
  const first = character.charinfo?.firstname?.trim().charAt(0) || "";
  const last = character.charinfo?.lastname?.trim().charAt(0) || "";
  return `${first}${last}`.toUpperCase() || "?";
}

export function App() {
  const [stage, setStage] = useState<Stage>("hidden");
  const [characters, setCharacters] = useState<Character[]>([]);
  const [maxCharacters, setMaxCharacters] = useState(5);
  const [index, setIndex] = useState(0);
  const [details, setDetails] = useState(false);
  const [creating, setCreating] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [disconnecting, setDisconnecting] = useState(false);
  const [confirmDisconnect, setConfirmDisconnect] = useState(true);
  const [busy, setBusy] = useState(false);
  const [previewing, setPreviewing] = useState(false);
  // From the show payload; 0 disables the watchdog.
  const [previewWatchdogMs, setPreviewWatchdogMs] = useState(0);
  const [closeCreateOnBackdrop, setCloseCreateOnBackdrop] = useState(false);
  const [confirmDiscard, setConfirmDiscard] = useState(true);
  const [uiSettings, setUiSettings] = useState<UiSettings>(DEFAULT_UI);
  // Kept here, not in the dialog, so closing and reopening restores typed values.
  const [createDraft, setCreateDraft] = useState<CreateDraft>(() => emptyCreateDraft(DEFAULT_UI));
  // What the spawn preview is currently waiting on, for the cover's subtitle.
  const [previewStage, setPreviewStage] = useState<string | null>(null);
  const [spawnTraveling, setSpawnTraveling] = useState(false);
  const spawnCameraReady = useRef(false);
  // Bumped every time Lua reports a preview camera live. The focus effect
  // captures its value on entry so it can tell "my preview never came up" from
  // "my preview came up ages ago and the callback is still pending" -- only the
  // first of those is worth a timeout toast.
  const spawnPreviewLiveSeq = useRef(0);
  // A ref, not state: the budget arrives with the spawn payload before the
  // first preview starts, and making it a dependency of the preview effect
  // would restart an in-flight preview every time Lua re-sent it.
  const spawnPreviewBudget = useRef<number | null>(null);
  // Config.spawnSelect: minimum gap between location switches, enforced for
  // buttons, arrow keys and A/D alike in move(). A ref for the same reason.
  const spawnSwitchCooldown = useRef(800);
  const lastSpawnSwitch = useRef(0);
  // Config.spawnSelect.settleMs: browsing only changes the label; the camera
  // flight starts once the player has stayed on a location this long.
  const spawnSettle = useRef(1000);
  const spawnSettleTimer = useRef(0);
  // Config.spawnSelect.lockWhileMoving: no switching until the camera arrives.
  const [spawnLock, setSpawnLock] = useState(true);
  // The location the camera is showing or flying to, so browsing back to it
  // does not start a flight to where the camera already is.
  const spawnCameraTarget = useRef<string | null>(null);
  const [spawnHints, setSpawnHints] = useState<SpawnHints>(DEFAULT_SPAWN_HINTS);
  const [sceneName, setSceneName] = useState("");
  const [toast, setToast] = useState<string | null>(null);
  const [spawns, setSpawns] = useState<SpawnLocation[]>([]);
  const [spawnIndex, setSpawnIndex] = useState(0);
  const [creatorDraft, setCreatorDraft] = useState<SceneDraft | null>(null);
  const [creatorScenes, setCreatorScenes] = useState<Record<string, SceneDraft>>({});
  const [creatorCursor, setCreatorCursor] = useState(true);
  const [exported, setExported] = useState<string | null>(null);

  const canCreate = characters.length < maxCharacters;
  const slideCount = characters.length + (canCreate ? 1 : 0);
  const character = index < characters.length ? characters[index] : null;
  const spawn = spawns[spawnIndex] ?? null;

  useEffect(() => {
    const listener = (event: MessageEvent<NuiMessage>) => {
      const { action, data } = event.data || {};
      if (action === "multichar:show") {
        const payload = data as { characters?: unknown; maxCharacters?: number; previewWatchdogMs?: number; ui?: Record<string, unknown> & { closeCreateOnBackdrop?: boolean; confirmDiscardOnClose?: boolean; confirmDisconnect?: boolean } };
        setPreviewWatchdogMs(Math.max(0, Number(payload?.previewWatchdogMs) || 0));
        setCloseCreateOnBackdrop(payload?.ui?.closeCreateOnBackdrop === true);
        setConfirmDiscard(payload?.ui?.confirmDiscardOnClose !== false);
        setConfirmDisconnect(payload?.ui?.confirmDisconnect !== false);
        setDisconnecting(false);
        const nextUi = parseUi(payload?.ui);
        setUiSettings(nextUi);
        setCreateDraft(emptyCreateDraft(nextUi));
        setCharacters(normalizeCharacters(payload?.characters));
        setMaxCharacters(Number(payload?.maxCharacters) || 5);
        spawnCameraReady.current = false;
        setIndex(0); setStage("characters"); setBusy(false); setDetails(false); setCreating(false); setDeleting(false); setPreviewing(true); setSpawnTraveling(false);
      } else if (action === "multichar:close") setStage("hidden");
      else if (action === "multichar:error") { setToast(String(data || "Something went wrong.")); setBusy(false); }
      else if (action === "multichar:previewLoading") setPreviewing(true);
      else if (action === "multichar:previewReady") {
        const payload = data as { scene?: string; error?: string; ok?: boolean };
        setPreviewing(false); setSceneName(payload.scene || "");
        if (payload.ok === false && payload.error) setToast(payload.error);
      } else if (action === "multichar:spawn:previewLive") {
        // Camera is live: drop the cover now rather than waiting for the focus
        // callback, which only answers once the whole preview has settled
        // (over a minute worst case). The callback still decides whether a
        // failure is worth a toast.
        spawnCameraReady.current = true;
        spawnPreviewLiveSeq.current += 1;
        setPreviewing(false);
        setSpawnTraveling(false);
        setPreviewStage(null);
      } else if (action === "multichar:spawn:previewStage") {
        // Cosmetic: names what the preview is waiting on so a long world
        // stream reads as busy rather than frozen.
        setPreviewStage((data as { stage?: string })?.stage ?? null);
      } else if (action === "multichar:spawn:locations") {
        const payload = data as SpawnPayload;
        spawnPreviewBudget.current = payload?.previewBudgetMs ?? spawnPreviewBudget.current;
        setSpawns(Array.isArray(payload?.locations) ? payload.locations : []); setSpawnIndex(0);
      } else if (action === "multichar:spawn:show" && (data as SpawnPayload)?.visible) {
        spawnPreviewBudget.current = (data as SpawnPayload)?.previewBudgetMs ?? spawnPreviewBudget.current;
        const cooldown = Number((data as SpawnPayload)?.switchCooldownMs);
        if (Number.isFinite(cooldown)) spawnSwitchCooldown.current = Math.max(0, cooldown);
        const settle = Number((data as SpawnPayload)?.settleMs);
        if (Number.isFinite(settle)) spawnSettle.current = Math.max(0, settle);
        setSpawnLock((data as SpawnPayload)?.lockWhileMoving !== false);
        lastSpawnSwitch.current = 0;
        spawnCameraTarget.current = null;
        setSpawnHints(parseSpawnHints((data as SpawnPayload)?.hints));
        spawnCameraReady.current = false;
        setStage("spawn"); setBusy(false); setSpawnIndex(0); setPreviewing(true); setSpawnTraveling(false);
      } else if (action === "multichar:creator:show") {
        const payload = data as CreatorPayload;
        setCreatorDraft(payload.draft ?? null); setCreatorScenes(payload.scenes ?? {}); setCreatorCursor(payload.cursor !== false); setStage("creator");
      } else if (action === "multichar:creator:state") {
        const payload = data as CreatorPayload;
        if (payload.draft) setCreatorDraft(payload.draft);
        if (payload.scenes) setCreatorScenes(payload.scenes);
        if (typeof payload.cursor === "boolean") setCreatorCursor(payload.cursor);
        if (payload.error) setToast(payload.error);
      } else if (action === "multichar:creator:cursor") setCreatorCursor((data as { cursor?: boolean })?.cursor === true);
      else if (action === "multichar:creator:close") setStage("hidden");
      else if (action === "multichar:creator:exported") {
        setExported((data as { registerCall?: boolean })?.registerCall ? "Registration call copied" : "Config copied");
        window.setTimeout(() => setExported(null), 2400);
      } else if (action === "multichar:creator:validated") {
        setExported(String((data as { message?: string })?.message || "Scene is valid"));
        window.setTimeout(() => setExported(null), 2400);
      }
    };
    window.addEventListener("message", listener);
    return () => window.removeEventListener("message", listener);
  }, []);

  useEffect(() => {
    if (stage !== "characters" || creating || deleting || slideCount === 0) return;
    setPreviewing(true);
    const timer = window.setTimeout(() => {
      if (character) fetchNui("multichar:preview", { citizenid: character.citizenid });
      else fetchNui("multichar:createPreview", { gender: 0 });
    }, 120);
    return () => window.clearTimeout(timer);
  }, [stage, index, character?.citizenid, creating, deleting, slideCount]);

  // Safety net: a preview that never reports back must not hold the cover forever.
  useEffect(() => {
    if (!previewing || stage !== "characters" || !previewWatchdogMs) return;
    const timer = window.setTimeout(() => {
      setPreviewing(false);
      setToast("The scene preview took too long to load.");
    }, previewWatchdogMs);
    return () => window.clearTimeout(timer);
  }, [previewing, stage, index, previewWatchdogMs]);

  useEffect(() => {
    if (stage !== "spawn" || !spawn) return;
    let active = true;
    const initial = !spawnCameraReady.current;
    // Browsing back to the place the camera already shows needs no flight.
    if (!initial && spawnCameraTarget.current === spawn.id) return;
    let timeoutId = 0;
    const start = () => {
      spawnSettleTimer.current = 0;
      spawnCameraTarget.current = spawn.id;
      const liveSeqAtStart = spawnPreviewLiveSeq.current;
      if (initial) setPreviewing(true);
      else setSpawnTraveling(true);
      // A new preview has nothing to report yet; a stale stage line from the
      // previous one would name the wrong location.
      setPreviewStage(null);
      const timeout = new Promise<null>((resolve) => {
        timeoutId = window.setTimeout(() => resolve(null), spawnPreviewTimeout(spawnPreviewBudget.current));
      });
      Promise.race([fetchNui<{ ok?: boolean; reason?: string }>("multichar:spawn:focus", { id: spawn.id }), timeout]).then((result) => {
        if (!active) return;
        if (result === null) {
          // Silent if the camera for THIS preview already went live: the player
          // has been looking at the place for the whole budget, and telling them
          // it timed out would describe something they can see is not true. Only
          // a preview that never came up is worth the toast.
          if (spawnPreviewLiveSeq.current === liveSeqAtStart) {
            setToast("Arrival preview timed out. You can still spawn here.");
          }
          return;
        }
        if (result?.ok === false) {
          // A superseded preview is the player picking somewhere else, or the
          // scene being torn down under it -- expected, and silent. Only a
          // camera or streaming failure is worth interrupting them for.
          if (result.reason !== SPAWN_PREVIEW_SUPERSEDED) {
            setToast("That arrival could not be previewed. You can still spawn here.");
          }
          return;
        }
        spawnCameraReady.current = true;
      }).catch(() => {
        if (active) setToast("That arrival could not be previewed. You can still spawn here.");
      }).finally(() => {
        window.clearTimeout(timeoutId);
        if (!active) return;
        // The preview is visual only. Whether it fails or its callback is
        // interrupted, always release the selector so a player cannot remain
        // indefinitely on “Scouting your arrival”.
        if (initial) setPreviewing(false);
        setSpawnTraveling(false);
      });
    };
    // The first shot comes up at once; after that the camera waits for the
    // player to settle, and every further switch restarts the wait (cleanup).
    if (spawnCameraTarget.current === null || spawnSettle.current <= 0) start();
    else spawnSettleTimer.current = window.setTimeout(start, spawnSettle.current);
    const settleTimer = spawnSettleTimer.current;
    return () => { active = false; window.clearTimeout(settleTimer); };
  }, [stage, spawn?.id]);

  const move = (delta: number) => {
    if (stage === "characters" && !creating && !deleting && slideCount) {
      // With a single slide there is nothing to preview; starting one would
      // never be answered because the preview effect only runs on index change.
      const next = wrapIndex(index, delta, slideCount);
      if (next === index) return;
      setPreviewing(true); setIndex(next); setDetails(false);
    } else if (stage === "spawn" && spawns.length && !busy && !(spawnLock && (previewing || spawnTraveling))) {
      const now = Date.now();
      if (now - lastSpawnSwitch.current < spawnSwitchCooldown.current) return;
      lastSpawnSwitch.current = now;
      setSpawnIndex((value) => wrapIndex(value, delta, spawns.length));
    }
  };

  const accept = () => {
    if (busy || previewing || spawnTraveling) return;
    if (stage === "characters" && !creating && !deleting) {
      if (!character) setCreating(true);
      else { setBusy(true); fetchNui("multichar:select", { citizenid: character.citizenid }); }
    } else if (stage === "spawn" && spawn) {
      // Spawning during the settle wait must not start a flight afterwards.
      window.clearTimeout(spawnSettleTimer.current);
      spawnSettleTimer.current = 0;
      setBusy(true); fetchNui("multichar:spawn:choose", { id: spawn.id });
    }
  };

  useEffect(() => {
    const keyboard = (event: KeyboardEvent) => {
      if (stage === "hidden" || stage === "creator" || creating || deleting || ["INPUT", "TEXTAREA", "SELECT"].includes((event.target as HTMLElement)?.tagName)) return;
      if (event.key === "ArrowLeft" || event.key.toLowerCase() === "a") move(-1);
      else if (event.key === "ArrowRight" || event.key.toLowerCase() === "d") move(1);
      else if (event.key === "Enter") accept();
      else if (event.key === "Escape" && stage === "spawn") fetchNui("multichar:spawn:exit");
    };
    window.addEventListener("keydown", keyboard);
    return () => window.removeEventListener("keydown", keyboard);
  });

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 6000);
    return () => window.clearTimeout(timer);
  }, [toast]);

  if (stage === "hidden") return null;

  return (
    <div className={`app stage-${stage}`}>
      {toast && <div className="toast"><span>{toast}</span><button aria-label="Dismiss" onClick={() => setToast(null)}><X size={15} /></button></div>}
      {stage === "characters" && (
        <CharacterScreen
          characters={characters} character={character} index={index} count={slideCount} canCreate={canCreate}
          brand={uiSettings.brandName} showNewBadge={uiSettings.showNewSlotBadge} profile={uiSettings.profile}
          details={details} previewing={previewing} sceneName={sceneName} busy={busy}
          onMove={move} onAccept={accept} onDetails={() => setDetails((value) => !value)}
          onCreate={() => setCreating(true)} onDelete={() => setDeleting(true)}
          onDisconnect={() => (confirmDisconnect ? setDisconnecting(true) : fetchNui("multichar:disconnect"))}
        />
      )}
      {stage === "spawn" && <SpawnScreen location={spawn} locations={spawns} index={spawnIndex} count={spawns.length} busy={busy} previewing={previewing} traveling={spawnTraveling} locked={spawnLock && (previewing || spawnTraveling)} hints={spawnHints} onMove={move} onAccept={accept} />}
      {stage === "creator" && creatorDraft && (
        <CreatorScreen key={creatorDraft.id} draft={creatorDraft} scenes={creatorScenes} cursor={creatorCursor} exported={exported} />
      )}
      {previewing && !creating && (stage === "characters" || stage === "spawn") && <SceneTransition stage={stage} previewStage={previewStage} />}
      {creating && <CreateDialog ui={uiSettings} draft={createDraft} onDraft={setCreateDraft} closeOnBackdrop={closeCreateOnBackdrop} confirmDiscard={confirmDiscard} onClose={() => setCreating(false)} onBusy={setBusy} />}
      {disconnecting && <DisconnectDialog onClose={() => setDisconnecting(false)} />}
      {deleting && character && <DeleteDialog character={character} onClose={() => setDeleting(false)} onBusy={setBusy} />}
    </div>
  );
}

const PREVIEW_STAGE_TEXT: Record<string, string> = {
  streaming: "Streaming the area around your arrival point",
};

function SceneTransition({ stage, previewStage }: { stage: "characters" | "spawn"; previewStage?: string | null }) {
  // The subtitle names what is actually being waited on when Lua has told us.
  // A world stream can legitimately take tens of seconds, and a fixed
  // "streaming the world" line for all of it is indistinguishable from a hung
  // panel -- which is how this screen got reported as stuck.
  const detail = (previewStage && PREVIEW_STAGE_TEXT[previewStage])
    || "Streaming the world and finding a clear camera angle";

  return <div className="scene-transition" role="status" aria-live="polite">
    <div className="transition-content">
      <h2>{stage === "spawn" ? "Scouting your arrival" : "Setting your scene"}</h2>
      <p>{detail}</p>
      <div className="transition-progress"><i /></div>
    </div>
  </div>;
}

// Every slot, in order, down the right edge. Display only: the arrows and the
// keyboard are what move the selection, so it never takes the pointer.
function SlotRail({ labels, selected }: { labels: string[]; selected: number }) {
  return <ul className="slot-rail" data-testid="slot-rail" aria-hidden>
    {labels.map((label, i) => <li key={`${i}-${label}`} className={i === selected ? "on" : undefined}>{label}</li>)}
  </ul>;
}

function SlotNav({ position, total, prevLabel, nextLabel, prevTitle, nextTitle, disabled, onMove }: {
  position: number; total: number; prevLabel: string; nextLabel: string; prevTitle?: string; nextTitle?: string; disabled: boolean; onMove: (delta: number) => void;
}) {
  return <span className="third-nav">
    <button className="nav-button" disabled={disabled} onClick={() => onMove(-1)} aria-label={prevLabel} title={prevTitle}><ChevronLeft size={18} /></button>
    <span className="profile-count">{position} of {total}</span>
    <button className="nav-button" disabled={disabled} onClick={() => onMove(1)} aria-label={nextLabel} title={nextTitle}><ChevronRight size={18} /></button>
  </span>;
}

function CharacterScreen(props: {
  characters: Character[]; character: Character | null; index: number; count: number; canCreate: boolean;
  brand: string; showNewBadge: boolean; profile: ProfileText;
  details: boolean; previewing: boolean; sceneName: string; busy: boolean;
  onMove: (delta: number) => void; onAccept: () => void; onDetails: () => void; onCreate: () => void; onDelete: () => void; onDisconnect: () => void;
}) {
  const { character } = props;
  const job = character ? roleLabel(character.job, "Civilian") : "";
  const gang = character?.gang?.name && character.gang.name !== "none" ? character.gang : null;
  const prev = slotTarget(props.characters, props.canCreate, props.index, -1);
  const next = slotTarget(props.characters, props.canCreate, props.index, 1);
  const targetLabel = (target: typeof prev) => target ? `Character ${target.slot}: ${target.label}` : undefined;
  const slots = [...props.characters.map(characterName), ...(props.canCreate ? ["New character"] : [])];
  return <>
    <span className="brand-mark corner-brand">{props.brand}</span>
    <button className="quiet-button corner-action" aria-label="Disconnect" onClick={props.onDisconnect}><LogOut size={15} />Disconnect</button>
    {props.details && character && <Dossier character={character} profile={props.profile} onClose={props.onDetails} onDelete={props.onDelete} />}
    <section className={`lower-third${character ? "" : " new-character"}`}>
      <p className="third-kicker">{props.previewing ? "Loading scene…" : (props.sceneName || "Cinematic preview")}</p>
      <h2>{character ? characterName(character) : "Create character"}{!character && props.showNewBadge && <span className="new-slot-chip">New</span>}</h2>
      <p className="third-meta">{character ? [job, gradeLabel(character.job), gang ? roleLabel(gang, gang.name || "Affiliation") : null].filter(Boolean).join(" · ") : "Use this slot to begin a new story in Los Santos."}</p>
      <div className="third-actions">
        <button className="button primary" disabled={props.busy || props.previewing} onClick={props.onAccept}>
          {props.busy ? <LoaderCircle className="spin" size={16} /> : null}
          {character ? "Continue" : "Create"}
        </button>
        {character && <button className="button ghost profile-button" aria-expanded={props.details} onClick={props.onDetails}>Profile</button>}
        <SlotNav position={props.index + 1} total={props.count} disabled={props.count <= 1} onMove={props.onMove}
          prevLabel={prev ? `Previous, ${targetLabel(prev)}` : "Previous"} nextLabel={next ? `Next, ${targetLabel(next)}` : "Next"} prevTitle={targetLabel(prev)} nextTitle={targetLabel(next)} />
      </div>
    </section>
    <SlotRail labels={slots} selected={props.index} />
    <div className="key-hints"><kbd>←</kbd><kbd>→</kbd><span>Browse</span><kbd>Enter</kbd><span>Continue</span></div>
  </>;
}

function Dossier({ character, profile, onClose, onDelete }: { character: Character; profile: ProfileText; onClose: () => void; onDelete: () => void }) {
  const gang = character.gang?.name && character.gang.name !== "none" ? character.gang : null;
  const card = (key: ProfileCard, value: string, detail?: string) => {
    const text = detail === undefined ? profile[key].description : detail;
    return <div><span><small>{profile[key].label}</small><strong>{value}</strong>{text && <em>{text}</em>}</span></div>;
  };
  return <aside className="dossier panel">
    <div className="dossier-heading">
      <div><h3>{characterName(character)}</h3><p>{roleLabel(character.job, "Civilian")} · {gradeLabel(character.job)}</p></div>
      <button className="icon-button" aria-label="Close profile" onClick={onClose}><X size={16} /></button>
    </div>
    <div className="detail-list">
      {card("career", roleLabel(character.job, "Civilian"), gradeLabel(character.job))}
      {card("affiliation", gang ? roleLabel(gang, gang.name || "Gang") : "None", gang ? gradeLabel(gang) : "Independent")}
      {card("finances", `${money(character.money?.bank)} bank`, `${money(character.money?.cash)} cash`)}
      {card("birthDate", character.charinfo?.birthdate || "Unknown")}
      {card("nationality", character.charinfo?.nationality || "Unknown")}
      {card("citizenId", character.citizenid)}
    </div>
    <button className="danger-link" onClick={onDelete}>Delete character</button>
  </aside>;
}

type CreateField = "firstname" | "lastname" | "birthdate" | "nationality";
type CreateErrors = Partial<Record<CreateField, string>>;

// The NUI has no locale table; every UI string is a literal, so the
// validation messages live together here for easy translation.
const CREATE_MESSAGES = {
  firstnameRequired: "Enter a first name.",
  lastnameRequired: "Enter a last name.",
  nameLength: "Names must be between 1 and 24 characters.",
  birthdate: "Enter a real, non-future birth date.",
  nationalityList: "Choose a nationality from the list.",
  nationalityLength: "Nationality must be between 2 and 32 characters.",
};

type CreateDraft = { firstname: string; lastname: string; birthdate: string; nationality: string; gender: number };

// The configured default wins when it is selectable (or when free text is
// allowed); otherwise a list-backed form starts on its first entry.
function emptyCreateDraft(ui: UiSettings): CreateDraft {
  const list = ui.nationalities;
  const nationality = list.length === 0 ? (ui.defaultNationality || "USA")
    : list.includes(ui.defaultNationality) || (ui.allowFreeTextNationality && ui.defaultNationality) ? ui.defaultNationality : list[0];
  return { firstname: "", lastname: "", birthdate: "2000-01-01", nationality, gender: 0 };
}

function CreateDialog({ ui, draft, onDraft, closeOnBackdrop, confirmDiscard, onClose, onBusy }: { ui: UiSettings; draft: CreateDraft; onDraft: (draft: CreateDraft) => void; closeOnBackdrop: boolean; confirmDiscard: boolean; onClose: () => void; onBusy: (value: boolean) => void }) {
  const [errors, setErrors] = useState<CreateErrors>({});
  const formRef = useRef<HTMLFormElement>(null);
  const EMPTY_CREATE_DRAFT = useMemo(() => emptyCreateDraft(ui), [ui]);
  const nationalityList = ui.nationalities;
  const useDropdown = nationalityList.length > 0 && !ui.allowFreeTextNationality;
  const dirty = draft.firstname !== "" || draft.lastname !== "" || draft.birthdate !== EMPTY_CREATE_DRAFT.birthdate || draft.nationality !== EMPTY_CREATE_DRAFT.nationality;
  const setField = (field: keyof CreateDraft, value: string | number) => {
    if (field in errors) setErrors(({ [field as CreateField]: _cleared, ...rest }) => rest);
    onDraft({ ...draft, [field]: value });
  };
  // X, Cancel and Escape are deliberate, so they ask before discarding typed data.
  // The question is drawn in the page: the game's browser does not show
  // window.confirm() and answers "no", which made X, Cancel and Escape do
  // nothing as soon as a name was typed.
  const [asking, setAsking] = useState(false);
  const requestClose = () => {
    if (dirty && confirmDiscard && !asking) { setAsking(true); return; }
    if (dirty) onDraft(EMPTY_CREATE_DRAFT);
    onClose();
  };
  const keepEditing = () => setAsking(false);
  // A restored female draft needs the matching model back on screen.
  useEffect(() => { if (draft.gender === 1) fetchNui("multichar:createPreview", { gender: 1 }); }, []);
  const closeRef = useRef(requestClose);
  closeRef.current = requestClose;
  const askingRef = useRef(asking);
  askingRef.current = asking;
  const keepEditingRef = useRef(keepEditing);
  keepEditingRef.current = keepEditing;
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key !== "Escape") return; if (askingRef.current) keepEditingRef.current(); else closeRef.current(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const firstname = draft.firstname.trim();
    const lastname = draft.lastname.trim();
    const birthdate = draft.birthdate;
    const nationality = draft.nationality.trim();
    const gender = draft.gender;
    const found: CreateErrors = {};
    if (!firstname) found.firstname = CREATE_MESSAGES.firstnameRequired;
    else if (firstname.length > 24) found.firstname = CREATE_MESSAGES.nameLength;
    if (!lastname) found.lastname = CREATE_MESSAGES.lastnameRequired;
    else if (lastname.length > 24) found.lastname = CREATE_MESSAGES.nameLength;
    if (!isValidBirthdate(birthdate)) found.birthdate = CREATE_MESSAGES.birthdate;
    if (useDropdown && !nationalityList.includes(nationality)) found.nationality = CREATE_MESSAGES.nationalityList;
    else if (nationality.length < 2 || nationality.length > 32) found.nationality = CREATE_MESSAGES.nationalityLength;
    const first = (["firstname", "lastname", "birthdate", "nationality"] as const).find((field) => found[field]);
    if (first) {
      setErrors(found);
      (formRef.current?.elements.namedItem(first) as HTMLElement | null)?.focus();
      return;
    }
    onBusy(true); onDraft(EMPTY_CREATE_DRAFT); onClose();
    fetchNui("multichar:create", { firstname, lastname, birthdate, nationality, gender });
  };
  return <div className="modal-layer"><div className="modal-backdrop" onClick={closeOnBackdrop ? onClose : undefined} /><form ref={formRef} noValidate className="modal panel create-modal" onSubmit={submit}>
    <div className="panel-heading"><h3>Create character</h3><button type="button" className="icon-button" aria-label="Close" onClick={requestClose}><X size={16} /></button></div>
    <p className="modal-copy">Build the identity. You will customize appearance immediately after spawning.</p>
    <div className="field-grid">
      <div className="field"><label>First name<input name="firstname" autoFocus maxLength={24} required aria-invalid={!!errors.firstname} aria-describedby={errors.firstname ? "create-firstname-error" : undefined} value={draft.firstname} onChange={(event) => setField("firstname", event.target.value)} /></label><FieldError id="create-firstname-error" message={errors.firstname} /></div>
      <div className="field"><label>Last name<input name="lastname" maxLength={24} required aria-invalid={!!errors.lastname} aria-describedby={errors.lastname ? "create-lastname-error" : undefined} value={draft.lastname} onChange={(event) => setField("lastname", event.target.value)} /></label><FieldError id="create-lastname-error" message={errors.lastname} /></div>
    </div>
    <div className="field-grid">
      <div className="field"><label>Birth date<input name="birthdate" type="date" max={new Date().toISOString().slice(0, 10)} required aria-invalid={!!errors.birthdate} aria-describedby={errors.birthdate ? "create-birthdate-error" : undefined} value={draft.birthdate} onChange={(event) => setField("birthdate", event.target.value)} /></label><FieldError id="create-birthdate-error" message={errors.birthdate} /></div>
      <div className="field"><label>Nationality{useDropdown
        ? <select name="nationality" required aria-invalid={!!errors.nationality} aria-describedby={errors.nationality ? "create-nationality-error" : undefined} value={draft.nationality} onChange={(event) => setField("nationality", event.target.value)}>{(nationalityList.includes(draft.nationality) ? nationalityList : [draft.nationality, ...nationalityList]).map((entry) => <option key={entry} value={entry}>{entry}</option>)}</select>
        : <><input name="nationality" maxLength={32} required aria-invalid={!!errors.nationality} aria-describedby={errors.nationality ? "create-nationality-error" : undefined} list={nationalityList.length ? "nationality-options" : undefined} value={draft.nationality} onChange={(event) => setField("nationality", event.target.value)} />{nationalityList.length > 0 && <datalist id="nationality-options">{nationalityList.map((entry) => <option key={entry} value={entry} />)}</datalist>}</>}</label><FieldError id="create-nationality-error" message={errors.nationality} /></div>
    </div>
    <div className="segmented" aria-label="Body model"><button type="button" className={draft.gender === 0 ? "active" : ""} onClick={() => { setField("gender", 0); fetchNui("multichar:createPreview", { gender: 0 }); }}>Male</button><button type="button" className={draft.gender === 1 ? "active" : ""} onClick={() => { setField("gender", 1); fetchNui("multichar:createPreview", { gender: 1 }); }}>Female</button></div>
    {asking && <div className="discard-prompt" role="alertdialog" aria-label="Discard details"><p>Discard the identity details you entered?</p><div className="modal-actions"><button type="button" className="button ghost" onClick={keepEditing}>Keep editing</button><button type="button" className="button destructive" onClick={requestClose}>Discard</button></div></div>}
    {!asking && <div className="modal-actions"><button type="button" className="button ghost" onClick={requestClose}>Cancel</button><button className="button primary">Create identity</button></div>}
  </form></div>;
}

function FieldError({ id, message }: { id: string; message?: string }) {
  return message ? <small id={id} className="field-error" role="alert">{message}</small> : null;
}

function DisconnectDialog({ onClose }: { onClose: () => void }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return <div className="modal-layer"><div className="modal-backdrop" onClick={onClose} /><div className="modal panel disconnect-modal" role="alertdialog" aria-label="Disconnect">
    <div className="panel-heading"><h3>Disconnect?</h3><button className="icon-button" aria-label="Close" onClick={onClose}><X size={16} /></button></div>
    <p className="modal-copy">You will leave the server and return to the main menu.</p>
    <div className="modal-actions"><button className="button ghost" onClick={onClose}>Cancel</button><button className="button destructive" autoFocus onClick={() => { onClose(); fetchNui("multichar:disconnect"); }}>Disconnect</button></div>
  </div></div>;
}

function DeleteDialog({ character, onClose, onBusy }: { character: Character; onClose: () => void; onBusy: (value: boolean) => void }) {
  const name = characterName(character); const [typed, setTyped] = useState("");
  return <div className="modal-layer"><div className="modal-backdrop" onClick={onClose} /><div className="modal panel delete-modal">
    <div className="panel-heading"><h3>Delete {name}?</h3><button className="icon-button" aria-label="Close" onClick={onClose}><X size={16} /></button></div>
    <p className="modal-copy">This cannot be undone. Type <strong>{name}</strong> to confirm.</p>
    <label>Character name<input value={typed} onChange={(event) => setTyped(event.target.value)} autoFocus /></label>
    <div className="modal-actions"><button className="button ghost" onClick={onClose}>Cancel</button><button className="button destructive" disabled={typed !== name} onClick={() => { onBusy(true); onClose(); fetchNui("multichar:delete", { citizenid: character.citizenid }); }}>Delete forever</button></div>
  </div></div>;
}

function SpawnScreen({ location, locations, index, count, busy, previewing, traveling, locked, hints, onMove, onAccept }: { location: SpawnLocation | null; locations: SpawnLocation[]; index: number; count: number; busy: boolean; previewing: boolean; traveling: boolean; locked: boolean; hints: SpawnHints; onMove: (delta: number) => void; onAccept: () => void }) {
  return <>
    <header className="corner-title"><h1>Where do you wake up?</h1></header>
    <section className="lower-third spawn-third">
      {traveling
        ? <p className="third-kicker" role="status">Flying to <strong>{location?.label}</strong></p>
        : <p className="third-kicker">Arrival point</p>}
      <h2>{location?.label || "Loading locations"}</h2>
      <p className="third-meta">{location?.description || "Preparing a safe arrival point…"}</p>
      <div className="third-actions">
        <button className="button primary" disabled={!location || busy || previewing || traveling} onClick={onAccept}>{busy ? <LoaderCircle className="spin" size={16} /> : null}Spawn here</button>
        <SlotNav position={count ? index + 1 : 0} total={count} disabled={count <= 1 || busy || locked} onMove={onMove} prevLabel="Previous location" nextLabel="Next location" />
      </div>
    </section>
    <SlotRail labels={locations.map((entry) => entry.label)} selected={index} />
    <div className="key-hints"><kbd>A</kbd><kbd>←</kbd><span>{hints.previous}</span><kbd>D</kbd><kbd>→</kbd><span>{hints.next}</span><span>{traveling ? hints.flying : hints.preview}</span><kbd>Enter</kbd><span>{hints.spawn}</span></div>
  </>;
}

const creatorAction = (action: string, payload: unknown = {}) => fetchNui("multichar:creator:action", { action, payload });

function CreatorScreen({ draft, scenes, cursor, exported }: { draft: SceneDraft; scenes: Record<string, SceneDraft>; cursor: boolean; exported: string | null }) {
  const [cueText, setCueText] = useState('{"at":5200,"type":"camera","camera":"establishing","transitionMs":2400}');
  const [selectorText, setSelectorText] = useState(JSON.stringify(draft.selectors ?? [], null, 2));
  const [scrub, setScrub] = useState(0);
  useEffect(() => setSelectorText(JSON.stringify(draft.selectors ?? [], null, 2)), [draft.id, draft.selectors]);
  const sceneOptions = useMemo(() => Object.keys(scenes).sort(), [scenes]);
  return <div className="creator-shell">
    <header className="creator-top panel">
      <div><span className="eyebrow">Cinematic tools</span><h2>Scene Studio</h2></div>
      <select value={scenes[draft.id] ? draft.id : ""} onChange={(event) => event.target.value && creatorAction("load", { id: event.target.value })}><option value="">Unsaved draft</option>{sceneOptions.map((id) => <option key={id} value={id}>{scenes[id].label} · {id}</option>)}</select>
      <button className="button ghost" onClick={() => creatorAction("new")}><Plus size={15} />New</button>
      <button className="button ghost" onClick={() => creatorAction("duplicate")}><Copy size={15} />Duplicate</button>
      <button className={`button ${cursor ? "primary" : "ghost"}`} onClick={() => creatorAction("toggleMode")}><MousePointer2 size={15} />{cursor ? "Cursor" : "Freecam"}</button>
      <button className="icon-button" onClick={() => creatorAction("close")}><X /></button>
    </header>
    <aside className="creator-left panel">
      <CreatorSection title="Scene" icon={<Clapperboard size={15} />}>
        <form onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); try { creatorAction("metadata", { id: form.get("id"), label: form.get("label"), priority: Number(form.get("priority")), selectors: JSON.parse(selectorText) }); } catch { /* Lua returns useful validation on preview */ } }}>
          <label>ID<input name="id" defaultValue={draft.id} /></label><label>Label<input name="label" defaultValue={draft.label} /></label><label>Priority<input name="priority" type="number" defaultValue={draft.priority} /></label>
          <label>Selectors JSON<textarea rows={4} value={selectorText} onChange={(event) => setSelectorText(event.target.value)} /></label><button className="mini-button"><Save size={13} />Apply metadata</button>
        </form>
      </CreatorSection>
      <CreatorSection title="Environment" icon={<Sparkles size={15} />}>
        <form onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); const strength = String(form.get("strength") ?? ""); creatorAction("environment", { hour: Number(form.get("hour")), minute: Number(form.get("minute")), weather: form.get("weather"), timecycle: form.get("timecycle") || undefined, strength: strength === "" ? undefined : Number(strength) }); }}>
          <div className="field-grid"><label>Hour<input name="hour" type="number" min="0" max="23" defaultValue={Number(draft.environment?.hour ?? 18)} /></label><label>Minute<input name="minute" type="number" min="0" max="59" defaultValue={Number(draft.environment?.minute ?? 0)} /></label></div>
          <label>Weather<input name="weather" defaultValue={String(draft.environment?.weather ?? "CLEAR")} /></label><label>Timecycle<input name="timecycle" defaultValue={String(draft.environment?.timecycle ?? "")} /></label><label>Strength<input name="strength" type="number" step="0.05" min="0" max="1" defaultValue={Number(draft.environment?.strength ?? 0)} /></label><button className="mini-button"><Save size={13} />Apply environment</button>
        </form>
      </CreatorSection>
      <button className="wide-tool" onClick={() => creatorAction("setAnchor")}><MapPin size={15} />Set anchor at crosshair</button>
      <button className="wide-tool" onClick={() => creatorAction("placeCharacter")}><Crosshair size={15} />Place character at crosshair</button>
    </aside>
    <aside className="creator-right panel">
      <CreatorSection title={`Entities · ${draft.entities.length}`} icon={<Box size={15} />}>
        <div className="object-list">{draft.entities.map((entity, index) => <div className="object-editor" key={entity.id}>
          <div className="object-row"><span><strong>{entity.id}</strong><small>{entity.type} · {String(entity.model)}</small></span><div className="row-tools">
            <button aria-label={`Move ${entity.id} up`} disabled={index === 0} onClick={() => creatorAction("reorderEntity", { index: index + 1, delta: -1 })}><ChevronUp size={13} /></button>
            <button aria-label={`Move ${entity.id} down`} disabled={index === draft.entities.length - 1} onClick={() => creatorAction("reorderEntity", { index: index + 1, delta: 1 })}><ChevronDown size={13} /></button>
            <button aria-label={`Delete ${entity.id}`} onClick={() => creatorAction("removeEntity", { id: entity.id })}><Trash2 size={13} /></button>
          </div></div>
          <JsonEditor label="Edit entity data" value={entity} onSave={(value) => creatorAction("replaceEntity", { originalId: entity.id, value })} />
        </div>)}</div>
        <form className="inline-add" onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); creatorAction("addEntity", { id: form.get("id"), type: form.get("type"), model: form.get("model") }); }}>
          <input name="id" placeholder="unique_id" required /><select name="type"><option value="ped">NPC</option><option value="vehicle">Vehicle</option><option value="prop">Prop</option></select><input name="model" placeholder="model name" required /><button className="mini-button"><Crosshair size={13} />Place</button>
        </form>
      </CreatorSection>
      <CreatorSection title={`Cameras · ${draft.cameras.length}`} icon={<Camera size={15} />}>
        <div className="object-list">{draft.cameras.map((camera, index) => <div className="object-editor" key={camera.id}>
          <div className="object-row"><span><strong>{camera.id}</strong><small>FOV {String(camera.fov ?? 45)}</small></span><div className="row-tools">
            <button aria-label={`Move ${camera.id} up`} disabled={index === 0} onClick={() => creatorAction("reorderCamera", { index: index + 1, delta: -1 })}><ChevronUp size={13} /></button>
            <button aria-label={`Move ${camera.id} down`} disabled={index === draft.cameras.length - 1} onClick={() => creatorAction("reorderCamera", { index: index + 1, delta: 1 })}><ChevronDown size={13} /></button>
            <button aria-label={`Delete ${camera.id}`} disabled={draft.cameras.length <= 1} onClick={() => creatorAction("removeCamera", { id: camera.id })}><Trash2 size={13} /></button>
          </div></div>
          <JsonEditor label="Edit camera data" value={camera} onSave={(value) => creatorAction("replaceCamera", { index: index + 1, value })} />
        </div>)}</div>
        <form className="inline-add" onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); creatorAction("captureCamera", { id: form.get("id"), fov: Number(form.get("fov")), transitionMs: 900 }); }}><input name="id" placeholder="shot_id" required /><input name="fov" type="number" min="10" max="100" defaultValue="45" /><button className="mini-button"><Camera size={13} />Capture</button></form>
      </CreatorSection>
    </aside>
    <section className="timeline panel">
      <div className="timeline-heading"><span><Clapperboard size={15} /><strong>Timeline</strong></span><label>Duration <input type="number" defaultValue={draft.timeline.durationMs} onBlur={(event) => creatorAction("timeline", { durationMs: Number(event.target.value), loop: draft.timeline.loop })} /></label><label className="check"><input type="checkbox" checked={draft.timeline.loop} onChange={(event) => creatorAction("timeline", { durationMs: draft.timeline.durationMs, loop: event.target.checked })} />Loop</label></div>
      <input className="scrubber" type="range" min="0" max={draft.timeline.durationMs || 1} value={scrub} onChange={(event) => { const at = Number(event.target.value); setScrub(at); creatorAction("scrub", { at }); }} />
      <div className="cue-list">{draft.timeline.cues.map((cue, i) => <div className="cue-editor" key={`${String(cue.type)}-${i}`}>
        <div className="cue"><b>{Number(cue.at ?? 0) / 1000}s</b><span>{String(cue.type)}</span><div className="row-tools">
          <button aria-label="Move cue up" disabled={i === 0} onClick={() => creatorAction("reorderCue", { index: i + 1, delta: -1 })}><ChevronUp size={12} /></button>
          <button aria-label="Move cue down" disabled={i === draft.timeline.cues.length - 1} onClick={() => creatorAction("reorderCue", { index: i + 1, delta: 1 })}><ChevronDown size={12} /></button>
          <button aria-label="Delete cue" onClick={() => creatorAction("removeCue", { index: i + 1 })}><X size={12} /></button>
        </div></div>
        <JsonEditor label="Edit cue data" value={cue} onSave={(value) => creatorAction("replaceCue", { index: i + 1, value })} />
      </div>)}</div>
      <div className="cue-add"><input value={cueText} onChange={(event) => setCueText(event.target.value)} /><button className="mini-button" onClick={() => { try { creatorAction("addCue", JSON.parse(cueText)); } catch { /* keep editable */ } }}><Plus size={13} />Add cue JSON</button></div>
    </section>
    <footer className="creator-actions panel"><button className="button ghost" onClick={() => creatorAction("validate")}><CheckCircle2 size={15} />Validate</button><button className="button ghost" onClick={() => creatorAction("preview")}><Play size={15} />Play timeline</button><button className="button ghost" onClick={() => creatorAction("exportRegister")}><Copy size={15} />Copy registration</button><button className="button primary" onClick={() => creatorAction("exportConfig")}><Copy size={15} />Copy config</button>{exported && <span className="export-toast">{exported}</span>}</footer>
  </div>;
}

function CreatorSection({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) {
  return <section className="creator-section"><h3>{icon}{title}</h3>{children}</section>;
}

function JsonEditor({ label, value, onSave }: { label: string; value: unknown; onSave: (value: Record<string, unknown>) => void }) {
  const serialized = JSON.stringify(value, null, 2);
  const [text, setText] = useState(serialized);
  const [error, setError] = useState(false);
  useEffect(() => { setText(serialized); setError(false); }, [serialized]);
  return <details className="json-editor"><summary>{label}</summary><textarea rows={7} value={text} onChange={(event) => setText(event.target.value)} />{error && <small>Enter a valid JSON object.</small>}<button className="mini-button" onClick={() => { try { const parsed = JSON.parse(text); if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") throw new Error(); setError(false); onSave(parsed); } catch { setError(true); } }}><Save size={12} />Apply JSON</button></details>;
}
