import { FormEvent, type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import {
  Box, Briefcase, CalendarDays, Camera, CheckCircle2, ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Clapperboard, Copy,
  Crosshair, Fingerprint, Flag, Info, LoaderCircle, LogOut, MapPin, MousePointer2,
  Plane, Play, Plus, Save, Sparkles, Trash2, UserPlus, Users, Wallet, X,
} from "lucide-react";
import { fetchNui } from "./nui";
import {
  characterName, isValidBirthdate, money, normalizeCharacters, SPAWN_PREVIEW_SUPERSEDED, spawnPreviewTimeout, wrapIndex,
} from "./lib";
import type { Character, NuiMessage, SceneDraft, SpawnLocation } from "./types";

type Stage = "hidden" | "characters" | "spawn" | "creator";
type CreatorPayload = { draft?: SceneDraft; scenes?: Record<string, SceneDraft>; cursor?: boolean; error?: string };
type UiSettings = {
  brandName: string; showNewSlotBadge: boolean; nationalities: string[]; defaultNationality: string; allowFreeTextNationality: boolean;
};
const DEFAULT_UI: UiSettings = { brandName: "Kora", showNewSlotBadge: false, nationalities: [], defaultNationality: "", allowFreeTextNationality: false };

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
  };
}

type SpawnPayload = { locations?: SpawnLocation[]; visible?: boolean; previewBudgetMs?: number };

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
        const payload = data as { characters?: unknown; maxCharacters?: number; previewWatchdogMs?: number; ui?: Record<string, unknown> & { closeCreateOnBackdrop?: boolean; confirmDiscardOnClose?: boolean } };
        setPreviewWatchdogMs(Math.max(0, Number(payload?.previewWatchdogMs) || 0));
        setCloseCreateOnBackdrop(payload?.ui?.closeCreateOnBackdrop === true);
        setConfirmDiscard(payload?.ui?.confirmDiscardOnClose !== false);
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
        // The spawn camera is live and looking at the place. Drop the cover
        // NOW rather than waiting for the focus callback to answer: that
        // answer only arrives once the whole preview has settled, and the NUI
        // races it against a timeout derived from the real worst case (over a
        // minute). Waiting for it sat the player on a loading panel with a
        // finished camera behind it -- the "stuck on Scouting your arrival"
        // report. The callback still resolves later and still decides whether
        // a failure is worth a toast.
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
    const liveSeqAtStart = spawnPreviewLiveSeq.current;
    const initial = !spawnCameraReady.current;
    if (initial) setPreviewing(true);
    else setSpawnTraveling(true);
    // A new preview has nothing to report yet; a stale stage line from the
    // previous one would name the wrong location.
    setPreviewStage(null);
    let timeoutId = 0;
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
    return () => { active = false; };
  }, [stage, spawn?.id]);

  const move = (delta: number) => {
    if (stage === "characters" && !creating && !deleting && slideCount) {
      // With a single slide there is nothing to preview; starting one would
      // never be answered because the preview effect only runs on index change.
      const next = wrapIndex(index, delta, slideCount);
      if (next === index) return;
      setPreviewing(true); setIndex(next); setDetails(false);
    } else if (stage === "spawn" && spawns.length && !busy) {
      setSpawnIndex((value) => wrapIndex(value, delta, spawns.length));
    }
  };

  const accept = () => {
    if (busy || previewing || spawnTraveling) return;
    if (stage === "characters" && !creating && !deleting) {
      if (!character) setCreating(true);
      else { setBusy(true); fetchNui("multichar:select", { citizenid: character.citizenid }); }
    } else if (stage === "spawn" && spawn) {
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
      {toast && <div className="toast"><Sparkles size={16} /><span>{toast}</span><button onClick={() => setToast(null)}><X size={15} /></button></div>}
      {stage === "characters" && (
        <CharacterScreen
          characters={characters} character={character} index={index} count={slideCount} canCreate={canCreate}
          brand={uiSettings.brandName} showNewBadge={uiSettings.showNewSlotBadge}
          details={details} previewing={previewing} sceneName={sceneName} busy={busy}
          onMove={move} onAccept={accept} onDetails={() => setDetails((value) => !value)}
          onCreate={() => setCreating(true)} onDelete={() => setDeleting(true)}
        />
      )}
      {stage === "spawn" && <SpawnScreen location={spawn} index={spawnIndex} count={spawns.length} busy={busy} previewing={previewing} traveling={spawnTraveling} onMove={move} onAccept={accept} />}
      {stage === "creator" && creatorDraft && (
        <CreatorScreen key={creatorDraft.id} draft={creatorDraft} scenes={creatorScenes} cursor={creatorCursor} exported={exported} />
      )}
      {previewing && !creating && (stage === "characters" || stage === "spawn") && <SceneTransition stage={stage} previewStage={previewStage} brand={uiSettings.brandName} />}
      {creating && <CreateDialog ui={uiSettings} draft={createDraft} onDraft={setCreateDraft} closeOnBackdrop={closeCreateOnBackdrop} confirmDiscard={confirmDiscard} onClose={() => setCreating(false)} onBusy={setBusy} />}
      {deleting && character && <DeleteDialog character={character} onClose={() => setDeleting(false)} onBusy={setBusy} />}
    </div>
  );
}

const PREVIEW_STAGE_TEXT: Record<string, string> = {
  streaming: "Streaming the area around your arrival point",
};

function SceneTransition({ stage, previewStage, brand }: { stage: "characters" | "spawn"; previewStage?: string | null; brand: string }) {
  // The subtitle names what is actually being waited on when Lua has told us.
  // A world stream can legitimately take tens of seconds, and a fixed
  // "streaming the world" line for all of it is indistinguishable from a hung
  // panel -- which is how this screen got reported as stuck.
  const detail = (previewStage && PREVIEW_STAGE_TEXT[previewStage])
    || "Streaming the world and finding a clear camera angle";

  return <div className="scene-transition" role="status" aria-live="polite">
    <div className="transition-frame" aria-hidden><span /><span /><span /></div>
    <div className="transition-content">
      <span className="transition-brand">{brand} · CINEMATIC</span>
      <div className="transition-pulse"><Clapperboard size={20} /></div>
      <h2>{stage === "spawn" ? "Scouting your arrival" : "Setting your scene"}</h2>
      <p>{detail}</p>
      <div className="transition-progress"><i /></div>
    </div>
  </div>;
}

function CharacterScreen(props: {
  characters: Character[]; character: Character | null; index: number; count: number; canCreate: boolean;
  brand: string; showNewBadge: boolean;
  details: boolean; previewing: boolean; sceneName: string; busy: boolean;
  onMove: (delta: number) => void; onAccept: () => void; onDetails: () => void; onCreate: () => void; onDelete: () => void;
}) {
  const { character } = props;
  const job = character ? roleLabel(character.job, "Civilian") : "Create a new story";
  const gang = character?.gang?.name && character.gang.name !== "none" ? character.gang : null;
  const position = String(props.index + 1).padStart(2, "0");
  const total = String(props.characters.length).padStart(2, "0");
  return <>
    <header className="topbar">
      <div><span className="eyebrow brand-mark">{props.brand}</span><h1>Choose your story</h1></div>
      <button className="icon-button" aria-label="Disconnect" onClick={() => fetchNui("multichar:disconnect")}><LogOut size={18} /></button>
    </header>
    <div className="scene-label"><Clapperboard size={13} />{props.previewing ? "Loading scene…" : (props.sceneName || "Cinematic preview")}</div>
    {props.details && character && <Dossier character={character} onClose={props.onDetails} onDelete={props.onDelete} />}
    <section className="carousel-shell">
      <button className="nav-button" disabled={props.count <= 1} onClick={() => props.onMove(-1)} aria-label="Previous"><ChevronLeft /></button>
      <div className={`identity-card character-card${character ? "" : " new-character-card"}`}>
        <div className="identity-mark" aria-hidden>{character ? characterInitials(character) : <UserPlus size={22} />}</div>
        <div className="identity-copy">
          <div className="identity-kicker">
            <span className="eyebrow">{character ? "SELECTED IDENTITY" : "AVAILABLE CHARACTER SLOT"}</span>
            {character ? <span className="profile-count"><strong>{position}</strong><i>/</i>{total}</span> : props.showNewBadge ? <span className="new-slot-chip">NEW</span> : null}
          </div>
          <h2>{character ? characterName(character) : "Create character"}</h2>
          {character ? <div className="identity-meta">
            <span className="career-label"><Briefcase size={13} />{job}</span>
            <span className="rank-chip">{gradeLabel(character.job)}</span>
            {gang && <span className="affiliation-chip"><Users size={12} />{roleLabel(gang, gang.name || "Affiliation")}</span>}
          </div> : <p>Use this slot to begin a new story in Los Santos.</p>}
        </div>
        <div className="identity-actions">
          {character && <button className="button ghost profile-button" aria-expanded={props.details} onClick={props.onDetails}><Info size={16} />Profile</button>}
          <button className="button primary" disabled={props.busy || props.previewing} onClick={props.onAccept}>
            {props.busy ? <LoaderCircle className="spin" size={17} /> : character ? <Play size={17} fill="currentColor" /> : <UserPlus size={17} />}
            {character ? "Continue" : "Create"}
          </button>
        </div>
      </div>
      <button className="nav-button" disabled={props.count <= 1} onClick={() => props.onMove(1)} aria-label="Next"><ChevronRight /></button>
    </section>
    <div className="key-hints"><kbd>←</kbd><kbd>→</kbd><span>Browse</span><kbd>Enter</kbd><span>Continue</span></div>
  </>;
}

function Dossier({ character, onClose, onDelete }: { character: Character; onClose: () => void; onDelete: () => void }) {
  const gang = character.gang?.name && character.gang.name !== "none" ? character.gang : null;
  return <aside className="dossier panel">
    <div className="dossier-heading">
      <div className="identity-mark compact" aria-hidden>{characterInitials(character)}</div>
      <div><span className="eyebrow">CHARACTER PROFILE</span><h3>{characterName(character)}</h3><p>{roleLabel(character.job, "Civilian")} · {gradeLabel(character.job)}</p></div>
      <button className="icon-button" aria-label="Close profile" onClick={onClose}><X size={16} /></button>
    </div>
    <div className="detail-list">
      <div><Briefcase /><span><small>Career</small><strong>{roleLabel(character.job, "Civilian")}</strong><em>{gradeLabel(character.job)}</em></span></div>
      <div><Users /><span><small>Affiliation</small><strong>{gang ? roleLabel(gang, gang.name || "Gang") : "None"}</strong><em>{gang ? gradeLabel(gang) : "Independent"}</em></span></div>
      <div><Wallet /><span><small>Finances</small><strong>{money(character.money?.bank)} bank</strong><em>{money(character.money?.cash)} cash</em></span></div>
      <div><CalendarDays /><span><small>Birth date</small><strong>{character.charinfo?.birthdate || "Unknown"}</strong><em>Registered identity</em></span></div>
      <div><Flag /><span><small>Nationality</small><strong>{character.charinfo?.nationality || "Unknown"}</strong><em>Place of origin</em></span></div>
      <div><Fingerprint /><span><small>Citizen record</small><strong>{character.citizenid}</strong><em>Permanent identifier</em></span></div>
    </div>
    <button className="danger-link" onClick={onDelete}><Trash2 size={14} />Delete character</button>
  </aside>;
}

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
  const [error, setError] = useState("");
  const EMPTY_CREATE_DRAFT = useMemo(() => emptyCreateDraft(ui), [ui]);
  const nationalityList = ui.nationalities;
  const useDropdown = nationalityList.length > 0 && !ui.allowFreeTextNationality;
  const dirty = draft.firstname !== "" || draft.lastname !== "" || draft.birthdate !== EMPTY_CREATE_DRAFT.birthdate || draft.nationality !== EMPTY_CREATE_DRAFT.nationality;
  const setField = (field: keyof CreateDraft, value: string | number) => onDraft({ ...draft, [field]: value });
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
    if (!firstname || firstname.length > 24 || !lastname || lastname.length > 24) { setError("Names must be between 1 and 24 characters."); return; }
    if (!isValidBirthdate(birthdate)) { setError("Enter a real, non-future birth date."); return; }
    if (useDropdown && !nationalityList.includes(nationality)) { setError("Choose a nationality from the list."); return; }
    if (nationality.length < 2 || nationality.length > 32) { setError("Nationality must be between 2 and 32 characters."); return; }
    onBusy(true); onDraft(EMPTY_CREATE_DRAFT); onClose();
    fetchNui("multichar:create", { firstname, lastname, birthdate, nationality, gender });
  };
  return <div className="modal-layer"><div className="modal-backdrop" onClick={closeOnBackdrop ? onClose : undefined} /><form className="modal panel create-modal" onSubmit={submit}>
    <div className="panel-heading"><div><span className="eyebrow">NEW IDENTITY</span><h3>Create character</h3></div><button type="button" className="icon-button" aria-label="Close" onClick={requestClose}><X size={16} /></button></div>
    <p className="modal-copy">Build the identity. You will customize appearance immediately after spawning.</p>
    <div className="field-grid"><label>First name<input name="firstname" autoFocus maxLength={24} required value={draft.firstname} onChange={(event) => setField("firstname", event.target.value)} /></label><label>Last name<input name="lastname" maxLength={24} required value={draft.lastname} onChange={(event) => setField("lastname", event.target.value)} /></label></div>
    <div className="field-grid"><label>Birth date<input name="birthdate" type="date" max={new Date().toISOString().slice(0, 10)} required value={draft.birthdate} onChange={(event) => setField("birthdate", event.target.value)} /></label><label>Nationality{useDropdown
      ? <select name="nationality" required value={draft.nationality} onChange={(event) => setField("nationality", event.target.value)}>{(nationalityList.includes(draft.nationality) ? nationalityList : [draft.nationality, ...nationalityList]).map((entry) => <option key={entry} value={entry}>{entry}</option>)}</select>
      : <><input name="nationality" maxLength={32} required list={nationalityList.length ? "nationality-options" : undefined} value={draft.nationality} onChange={(event) => setField("nationality", event.target.value)} />{nationalityList.length > 0 && <datalist id="nationality-options">{nationalityList.map((entry) => <option key={entry} value={entry} />)}</datalist>}</>}</label></div>
    <div className="segmented" aria-label="Body model"><button type="button" className={draft.gender === 0 ? "active" : ""} onClick={() => { setField("gender", 0); fetchNui("multichar:createPreview", { gender: 0 }); }}>Male</button><button type="button" className={draft.gender === 1 ? "active" : ""} onClick={() => { setField("gender", 1); fetchNui("multichar:createPreview", { gender: 1 }); }}>Female</button></div>
    {error && <p className="form-error">{error}</p>}
    {asking && <div className="discard-prompt" role="alertdialog" aria-label="Discard details"><p>Discard the identity details you entered?</p><div className="modal-actions"><button type="button" className="button ghost" onClick={keepEditing}>Keep editing</button><button type="button" className="button destructive" onClick={requestClose}>Discard</button></div></div>}
    {!asking && <div className="modal-actions"><button type="button" className="button ghost" onClick={requestClose}>Cancel</button><button className="button primary"><UserPlus size={16} />Create identity</button></div>}
  </form></div>;
}

function DeleteDialog({ character, onClose, onBusy }: { character: Character; onClose: () => void; onBusy: (value: boolean) => void }) {
  const name = characterName(character); const [typed, setTyped] = useState("");
  return <div className="modal-layer"><div className="modal-backdrop" onClick={onClose} /><div className="modal panel delete-modal">
    <div className="modal-rail danger" /><div className="panel-heading"><div><span className="eyebrow">PERMANENT ACTION</span><h3>Delete {name}?</h3></div><button className="icon-button" onClick={onClose}><X size={16} /></button></div>
    <p className="modal-copy">This cannot be undone. Type <strong>{name}</strong> to confirm.</p>
    <label>Character name<input value={typed} onChange={(event) => setTyped(event.target.value)} autoFocus /></label>
    <div className="modal-actions"><button className="button ghost" onClick={onClose}>Cancel</button><button className="button destructive" disabled={typed !== name} onClick={() => { onBusy(true); onClose(); fetchNui("multichar:delete", { citizenid: character.citizenid }); }}><Trash2 size={16} />Delete forever</button></div>
  </div></div>;
}

function SpawnScreen({ location, index, count, busy, previewing, traveling, onMove, onAccept }: { location: SpawnLocation | null; index: number; count: number; busy: boolean; previewing: boolean; traveling: boolean; onMove: (delta: number) => void; onAccept: () => void }) {
  return <>
    <header className="topbar"><div><span className="eyebrow">ARRIVAL</span><h1>Where do you wake up?</h1></div><span className="mandatory-chip">Selection required</span></header>
    {traveling && <div className="travel-indicator" role="status"><Plane size={15} /><span>Flying to <strong>{location?.label}</strong></span></div>}
    <section className="carousel-shell spawn-carousel">
      <button className="nav-button" disabled={count <= 1 || busy} onClick={() => onMove(-1)} aria-label="Previous location"><ChevronLeft /></button>
      <div className="identity-card spawn-card">
        <div className="location-icon"><MapPin size={22} /></div>
        <div className="identity-copy"><span className="eyebrow">LOCATION {count ? index + 1 : 0} OF {count}</span><h2>{location?.label || "Loading locations"}</h2><p>{location?.description || "Preparing a safe arrival point…"}</p></div>
        <button className="button primary" disabled={!location || busy || previewing || traveling} onClick={onAccept}>{busy ? <LoaderCircle className="spin" size={17} /> : <MapPin size={17} />}Spawn here</button>
      </div>
      <button className="nav-button" disabled={count <= 1 || busy} onClick={() => onMove(1)} aria-label="Next location"><ChevronRight /></button>
    </section>
    <div className="key-hints"><kbd>←</kbd><kbd>→</kbd><span>{traveling ? "Flying to location…" : "Preview location"}</span><kbd>Enter</kbd><span>Spawn</span></div>
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
      <div><span className="eyebrow">CINEMATIC TOOLS</span><h2>Scene Studio</h2></div>
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
