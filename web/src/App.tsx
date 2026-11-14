import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { Building2, ChevronLeft, ChevronRight, Clock, House, LoaderCircle, LogOut, MapPin, Plus, X } from "lucide-react";
import { CreatorScreen } from "./Creator";
import { fetchNui } from "./nui";
import { setLocales, useLocale } from "./locales";
import {
  characterName, defaultArrivalId, isValidBirthdate, money, normalizeCharacters, parseArrivalList, parseLibrary, slotTarget, SPAWN_PREVIEW_SUPERSEDED, spawnPreviewTimeout, wrapIndex,
} from "./lib";
import type { ModelLibrary } from "./lib";
import type { Character, NuiMessage, SceneDraft, SpawnLocation } from "./types";

type Stage = "hidden" | "characters" | "spawn" | "flight" | "creator";
type FlightState = { location: string; character: string | null; skippable: boolean; stage: string };
type CreatorPayload = { draft?: SceneDraft; scenes?: Record<string, SceneDraft>; cursor?: boolean; error?: string; library?: unknown; placing?: boolean; selected?: string };
type UiSettings = {
  brandName: string; showNewSlotBadge: boolean; nationalities: string[]; defaultNationality: string; allowFreeTextNationality: boolean;
  profile: ProfileText;
  /** One screen for character and arrival point, then a fly-in; false keeps the separate spawn picker. */
  combinedSelect: boolean;
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
const DEFAULT_UI: UiSettings = { brandName: "Kora", showNewSlotBadge: false, nationalities: [], defaultNationality: "", allowFreeTextNationality: false, profile: DEFAULT_PROFILE, combinedSelect: false };

function parseProfile(raw: unknown, t: (key: string, ...values: Array<string | number>) => string): ProfileText {
  const source = (raw && typeof raw === "object" ? raw : {}) as Record<string, { label?: unknown; description?: unknown } | undefined>;
  const profile: ProfileText = {
    career: { label: t("UI.profileCareer"), description: "" },
    affiliation: { label: t("UI.profileAffiliation"), description: "" },
    finances: { label: t("UI.profileFinances"), description: "" },
    birthDate: { label: t("UI.profileBirthDate"), description: "" },
    nationality: { label: t("UI.profileNationality"), description: t("UI.placeOfOrigin") },
    citizenId: { label: t("UI.profileCitizenId"), description: "" },
  };
  for (const key of Object.keys(profile) as ProfileCard[]) {
    const entry = source[key];
    const label = typeof entry?.label === "string" ? entry.label.trim() : "";
    profile[key] = {
      label: label || profile[key].label,
      description: typeof entry?.description === "string" ? entry.description.trim() : profile[key].description,
    };
  }
  return profile;
}

function parseUi(raw: unknown, t: (key: string, ...values: Array<string | number>) => string): UiSettings {
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
    profile: parseProfile(ui.profile, t),
    combinedSelect: ui.combinedSelect === true,
  };
}

type SpawnHints = { previous: string; next: string; preview: string; flying: string; spawn: string };
const DEFAULT_SPAWN_HINTS: SpawnHints = { previous: "Previous", next: "Next", preview: "Preview location", flying: "Flying to location…", spawn: "Spawn" };
type SpawnPayload = { locations?: SpawnLocation[]; visible?: boolean; previewBudgetMs?: number; switchCooldownMs?: number; settleMs?: number; lockWhileMoving?: boolean; hints?: Partial<SpawnHints> };

function parseSpawnHints(value: Partial<SpawnHints> | undefined, t: (key: string, ...values: Array<string | number>) => string): SpawnHints {
  const fallback: Record<keyof SpawnHints, string> = {
    previous: t("UI.spawnPrevious"), next: t("UI.spawnNext"), preview: t("UI.spawnPreview"),
    flying: t("UI.spawnFlying"), spawn: t("UI.spawn"),
  };
  const pick = (key: keyof SpawnHints) => (typeof value?.[key] === "string" && value[key]!.trim() ? value[key]! : fallback[key]);
  return { previous: pick("previous"), next: pick("next"), preview: pick("preview"), flying: pick("flying"), spawn: pick("spawn") };
}

function roleLabel(role: Character["job"], fallback: string) {
  return role?.label || role?.name || fallback;
}

function gradeLabel(role: Character["job"], t: (key: string, ...values: Array<string | number>) => string) {
  return role?.grade?.name || t("UI.grade", role?.grade?.level ?? 0);
}

function characterInitials(character: Character) {
  const first = character.charinfo?.firstname?.trim().charAt(0) || "";
  const last = character.charinfo?.lastname?.trim().charAt(0) || "";
  return `${first}${last}`.toUpperCase() || "?";
}

export function App() {
  const t = useLocale();
  const tRef = useRef(t);
  tRef.current = t;
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
  const [previewWatchdogMs, setPreviewWatchdogMs] = useState(0);
  const [closeCreateOnBackdrop, setCloseCreateOnBackdrop] = useState(false);
  const [confirmDiscard, setConfirmDiscard] = useState(true);
  const [uiSettings, setUiSettings] = useState<UiSettings>(DEFAULT_UI);
  const [createDraft, setCreateDraft] = useState<CreateDraft>(() => emptyCreateDraft(DEFAULT_UI));
  const [previewStage, setPreviewStage] = useState<string | null>(null);
  const [spawnTraveling, setSpawnTraveling] = useState(false);
  const spawnCameraReady = useRef(false);
  const spawnPreviewLiveSeq = useRef(0);
  const spawnPreviewBudget = useRef<number | null>(null);
  const spawnSwitchCooldown = useRef(800);
  const lastSpawnSwitch = useRef(0);
  const spawnSettle = useRef(1000);
  const spawnSettleTimer = useRef(0);
  const [spawnLock, setSpawnLock] = useState(true);
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
  const [creatorLibrary, setCreatorLibrary] = useState<ModelLibrary>({});
  const [creatorPlacing, setCreatorPlacing] = useState(false);
  const [creatorFocus, setCreatorFocus] = useState<string | null>(null);
  const [arrivals, setArrivals] = useState<SpawnLocation[]>([]);
  const [arrivalId, setArrivalId] = useState<string | null>(null);
  const [arrivalsLoading, setArrivalsLoading] = useState(false);
  const [flight, setFlight] = useState<FlightState | null>(null);
  const arrivalSeq = useRef(0);

  const canCreate = characters.length < maxCharacters;
  const slideCount = characters.length + (canCreate ? 1 : 0);
  const character = index < characters.length ? characters[index] : null;
  const spawn = spawns[spawnIndex] ?? null;

  useEffect(() => {
    const listener = (event: MessageEvent<NuiMessage>) => {
      const { action, data } = event.data || {};
      if (action === "multichar:locales") { setLocales(data); return; }
      if (action === "multichar:show") {
        const payload = data as { characters?: unknown; maxCharacters?: number; previewWatchdogMs?: number; ui?: Record<string, unknown> & { closeCreateOnBackdrop?: boolean; confirmDiscardOnClose?: boolean; confirmDisconnect?: boolean } };
        setPreviewWatchdogMs(Math.max(0, Number(payload?.previewWatchdogMs) || 0));
        setCloseCreateOnBackdrop(payload?.ui?.closeCreateOnBackdrop === true);
        setConfirmDiscard(payload?.ui?.confirmDiscardOnClose !== false);
        setConfirmDisconnect(payload?.ui?.confirmDisconnect !== false);
        setDisconnecting(false);
        const nextUi = parseUi(payload?.ui, tRef.current);
        setUiSettings(nextUi);
        setCreateDraft(emptyCreateDraft(nextUi));
        setCharacters(normalizeCharacters(payload?.characters));
        setMaxCharacters(Number(payload?.maxCharacters) || 5);
        spawnCameraReady.current = false;
        setArrivals([]); setArrivalId(null); setArrivalsLoading(false); setFlight(null);
        setIndex(0); setStage("characters"); setBusy(false); setDetails(false); setCreating(false); setDeleting(false); setPreviewing(true); setSpawnTraveling(false);
      } else if (action === "multichar:flight:start") {
        const payload = (data ?? {}) as { location?: string; character?: string | null; skippable?: boolean };
        setFlight({ location: payload.location || tRef.current("UI.yourArrivalPoint"), character: payload.character || null, skippable: payload.skippable !== false, stage: "lift" });
        setCreating(false); setDeleting(false); setDisconnecting(false); setDetails(false); setPreviewing(false); setBusy(true);
        setStage("flight");
      } else if (action === "multichar:flight:stage") {
        const next = (data as { stage?: string })?.stage;
        if (next) setFlight((current) => (current ? { ...current, stage: next } : current));
      } else if (action === "multichar:close") { setStage("hidden"); setFlight(null); }
      else if (action === "multichar:error") { setToast(String(data || tRef.current("Notify.generic_error"))); setBusy(false); }
      else if (action === "multichar:previewLoading") setPreviewing(true);
      else if (action === "multichar:previewReady") {
        const payload = data as { scene?: string; error?: string; ok?: boolean };
        setPreviewing(false); setSceneName(payload.scene || "");
        if (payload.ok === false && payload.error) setToast(payload.error);
      } else if (action === "multichar:spawn:previewLive") {
        spawnCameraReady.current = true;
        spawnPreviewLiveSeq.current += 1;
        setPreviewing(false);
        setSpawnTraveling(false);
        setPreviewStage(null);
      } else if (action === "multichar:spawn:previewStage") {
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
        setSpawnHints(parseSpawnHints((data as SpawnPayload)?.hints, tRef.current));
        spawnCameraReady.current = false;
        setStage("spawn"); setBusy(false); setSpawnIndex(0); setPreviewing(true); setSpawnTraveling(false);
      } else if (action === "multichar:creator:show") {
        const payload = data as CreatorPayload;
        setCreatorDraft(payload.draft ?? null); setCreatorScenes(payload.scenes ?? {}); setCreatorCursor(payload.cursor !== false); setCreatorLibrary(parseLibrary(payload.library)); setCreatorPlacing(false); setCreatorFocus(null); setStage("creator");
      } else if (action === "multichar:creator:state") {
        const payload = data as CreatorPayload;
        if (payload.draft) setCreatorDraft(payload.draft);
        if (payload.scenes) setCreatorScenes(payload.scenes);
        if (typeof payload.cursor === "boolean") setCreatorCursor(payload.cursor);
        setCreatorPlacing(payload.placing === true);
        if (payload.selected) setCreatorFocus(payload.selected);
        if (payload.error) setToast(payload.error);
      } else if (action === "multichar:creator:cursor") setCreatorCursor((data as { cursor?: boolean })?.cursor === true);
      else if (action === "multichar:creator:close") setStage("hidden");
      else if (action === "multichar:creator:exported") {
        setExported((data as { registerCall?: boolean })?.registerCall ? tRef.current("UI.registrationCopied") : tRef.current("UI.configCopied"));
        window.setTimeout(() => setExported(null), 2400);
      } else if (action === "multichar:creator:validated") {
        setExported(String((data as { message?: string })?.message || tRef.current("Studio.valid")));
        window.setTimeout(() => setExported(null), 2400);
      }
    };
    window.addEventListener("message", listener);
    fetchNui("multichar:ready");
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

  // One-screen select: load the arrival points this character can start at.
  // The list depends on the character (their last location, owned property),
  // so it is fetched on the same debounce as the scene preview and answers
  // from an older selection are dropped.
  useEffect(() => {
    if (stage !== "characters" || !uiSettings.combinedSelect) return;
    const seq = ++arrivalSeq.current;
    if (!character) { setArrivals([]); setArrivalId(null); setArrivalsLoading(false); return; }
    setArrivalsLoading(true);
    const timer = window.setTimeout(() => {
      fetchNui<unknown>("multichar:spawn:list", { citizenid: character.citizenid }).then((reply) => {
        if (seq !== arrivalSeq.current) return;
        const list = parseArrivalList(reply);
        setArrivals(list);
        setArrivalId((current) => defaultArrivalId(list, current));
        setArrivalsLoading(false);
        if (!list.length) setToast(tRef.current("UI.noArrivalForCharacter"));
      });
    }, 120);
    return () => window.clearTimeout(timer);
  }, [stage, character?.citizenid, uiSettings.combinedSelect]);

  useEffect(() => {
    if (!previewing || stage !== "characters" || !previewWatchdogMs) return;
    const timer = window.setTimeout(() => {
      setPreviewing(false);
      setToast(tRef.current("UI.previewTimeout"));
    }, previewWatchdogMs);
    return () => window.clearTimeout(timer);
  }, [previewing, stage, index, previewWatchdogMs]);

  useEffect(() => {
    if (stage !== "spawn" || !spawn) return;
    let active = true;
    const initial = !spawnCameraReady.current;
    if (!initial && spawnCameraTarget.current === spawn.id) return;
    let timeoutId = 0;
    const start = () => {
      spawnSettleTimer.current = 0;
      spawnCameraTarget.current = spawn.id;
      const liveSeqAtStart = spawnPreviewLiveSeq.current;
      if (initial) setPreviewing(true);
      else setSpawnTraveling(true);
      setPreviewStage(null);
      const timeout = new Promise<null>((resolve) => {
        timeoutId = window.setTimeout(() => resolve(null), spawnPreviewTimeout(spawnPreviewBudget.current));
      });
      Promise.race([fetchNui<{ ok?: boolean; reason?: string }>("multichar:spawn:focus", { id: spawn.id }), timeout]).then((result) => {
        if (!active) return;
        if (result === null) {
          if (spawnPreviewLiveSeq.current === liveSeqAtStart) {
            setToast(tRef.current("UI.arrivalPreviewTimeout"));
          }
          return;
        }
        if (result?.ok === false) {
          if (result.reason !== SPAWN_PREVIEW_SUPERSEDED) {
            setToast(tRef.current("UI.arrivalPreviewFailed"));
          }
          return;
        }
        spawnCameraReady.current = true;
      }).catch(() => {
        if (active) setToast(tRef.current("UI.arrivalPreviewFailed"));
      }).finally(() => {
        window.clearTimeout(timeoutId);
        if (!active) return;
        if (initial) setPreviewing(false);
        setSpawnTraveling(false);
      });
    };
    if (spawnCameraTarget.current === null || spawnSettle.current <= 0) start();
    else spawnSettleTimer.current = window.setTimeout(start, spawnSettle.current);
    const settleTimer = spawnSettleTimer.current;
    return () => { active = false; window.clearTimeout(settleTimer); };
  }, [stage, spawn?.id]);

  const move = (delta: number) => {
    if (stage === "characters" && !creating && !deleting && slideCount) {
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

  const moveArrival = (delta: number) => {
    if (stage !== "characters" || creating || deleting || busy || !arrivals.length) return;
    const at = Math.max(0, arrivals.findIndex((entry) => entry.id === arrivalId));
    setArrivalId(arrivals[wrapIndex(at, delta, arrivals.length)].id);
  };

  const accept = () => {
    if (busy || previewing || spawnTraveling) return;
    if (stage === "characters" && !creating && !deleting) {
      if (!character) setCreating(true);
      else if (uiSettings.combinedSelect) {
        if (!arrivalId || arrivalsLoading) return;
        setBusy(true);
        fetchNui<{ ok?: boolean }>("multichar:play", { citizenid: character.citizenid, locationId: arrivalId }).then((reply) => {
          if (!reply?.ok) setBusy(false);
        });
      }
      else { setBusy(true); fetchNui("multichar:select", { citizenid: character.citizenid }); }
    } else if (stage === "spawn" && spawn) {
      window.clearTimeout(spawnSettleTimer.current);
      spawnSettleTimer.current = 0;
      setBusy(true); fetchNui("multichar:spawn:choose", { id: spawn.id });
    }
  };

  useEffect(() => {
    const keyboard = (event: KeyboardEvent) => {
      if (stage === "hidden" || stage === "creator" || stage === "flight" || creating || deleting || ["INPUT", "TEXTAREA", "SELECT"].includes((event.target as HTMLElement)?.tagName)) return;
      if (event.key === "ArrowLeft" || event.key.toLowerCase() === "a") move(-1);
      else if (event.key === "ArrowRight" || event.key.toLowerCase() === "d") move(1);
      else if (uiSettings.combinedSelect && stage === "characters" && event.key === "ArrowUp") { event.preventDefault(); moveArrival(-1); }
      else if (uiSettings.combinedSelect && stage === "characters" && event.key === "ArrowDown") { event.preventDefault(); moveArrival(1); }
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
      {toast && <div className="toast"><span>{toast}</span><button aria-label={t("UI.dismiss")} onClick={() => setToast(null)}><X size={15} /></button></div>}
      {stage === "characters" && uiSettings.combinedSelect && (
        <CombinedScreen
          characters={characters} character={character} index={index} canCreate={canCreate}
          brand={uiSettings.brandName} profile={uiSettings.profile}
          details={details} previewing={previewing} sceneName={sceneName} busy={busy}
          arrivals={arrivals} arrivalId={arrivalId} arrivalsLoading={arrivalsLoading}
          onPickCharacter={(next) => { if (next !== index && !busy && !creating && !deleting) { setPreviewing(true); setIndex(next); setDetails(false); } }}
          onPickArrival={(id) => { if (!busy) setArrivalId(id); }}
          onAccept={accept} onDetails={() => setDetails((value) => !value)} onDelete={() => setDeleting(true)}
          onDisconnect={() => (confirmDisconnect ? setDisconnecting(true) : fetchNui("multichar:disconnect"))}
        />
      )}
      {stage === "flight" && flight && <FlightScreen flight={flight} />}
      {stage === "characters" && !uiSettings.combinedSelect && (
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
        <CreatorScreen key={creatorDraft.id} draft={creatorDraft} scenes={creatorScenes} cursor={creatorCursor} exported={exported} library={creatorLibrary} placing={creatorPlacing} focusId={creatorFocus} />
      )}
      {previewing && !creating && (stage === "characters" || stage === "spawn") && <SceneTransition stage={stage} previewStage={previewStage} />}
      {creating && <CreateDialog ui={uiSettings} draft={createDraft} onDraft={setCreateDraft} closeOnBackdrop={closeCreateOnBackdrop} confirmDiscard={confirmDiscard} onClose={() => setCreating(false)} onBusy={setBusy} />}
      {disconnecting && <DisconnectDialog onClose={() => setDisconnecting(false)} />}
      {deleting && character && <DeleteDialog character={character} onClose={() => setDeleting(false)} onBusy={setBusy} />}
    </div>
  );
}

function SceneTransition({ stage, previewStage }: { stage: "characters" | "spawn"; previewStage?: string | null }) {
  const t = useLocale();
  const detail = previewStage === "streaming" ? t("UI.streamingArea") : t("UI.streamingWorld");

  return <div className="scene-transition" role="status" aria-live="polite">
    <div className="transition-content">
      <h2>{stage === "spawn" ? t("UI.scoutingArrival") : t("UI.settingScene")}</h2>
      <p>{detail}</p>
      <div className="transition-progress"><i /></div>
    </div>
  </div>;
}

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
  const t = useLocale();
  const { character } = props;
  const job = character ? roleLabel(character.job, t("UI.civilian")) : "";
  const gang = character?.gang?.name && character.gang.name !== "none" ? character.gang : null;
  const prev = slotTarget(props.characters, props.canCreate, props.index, -1, t("UI.createNewCharacter"), t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid));
  const next = slotTarget(props.characters, props.canCreate, props.index, 1, t("UI.createNewCharacter"), t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid));
  const targetLabel = (target: typeof prev) => target ? t("UI.characterSlot", target.slot, target.label) : undefined;
  const slots = [...props.characters.map((entry) => characterName(entry, t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid))), ...(props.canCreate ? [t("UI.newCharacterSlot")] : [])];
  return <>
    <span className="brand-mark corner-brand">{props.brand}</span>
    <button className="quiet-button corner-action" aria-label={t("UI.disconnect")} onClick={props.onDisconnect}><LogOut size={15} />{t("UI.disconnect")}</button>
    {props.details && character && <Dossier character={character} profile={props.profile} onClose={props.onDetails} onDelete={props.onDelete} />}
    <section className={`lower-third${character ? "" : " new-character"}`}>
      <p className="third-kicker">{props.previewing ? t("UI.loadingScene") : (props.sceneName || t("UI.cinematicPreview"))}</p>
      <h2>{character ? characterName(character, t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid)) : t("UI.createCharacter")}{!character && props.showNewBadge && <span className="new-slot-chip">{t("UI.newCharacter")}</span>}</h2>
      <p className="third-meta">{character ? [job, gradeLabel(character.job, t), gang ? roleLabel(gang, gang.name || t("UI.affiliationFallback")) : null].filter(Boolean).join(" · ") : t("UI.newStoryLosSantos")}</p>
      <div className="third-actions">
        <button className="button primary" disabled={props.busy || props.previewing} onClick={props.onAccept}>
          {props.busy ? <LoaderCircle className="spin" size={16} /> : null}
          {character ? t("UI.continue") : t("UI.createIdentity")}
        </button>
        {character && <button className="button ghost profile-button" aria-expanded={props.details} onClick={props.onDetails}>{t("UI.profile")}</button>}
        <SlotNav position={props.index + 1} total={props.count} disabled={props.count <= 1} onMove={props.onMove}
          prevLabel={prev ? t("UI.previousTarget", targetLabel(prev)!) : t("UI.spawnPrevious")} nextLabel={next ? t("UI.nextTarget", targetLabel(next)!) : t("UI.spawnNext")} prevTitle={targetLabel(prev)} nextTitle={targetLabel(next)} />
      </div>
    </section>
    <SlotRail labels={slots} selected={props.index} />
    <div className="key-hints"><kbd>←</kbd><kbd>→</kbd><span>{t("UI.browse")}</span><kbd>Enter</kbd><span>{t("UI.continue")}</span></div>
  </>;
}

function arrivalIcon(typeLoc?: string) {
  if (typeLoc === "current") return <Clock size={16} />;
  if (typeLoc === "house") return <House size={16} />;
  if (typeLoc === "apartment") return <Building2 size={16} />;
  return <MapPin size={16} />;
}

/**
 * Character and arrival point on one screen. Characters on the left, the
 * arrival points that character can start at on the right, Play in the middle.
 * The camera flight to the chosen point runs after Play (see FlightScreen).
 */
function CombinedScreen(props: {
  characters: Character[]; character: Character | null; index: number; canCreate: boolean;
  brand: string; profile: ProfileText; details: boolean; previewing: boolean; sceneName: string; busy: boolean;
  arrivals: SpawnLocation[]; arrivalId: string | null; arrivalsLoading: boolean;
  onPickCharacter: (index: number) => void; onPickArrival: (id: string) => void;
  onAccept: () => void; onDetails: () => void; onDelete: () => void; onDisconnect: () => void;
}) {
  const t = useLocale();
  const { character, arrivals, arrivalId } = props;
  const arrival = arrivals.find((entry) => entry.id === arrivalId) ?? null;
  const job = character ? roleLabel(character.job, t("UI.civilian")) : "";
  const canPlay = !props.busy && !props.previewing && (!character || (!!arrival && !props.arrivalsLoading));
  return <>
    <span className="brand-mark corner-brand">{props.brand}</span>
    <button className="quiet-button corner-action" aria-label={t("UI.disconnect")} onClick={props.onDisconnect}><LogOut size={15} />{t("UI.disconnect")}</button>

    <aside className="pick-panel who-panel panel" aria-label={t("UI.characters")}>
      <h3 className="pick-heading"><span>{t("UI.who")}</span><span>{t(props.characters.length === 1 ? "UI.characterCount" : "UI.characterCountPlural", props.characters.length)}</span></h3>
      <ul className="pick-list">
        {props.characters.map((entry, i) => <li key={entry.citizenid}>
          <button className={`pick-card${i === props.index ? " on" : ""}`} aria-pressed={i === props.index} onClick={() => props.onPickCharacter(i)}>
            <span className="pick-avatar">{characterInitials(entry)}</span>
            <span className="pick-text"><strong>{characterName(entry, t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid))}</strong><small>{[roleLabel(entry.job, t("UI.civilian")), gradeLabel(entry.job, t)].join(" · ")}</small></span>
          </button>
        </li>)}
        {props.canCreate && <li>
          <button className={`pick-card new${!character ? " on" : ""}`} aria-pressed={!character} onClick={() => props.onPickCharacter(props.characters.length)}>
            <span className="pick-avatar"><Plus size={16} /></span>
            <span className="pick-text"><strong>{t("UI.createCharacter")}</strong><small>{t("UI.beginNewStory")}</small></span>
          </button>
        </li>}
      </ul>
    </aside>

    <aside className="pick-panel where-panel panel" aria-label={t("UI.arrivalPoints")}>
      <h3 className="pick-heading"><span>{t("UI.where")}</span>{character && arrivals.length > 0 && <span>{t("UI.arrivalCount", arrivals.length)}</span>}</h3>
      {!character
        ? <p className="pick-note">{t("UI.newCharacterFirstArrival")}</p>
        : arrivals.length === 0
          ? <p className="pick-note" role="status">{props.arrivalsLoading ? t("UI.findingArrivalPoints") : t("UI.noArrivalPoints")}</p>
          : <ul className={`pick-list${props.arrivalsLoading ? " loading" : ""}`}>
            {arrivals.map((entry) => <li key={entry.id}>
              <button className={`pick-card${entry.id === arrivalId ? " on" : ""}`} aria-pressed={entry.id === arrivalId} onClick={() => props.onPickArrival(entry.id)}>
                <span className="pick-avatar">{arrivalIcon(entry.typeLoc)}</span>
                <span className="pick-text"><strong>{entry.label}</strong>{entry.description && <small>{entry.description}</small>}</span>
              </button>
            </li>)}
          </ul>}
    </aside>

    {props.details && character && <Dossier character={character} profile={props.profile} onClose={props.onDetails} onDelete={props.onDelete} />}

    <section className="play-bar">
      <h2>{character ? characterName(character, t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid)) : t("UI.createCharacter")}</h2>
      <p className="third-meta">{character ? `${job}${arrival ? ` → ${arrival.label}` : ""}` : t("UI.newStoryLosSantos")}</p>
      <div className="third-actions">
        {character && <button className="button ghost profile-button" aria-expanded={props.details} onClick={props.onDetails}>{t("UI.profile")}</button>}
        <button className="button primary play-button" disabled={!canPlay} onClick={props.onAccept}>
          {props.busy ? <LoaderCircle className="spin" size={16} /> : null}
          {character ? t("UI.play") : t("UI.createIdentity")}
        </button>
      </div>
    </section>
    <p className="third-kicker scene-label">{props.previewing ? t("UI.loadingScene") : (props.sceneName || t("UI.cinematicPreview"))}</p>
    <div className="key-hints combined-hints"><kbd>A</kbd><kbd>D</kbd><span>{t("UI.character")}</span><kbd>↑</kbd><kbd>↓</kbd><span>{t("UI.arrival")}</span><kbd>Enter</kbd><span>{t("UI.play")}</span></div>
  </>;
}

/**
 * Shown while the camera flies to the chosen arrival point. The scene itself is
 * the real game camera; this only adds a caption over it. Lua closes
 * the whole UI once the player has arrived.
 */
function FlightScreen({ flight }: { flight: FlightState }) {
  const t = useLocale();
  return <div className={`flight stage-${flight.stage}`} role="status" aria-live="polite">
    <section className="flight-caption">
      <p className="third-kicker">{flight.stage === "descent" ? t("UI.arrivingAt") : t("UI.flyingTo")}</p>
      <h2>{flight.location}</h2>
      {flight.character && <p className="third-meta">{flight.character}</p>}
      <div className="flight-progress"><i /></div>
      {flight.skippable && <p className="flight-skip"><kbd>Space</kbd><span>{t("UI.skip")}</span></p>}
    </section>
  </div>;
}

function Dossier({ character, profile, onClose, onDelete }: { character: Character; profile: ProfileText; onClose: () => void; onDelete: () => void }) {
  const t = useLocale();
  const gang = character.gang?.name && character.gang.name !== "none" ? character.gang : null;
  const card = (key: ProfileCard, value: string, detail?: string) => {
    const text = detail === undefined ? profile[key].description : detail;
    return <div><span><small>{profile[key].label}</small><strong>{value}</strong>{text && <em>{text}</em>}</span></div>;
  };
  return <aside className="dossier panel">
    <div className="dossier-heading">
      <div><h3>{characterName(character, t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid))}</h3><p>{roleLabel(character.job, t("UI.civilian"))} · {gradeLabel(character.job, t)}</p></div>
      <button className="icon-button" aria-label={t("UI.closeProfile")} onClick={onClose}><X size={16} /></button>
    </div>
    <div className="detail-list">
      {card("career", roleLabel(character.job, t("UI.civilian")), gradeLabel(character.job, t))}
      {card("affiliation", gang ? roleLabel(gang, gang.name || t("UI.gang")) : t("UI.none"), gang ? gradeLabel(gang, t) : t("UI.independent"))}
      {card("finances", t("UI.bankAmount", money(character.money?.bank)), t("UI.cashAmount", money(character.money?.cash)))}
      {card("birthDate", character.charinfo?.birthdate || t("UI.unknown"))}
      {card("nationality", character.charinfo?.nationality || t("UI.unknown"))}
      {card("citizenId", character.citizenid)}
    </div>
    <button className="danger-link" onClick={onDelete}>{t("UI.deleteCharacter")}</button>
  </aside>;
}

type CreateField = "firstname" | "lastname" | "birthdate" | "nationality";
type CreateErrors = Partial<Record<CreateField, string>>;



type CreateDraft = { firstname: string; lastname: string; birthdate: string; nationality: string; gender: number };

function emptyCreateDraft(ui: UiSettings): CreateDraft {
  const list = ui.nationalities;
  const nationality = list.length === 0 ? (ui.defaultNationality || "USA")
    : list.includes(ui.defaultNationality) || (ui.allowFreeTextNationality && ui.defaultNationality) ? ui.defaultNationality : list[0];
  return { firstname: "", lastname: "", birthdate: "2000-01-01", nationality, gender: 0 };
}

function CreateDialog({ ui, draft, onDraft, closeOnBackdrop, confirmDiscard, onClose, onBusy }: { ui: UiSettings; draft: CreateDraft; onDraft: (draft: CreateDraft) => void; closeOnBackdrop: boolean; confirmDiscard: boolean; onClose: () => void; onBusy: (value: boolean) => void }) {
  const t = useLocale();
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
  const [asking, setAsking] = useState(false);
  const requestClose = () => {
    if (dirty && confirmDiscard && !asking) { setAsking(true); return; }
    if (dirty) onDraft(EMPTY_CREATE_DRAFT);
    onClose();
  };
  const keepEditing = () => setAsking(false);
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
    if (!firstname) found.firstname = t("UI.firstnameRequired");
    else if (firstname.length > 24) found.firstname = t("UI.nameLength");
    if (!lastname) found.lastname = t("UI.lastnameRequired");
    else if (lastname.length > 24) found.lastname = t("UI.nameLength");
    if (!isValidBirthdate(birthdate)) found.birthdate = t("UI.birthdateError");
    if (useDropdown && !nationalityList.includes(nationality)) found.nationality = t("UI.nationalityListError");
    else if (nationality.length < 2 || nationality.length > 32) found.nationality = t("UI.nationalityLengthError");
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
    <div className="panel-heading"><h3>{t("UI.createCharacter")}</h3><button type="button" className="icon-button" aria-label={t("UI.close")} onClick={requestClose}><X size={16} /></button></div>
    <p className="modal-copy">{t("UI.createDescription")}</p>
    <div className="field-grid">
      <div className="field"><label>{t("UI.firstName")}<input name="firstname" autoFocus maxLength={24} required aria-invalid={!!errors.firstname} aria-describedby={errors.firstname ? "create-firstname-error" : undefined} value={draft.firstname} onChange={(event) => setField("firstname", event.target.value)} /></label><FieldError id="create-firstname-error" message={errors.firstname} /></div>
      <div className="field"><label>{t("UI.lastName")}<input name="lastname" maxLength={24} required aria-invalid={!!errors.lastname} aria-describedby={errors.lastname ? "create-lastname-error" : undefined} value={draft.lastname} onChange={(event) => setField("lastname", event.target.value)} /></label><FieldError id="create-lastname-error" message={errors.lastname} /></div>
    </div>
    <div className="field-grid">
      <div className="field"><label>{t("UI.birthDate")}<input name="birthdate" type="date" max={new Date().toISOString().slice(0, 10)} required aria-invalid={!!errors.birthdate} aria-describedby={errors.birthdate ? "create-birthdate-error" : undefined} value={draft.birthdate} onChange={(event) => setField("birthdate", event.target.value)} /></label><FieldError id="create-birthdate-error" message={errors.birthdate} /></div>
      <div className="field"><label>{t("UI.nationality")}{useDropdown
        ? <select name="nationality" required aria-invalid={!!errors.nationality} aria-describedby={errors.nationality ? "create-nationality-error" : undefined} value={draft.nationality} onChange={(event) => setField("nationality", event.target.value)}>{(nationalityList.includes(draft.nationality) ? nationalityList : [draft.nationality, ...nationalityList]).map((entry) => <option key={entry} value={entry}>{entry}</option>)}</select>
        : <><input name="nationality" maxLength={32} required aria-invalid={!!errors.nationality} aria-describedby={errors.nationality ? "create-nationality-error" : undefined} list={nationalityList.length ? "nationality-options" : undefined} value={draft.nationality} onChange={(event) => setField("nationality", event.target.value)} />{nationalityList.length > 0 && <datalist id="nationality-options">{nationalityList.map((entry) => <option key={entry} value={entry} />)}</datalist>}</>}</label><FieldError id="create-nationality-error" message={errors.nationality} /></div>
    </div>
    <div className="segmented" aria-label={t("UI.bodyModel")}><button type="button" className={draft.gender === 0 ? "active" : ""} onClick={() => { setField("gender", 0); fetchNui("multichar:createPreview", { gender: 0 }); }}>{t("UI.male")}</button><button type="button" className={draft.gender === 1 ? "active" : ""} onClick={() => { setField("gender", 1); fetchNui("multichar:createPreview", { gender: 1 }); }}>{t("UI.female")}</button></div>
    {asking && <div className="discard-prompt" role="alertdialog" aria-label={t("UI.discardDetails")}><p>{t("UI.discardPrompt")}</p><div className="modal-actions"><button type="button" className="button ghost" onClick={keepEditing}>{t("UI.keepEditing")}</button><button type="button" className="button destructive" onClick={requestClose}>{t("UI.discard")}</button></div></div>}
    {!asking && <div className="modal-actions"><button type="button" className="button ghost" onClick={requestClose}>{t("UI.cancel")}</button><button className="button primary">{t("UI.createIdentity")}</button></div>}
  </form></div>;
}

function FieldError({ id, message }: { id: string; message?: string }) {
  return message ? <small id={id} className="field-error" role="alert">{message}</small> : null;
}

function DisconnectDialog({ onClose }: { onClose: () => void }) {
  const t = useLocale();
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return <div className="modal-layer"><div className="modal-backdrop" onClick={onClose} /><div className="modal panel disconnect-modal" role="alertdialog" aria-label={t("UI.disconnect")}>
    <div className="panel-heading"><h3>{t("UI.disconnectQuestion")}</h3><button className="icon-button" aria-label={t("UI.close")} onClick={onClose}><X size={16} /></button></div>
    <p className="modal-copy">{t("UI.disconnectDescription")}</p>
    <div className="modal-actions"><button className="button ghost" onClick={onClose}>{t("UI.cancel")}</button><button className="button destructive" autoFocus onClick={() => { onClose(); fetchNui("multichar:disconnect"); }}>{t("UI.disconnect")}</button></div>
  </div></div>;
}

function DeleteDialog({ character, onClose, onBusy }: { character: Character; onClose: () => void; onBusy: (value: boolean) => void }) {
  const t = useLocale();
  const name = characterName(character, t("UI.unnamedCharacter"), (cid) => t("UI.characterNumber", cid)); const [typed, setTyped] = useState("");
  return <div className="modal-layer"><div className="modal-backdrop" onClick={onClose} /><div className="modal panel delete-modal">
    <div className="panel-heading"><h3>{t("UI.deleteQuestion", name)}</h3><button className="icon-button" aria-label={t("UI.close")} onClick={onClose}><X size={16} /></button></div>
    <p className="modal-copy">{t("UI.deleteConfirmation", name)}</p>
    <label>{t("UI.characterName")}<input value={typed} onChange={(event) => setTyped(event.target.value)} autoFocus /></label>
    <div className="modal-actions"><button className="button ghost" onClick={onClose}>{t("UI.cancel")}</button><button className="button destructive" disabled={typed !== name} onClick={() => { onBusy(true); onClose(); fetchNui("multichar:delete", { citizenid: character.citizenid }); }}>{t("UI.deleteForever")}</button></div>
  </div></div>;
}

function SpawnScreen({ location, locations, index, count, busy, previewing, traveling, locked, hints, onMove, onAccept }: { location: SpawnLocation | null; locations: SpawnLocation[]; index: number; count: number; busy: boolean; previewing: boolean; traveling: boolean; locked: boolean; hints: SpawnHints; onMove: (delta: number) => void; onAccept: () => void }) {
  const t = useLocale();
  return <>
    <header className="corner-title"><h1>{t("UI.spawnTitle")}</h1></header>
    <section className="lower-third spawn-third">
      {traveling
        ? <p className="third-kicker" role="status">{t("UI.flightArrival")} <strong>{location?.label}</strong></p>
        : <p className="third-kicker">{t("UI.arrivalPoint")}</p>}
      <h2>{location?.label || t("UI.loadingLocations")}</h2>
      <p className="third-meta">{location?.description || t("UI.preparingArrival")}</p>
      <div className="third-actions">
        <button className="button primary" disabled={!location || busy || previewing || traveling} onClick={onAccept}>{busy ? <LoaderCircle className="spin" size={16} /> : null}{t("UI.spawnHere")}</button>
        <SlotNav position={count ? index + 1 : 0} total={count} disabled={count <= 1 || busy || locked} onMove={onMove} prevLabel={t("UI.previousLocation")} nextLabel={t("UI.nextLocation")} />
      </div>
    </section>
    <SlotRail labels={locations.map((entry) => entry.label)} selected={index} />
    <div className="key-hints"><kbd>A</kbd><kbd>←</kbd><span>{hints.previous}</span><kbd>D</kbd><kbd>→</kbd><span>{hints.next}</span><span>{traveling ? hints.flying : hints.preview}</span><kbd>Enter</kbd><span>{hints.spawn}</span></div>
  </>;
}
