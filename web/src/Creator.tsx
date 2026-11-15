import { type ReactNode, useEffect, useMemo, useState } from "react";
import {
  Camera, CheckCircle2, ChevronDown, ChevronLeft, ChevronUp, Clapperboard, Copy, Crosshair, Move, MousePointer2,
  Play, Plus, Save, Search, Sparkles, Trash2, X,
} from "lucide-react";
import { fetchNui } from "./nui";
import { useLocale } from "./locales";
import { filterLibrary, type EntityKind, type ModelLibrary } from "./lib";
import type { SceneDraft } from "./types";
import "./creator.css";

const creatorAction = (action: string, payload: unknown = {}) => fetchNui("multichar:creator:action", { action, payload });

type Tab = "scene" | "cameras" | "timeline";
const KINDS: EntityKind[] = ["ped", "vehicle", "prop"];

export function CreatorScreen({ draft, scenes, cursor, exported, library, placing, focusId }: {
  draft: SceneDraft; scenes: Record<string, SceneDraft>; cursor: boolean; exported: string | null;
  library: ModelLibrary; placing: boolean; focusId: string | null;
}) {
  const t = useLocale();
  const [tab, setTab] = useState<Tab>("scene");
  const [picking, setPicking] = useState<EntityKind | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  useEffect(() => { if (focusId) { setSelected(focusId); setPicking(null); } }, [focusId]);
  useEffect(() => { if (selected && !draft.entities.some((entity) => entity.id === selected)) setSelected(null); }, [draft.entities, selected]);
  const sceneOptions = useMemo(() => Object.keys(scenes).sort(), [scenes]);

  if (placing) return null;

  return <div className="studio">
    <header className="studio-top panel">
      <div><span className="eyebrow">{t("UI.cinematicTools")}</span><h2>{t("UI.sceneStudio")}</h2></div>
      <select aria-label={t("UI.scene")} value={scenes[draft.id] ? draft.id : ""} onChange={(event) => event.target.value && creatorAction("load", { id: event.target.value })}><option value="">{t("UI.unsavedDraft")}</option>{sceneOptions.map((id) => <option key={id} value={id}>{scenes[id].label} · {id}</option>)}</select>
      <button className="button ghost" onClick={() => creatorAction("new")}><Plus size={15} />{t("UI.new")}</button>
      <button className="button ghost" onClick={() => creatorAction("duplicate")}><Copy size={15} />{t("UI.duplicate")}</button>
      <button className={`button ${cursor ? "ghost" : "primary"}`} title={t("UI.tabKey")} onClick={() => creatorAction("toggleMode")}><MousePointer2 size={15} />{cursor ? t("UI.flyCamera") : t("UI.backToEditing")}<kbd>Tab</kbd></button>
      <button className="icon-button" aria-label={t("UI.closeStudio")} onClick={() => creatorAction("close")}><X /></button>
    </header>

    <aside className="studio-panel panel">
      {picking
        ? <ModelPicker kind={picking} library={library} onBack={() => setPicking(null)} onPick={(model) => { creatorAction("addEntity", { type: picking, model }); setPicking(null); }} />
        : <>
          <div className="add-row" role="group" aria-label={t("UI.addToScene")}>
            {KINDS.map((kind) => <button key={kind} className="button primary" onClick={() => setPicking(kind)}><Plus size={15} />{t(`UI.${kind}`)}</button>)}
          </div>
          <EntityList draft={draft} selected={selected} onSelect={(id) => setSelected(selected === id ? null : id)} />
          <nav className="studio-tabs" role="tablist" aria-label={t("UI.sceneSettings")}>
            {([["scene", t("UI.scene")], ["cameras", t("UI.camerasCount", draft.cameras.length)], ["timeline", t("UI.timeline")]] as const).map(([id, label]) =>
              <button key={id} role="tab" aria-selected={tab === id} className={tab === id ? "on" : ""} onClick={() => setTab(id)}>{label}</button>)}
          </nav>
          <div className="studio-tab-body" role="tabpanel">
            {tab === "scene" && <SceneTab draft={draft} />}
            {tab === "cameras" && <CamerasTab draft={draft} />}
            {tab === "timeline" && <TimelineTab draft={draft} />}
          </div>
        </>}
    </aside>

    <footer className="studio-actions panel">
      <button className="button ghost" onClick={() => creatorAction("validate")}><CheckCircle2 size={15} />{t("UI.validate")}</button>
      <button className="button ghost" onClick={() => creatorAction("preview")}><Play size={15} />{t("UI.playTimeline")}</button>
      <button className="button ghost" onClick={() => creatorAction("exportRegister")}><Copy size={15} />{t("UI.copyRegistration")}</button>
      <button className="button primary" onClick={() => creatorAction("exportConfig")}><Copy size={15} />{t("UI.copyConfig")}</button>
      {exported && <span className="export-toast">{exported}</span>}
    </footer>
  </div>;
}

function ModelPicker({ kind, library, onBack, onPick }: { kind: EntityKind; library: ModelLibrary; onBack: () => void; onPick: (model: string) => void }) {
  const t = useLocale();
  const [query, setQuery] = useState("");
  const { matches, custom } = filterLibrary(library, kind, query);
  return <form className="picker" onSubmit={(event) => {
    event.preventDefault();
    const first = matches[0]?.[0] ?? custom;
    if (first) onPick(first);
  }} onKeyDown={(event) => { if (event.key === "Escape") { event.stopPropagation(); onBack(); } }}>
    <div className="picker-head">
      <button type="button" className="icon-button" aria-label={t("UI.back")} onClick={onBack}><ChevronLeft size={16} /></button>
      <h3>Add {t(`UI.${kind}`)}</h3>
    </div>
    <label className="picker-search"><Search size={14} /><input autoFocus aria-label={t("UI.searchModels")} placeholder={t("UI.searchModelPlaceholder")} value={query} onChange={(event) => setQuery(event.target.value)} /></label>
    <ul className="picker-list">
      {matches.map(([model, label]) => <li key={model}><button type="button" onClick={() => onPick(model)}><strong>{label}</strong><small>{model}</small></button></li>)}
      {custom && <li><button type="button" className="custom" onClick={() => onPick(custom)}><strong>{t("UI.useCustomModel", custom)}</strong><small>{t("UI.anyModelName")}</small></button></li>}
      {!matches.length && !custom && <li className="picker-empty">{t("UI.noModels")}</li>}
    </ul>
  </form>;
}

function EntityList({ draft, selected, onSelect }: { draft: SceneDraft; selected: string | null; onSelect: (id: string) => void }) {
  const t = useLocale();
  if (!draft.entities.length) return <p className="empty-hint">{t("UI.emptyEntities")}</p>;
  return <ul className="entity-list" aria-label={t("UI.sceneEntities")}>
    {draft.entities.map((entity, index) => {
      const open = selected === entity.id;
      return <li key={entity.id} className={open ? "on" : undefined}>
        <button className="entity-row" aria-expanded={open} onClick={() => onSelect(entity.id)}>
          <span><strong>{entity.id}</strong><small>{entity.type} · {String(entity.model)}</small></span>
        </button>
        {open && <div className="entity-detail">
          <div className="entity-actions">
            <button className="button primary" onClick={() => creatorAction("moveEntity", { id: entity.id })}><Move size={15} />{t("UI.move")}</button>
            <div className="row-tools">
              <button aria-label={t("UI.moveEntityUp", entity.id)} disabled={index === 0} onClick={() => creatorAction("reorderEntity", { index: index + 1, delta: -1 })}><ChevronUp size={14} /></button>
              <button aria-label={t("UI.moveEntityDown", entity.id)} disabled={index === draft.entities.length - 1} onClick={() => creatorAction("reorderEntity", { index: index + 1, delta: 1 })}><ChevronDown size={14} /></button>
              <button aria-label={t("UI.deleteEntity", entity.id)} onClick={() => creatorAction("removeEntity", { id: entity.id })}><Trash2 size={14} /></button>
            </div>
          </div>
          <JsonEditor label={t("UI.advanced")} value={entity} onSave={(value) => creatorAction("replaceEntity", { originalId: entity.id, value })} />
        </div>}
      </li>;
    })}
  </ul>;
}

function SceneTab({ draft }: { draft: SceneDraft }) {
  const t = useLocale();
  const [selectorText, setSelectorText] = useState(JSON.stringify(draft.selectors ?? [], null, 2));
  useEffect(() => setSelectorText(JSON.stringify(draft.selectors ?? [], null, 2)), [draft.id, draft.selectors]);
  return <>
    <CreatorSection title={t("UI.scene")} icon={<Clapperboard size={15} />}>
      <form onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); try { creatorAction("metadata", { id: form.get("id"), label: form.get("label"), priority: Number(form.get("priority")), selectors: JSON.parse(selectorText) }); } catch {  } }}>
        <label>{t("UI.idLabel")}<input name="id" defaultValue={draft.id} /></label><label>{t("UI.label")}<input name="label" defaultValue={draft.label} /></label><label>{t("UI.priority")}<input name="priority" type="number" defaultValue={draft.priority} /></label>
        <label>{t("UI.selectorsJson")}<textarea rows={4} value={selectorText} onChange={(event) => setSelectorText(event.target.value)} /></label><button className="mini-button"><Save size={13} />{t("UI.applyMetadata")}</button>
      </form>
    </CreatorSection>
    <CreatorSection title={t("UI.environment")} icon={<Sparkles size={15} />}>
      <form onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); const strength = String(form.get("strength") ?? ""); creatorAction("environment", { hour: Number(form.get("hour")), minute: Number(form.get("minute")), weather: form.get("weather"), timecycle: form.get("timecycle") || undefined, strength: strength === "" ? undefined : Number(strength) }); }}>
        <div className="field-grid"><label>{t("UI.hour")}<input name="hour" type="number" min="0" max="23" defaultValue={Number(draft.environment?.hour ?? 18)} /></label><label>{t("UI.minute")}<input name="minute" type="number" min="0" max="59" defaultValue={Number(draft.environment?.minute ?? 0)} /></label></div>
        <label>{t("UI.weather")}<input name="weather" defaultValue={String(draft.environment?.weather ?? "CLEAR")} /></label><label>{t("UI.timecycle")}<input name="timecycle" defaultValue={String(draft.environment?.timecycle ?? "")} /></label><label>{t("UI.strength")}<input name="strength" type="number" step="0.05" min="0" max="1" defaultValue={Number(draft.environment?.strength ?? 0)} /></label><button className="mini-button"><Save size={13} />{t("UI.applyEnvironment")}</button>
      </form>
    </CreatorSection>
    <button className="wide-tool" onClick={() => creatorAction("setAnchor")}><Crosshair size={15} />{t("UI.setAnchor")}</button>
    <button className="wide-tool" onClick={() => creatorAction("placeCharacter")}><Crosshair size={15} />{t("UI.placeCharacter")}</button>
  </>;
}

function CamerasTab({ draft }: { draft: SceneDraft }) {
  const t = useLocale();
  return <CreatorSection title={t("UI.camerasCount", draft.cameras.length)} icon={<Camera size={15} />}>
    <div className="object-list">{draft.cameras.map((camera, index) => <div className="object-editor" key={camera.id}>
      <div className="object-row"><span><strong>{camera.id}</strong><small>{t("UI.fieldOfView")} {String(camera.fov ?? 45)}</small></span><div className="row-tools">
        <button aria-label={t("UI.moveEntityUp", camera.id)} disabled={index === 0} onClick={() => creatorAction("reorderCamera", { index: index + 1, delta: -1 })}><ChevronUp size={13} /></button>
        <button aria-label={t("UI.moveEntityDown", camera.id)} disabled={index === draft.cameras.length - 1} onClick={() => creatorAction("reorderCamera", { index: index + 1, delta: 1 })}><ChevronDown size={13} /></button>
        <button aria-label={t("UI.deleteEntity", camera.id)} disabled={draft.cameras.length <= 1} onClick={() => creatorAction("removeCamera", { id: camera.id })}><Trash2 size={13} /></button>
      </div></div>
      <JsonEditor label={t("UI.editCameraData")} value={camera} onSave={(value) => creatorAction("replaceCamera", { index: index + 1, value })} />
    </div>)}</div>
    <form className="inline-add" onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); creatorAction("captureCamera", { id: form.get("id"), fov: Number(form.get("fov")), transitionMs: 900 }); }}><input name="id" placeholder={t("UI.shotIdPlaceholder")} required /><input name="fov" type="number" min="10" max="100" defaultValue="45" /><button className="mini-button"><Camera size={13} />{t("UI.capture")}</button></form>
  </CreatorSection>;
}

function TimelineTab({ draft }: { draft: SceneDraft }) {
  const t = useLocale();
  const [cueText, setCueText] = useState('{"at":5200,"type":"camera","camera":"establishing","transitionMs":2400}');
  const [scrub, setScrub] = useState(0);
  return <CreatorSection title={t("UI.timeline")} icon={<Clapperboard size={15} />}>
    <div className="timeline-heading"><label>{t("UI.duration")} <input type="number" defaultValue={draft.timeline.durationMs} onBlur={(event) => creatorAction("timeline", { durationMs: Number(event.target.value), loop: draft.timeline.loop })} /></label><label className="check"><input type="checkbox" checked={draft.timeline.loop} onChange={(event) => creatorAction("timeline", { durationMs: draft.timeline.durationMs, loop: event.target.checked })} />{t("UI.loop")}</label></div>
    <input className="scrubber" aria-label={t("UI.scrubTimeline")} type="range" min="0" max={draft.timeline.durationMs || 1} value={scrub} onChange={(event) => { const at = Number(event.target.value); setScrub(at); creatorAction("scrub", { at }); }} />
    <div className="cue-list">{draft.timeline.cues.map((cue, i) => <div className="cue-editor" key={`${String(cue.type)}-${i}`}>
      <div className="cue"><b>{Number(cue.at ?? 0) / 1000}s</b><span>{String(cue.type)}</span><div className="row-tools">
        <button aria-label={t("UI.moveCueUp")} disabled={i === 0} onClick={() => creatorAction("reorderCue", { index: i + 1, delta: -1 })}><ChevronUp size={12} /></button>
        <button aria-label={t("UI.moveCueDown")} disabled={i === draft.timeline.cues.length - 1} onClick={() => creatorAction("reorderCue", { index: i + 1, delta: 1 })}><ChevronDown size={12} /></button>
        <button aria-label={t("UI.deleteCue")} onClick={() => creatorAction("removeCue", { index: i + 1 })}><X size={12} /></button>
      </div></div>
      <JsonEditor label={t("UI.editCueData")} value={cue} onSave={(value) => creatorAction("replaceCue", { index: i + 1, value })} />
    </div>)}</div>
    <div className="cue-add"><input value={cueText} onChange={(event) => setCueText(event.target.value)} /><button className="mini-button" onClick={() => { try { creatorAction("addCue", JSON.parse(cueText)); } catch {  } }}><Plus size={13} />{t("UI.addCueJson")}</button></div>
  </CreatorSection>;
}

function CreatorSection({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) {
  return <section className="creator-section"><h3>{icon}{title}</h3>{children}</section>;
}

function JsonEditor({ label, value, onSave }: { label: string; value: unknown; onSave: (value: Record<string, unknown>) => void }) {
  const t = useLocale();
  const serialized = JSON.stringify(value, null, 2);
  const [text, setText] = useState(serialized);
  const [error, setError] = useState(false);
  useEffect(() => { setText(serialized); setError(false); }, [serialized]);
  return <details className="json-editor"><summary>{label}</summary><textarea rows={7} value={text} onChange={(event) => setText(event.target.value)} />{error && <small>{t("UI.validJson")}</small>}<button className="mini-button" onClick={() => { try { const parsed = JSON.parse(text); if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") throw new Error(); setError(false); onSave(parsed); } catch { setError(true); } }}><Save size={12} />{t("UI.applyJson")}</button></details>;
}
