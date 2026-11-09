import { type ReactNode, useEffect, useMemo, useState } from "react";
import {
  Camera, CheckCircle2, ChevronDown, ChevronLeft, ChevronUp, Clapperboard, Copy, Crosshair, Move, MousePointer2,
  Play, Plus, Save, Search, Sparkles, Trash2, X,
} from "lucide-react";
import { fetchNui } from "./nui";
import { filterLibrary, KIND_LABEL, type EntityKind, type ModelLibrary } from "./lib";
import type { SceneDraft } from "./types";
import "./creator.css";

const creatorAction = (action: string, payload: unknown = {}) => fetchNui("multichar:creator:action", { action, payload });

type Tab = "scene" | "cameras" | "timeline";
const KINDS: EntityKind[] = ["ped", "vehicle", "prop"];

export function CreatorScreen({ draft, scenes, cursor, exported, library, placing, focusId }: {
  draft: SceneDraft; scenes: Record<string, SceneDraft>; cursor: boolean; exported: string | null;
  library: ModelLibrary; placing: boolean; focusId: string | null;
}) {
  const [tab, setTab] = useState<Tab>("scene");
  const [picking, setPicking] = useState<EntityKind | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  useEffect(() => { if (focusId) { setSelected(focusId); setPicking(null); } }, [focusId]);
  useEffect(() => { if (selected && !draft.entities.some((entity) => entity.id === selected)) setSelected(null); }, [draft.entities, selected]);
  const sceneOptions = useMemo(() => Object.keys(scenes).sort(), [scenes]);

  if (placing) return null;

  return <div className="studio">
    <header className="studio-top panel">
      <div><span className="eyebrow">Cinematic tools</span><h2>Scene Studio</h2></div>
      <select aria-label="Scene" value={scenes[draft.id] ? draft.id : ""} onChange={(event) => event.target.value && creatorAction("load", { id: event.target.value })}><option value="">Unsaved draft</option>{sceneOptions.map((id) => <option key={id} value={id}>{scenes[id].label} · {id}</option>)}</select>
      <button className="button ghost" onClick={() => creatorAction("new")}><Plus size={15} />New</button>
      <button className="button ghost" onClick={() => creatorAction("duplicate")}><Copy size={15} />Duplicate</button>
      <button className={`button ${cursor ? "ghost" : "primary"}`} title="Tab" onClick={() => creatorAction("toggleMode")}><MousePointer2 size={15} />{cursor ? "Fly camera" : "Back to editing"}<kbd>Tab</kbd></button>
      <button className="icon-button" aria-label="Close studio" onClick={() => creatorAction("close")}><X /></button>
    </header>

    <aside className="studio-panel panel">
      {picking
        ? <ModelPicker kind={picking} library={library} onBack={() => setPicking(null)} onPick={(model) => { creatorAction("addEntity", { type: picking, model }); setPicking(null); }} />
        : <>
          <div className="add-row" role="group" aria-label="Add to scene">
            {KINDS.map((kind) => <button key={kind} className="button primary" onClick={() => setPicking(kind)}><Plus size={15} />{KIND_LABEL[kind]}</button>)}
          </div>
          <EntityList draft={draft} selected={selected} onSelect={(id) => setSelected(selected === id ? null : id)} />
          <nav className="studio-tabs" role="tablist" aria-label="Scene settings">
            {([["scene", "Scene"], ["cameras", `Cameras · ${draft.cameras.length}`], ["timeline", "Timeline"]] as const).map(([id, label]) =>
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
      <button className="button ghost" onClick={() => creatorAction("validate")}><CheckCircle2 size={15} />Validate</button>
      <button className="button ghost" onClick={() => creatorAction("preview")}><Play size={15} />Play timeline</button>
      <button className="button ghost" onClick={() => creatorAction("exportRegister")}><Copy size={15} />Copy registration</button>
      <button className="button primary" onClick={() => creatorAction("exportConfig")}><Copy size={15} />Copy config</button>
      {exported && <span className="export-toast">{exported}</span>}
    </footer>
  </div>;
}

function ModelPicker({ kind, library, onBack, onPick }: { kind: EntityKind; library: ModelLibrary; onBack: () => void; onPick: (model: string) => void }) {
  const [query, setQuery] = useState("");
  const { matches, custom } = filterLibrary(library, kind, query);
  return <form className="picker" onSubmit={(event) => {
    event.preventDefault();
    const first = matches[0]?.[0] ?? custom;
    if (first) onPick(first);
  }} onKeyDown={(event) => { if (event.key === "Escape") { event.stopPropagation(); onBack(); } }}>
    <div className="picker-head">
      <button type="button" className="icon-button" aria-label="Back" onClick={onBack}><ChevronLeft size={16} /></button>
      <h3>Add {KIND_LABEL[kind].toLowerCase()}</h3>
    </div>
    <label className="picker-search"><Search size={14} /><input autoFocus aria-label="Search models" placeholder="Search, or type a model name" value={query} onChange={(event) => setQuery(event.target.value)} /></label>
    <ul className="picker-list">
      {matches.map(([model, label]) => <li key={model}><button type="button" onClick={() => onPick(model)}><strong>{label}</strong><small>{model}</small></button></li>)}
      {custom && <li><button type="button" className="custom" onClick={() => onPick(custom)}><strong>Use “{custom}”</strong><small>Any model name from the game</small></button></li>}
      {!matches.length && !custom && <li className="picker-empty">No models in the list.</li>}
    </ul>
  </form>;
}

function EntityList({ draft, selected, onSelect }: { draft: SceneDraft; selected: string | null; onSelect: (id: string) => void }) {
  if (!draft.entities.length) return <p className="empty-hint">Nothing here yet. Add a ped, vehicle or prop and it appears at your crosshair.</p>;
  return <ul className="entity-list" aria-label="Scene entities">
    {draft.entities.map((entity, index) => {
      const open = selected === entity.id;
      return <li key={entity.id} className={open ? "on" : undefined}>
        <button className="entity-row" aria-expanded={open} onClick={() => onSelect(entity.id)}>
          <span><strong>{entity.id}</strong><small>{entity.type} · {String(entity.model)}</small></span>
        </button>
        {open && <div className="entity-detail">
          <div className="entity-actions">
            <button className="button primary" onClick={() => creatorAction("moveEntity", { id: entity.id })}><Move size={15} />Move</button>
            <div className="row-tools">
              <button aria-label={`Move ${entity.id} up`} disabled={index === 0} onClick={() => creatorAction("reorderEntity", { index: index + 1, delta: -1 })}><ChevronUp size={14} /></button>
              <button aria-label={`Move ${entity.id} down`} disabled={index === draft.entities.length - 1} onClick={() => creatorAction("reorderEntity", { index: index + 1, delta: 1 })}><ChevronDown size={14} /></button>
              <button aria-label={`Delete ${entity.id}`} onClick={() => creatorAction("removeEntity", { id: entity.id })}><Trash2 size={14} /></button>
            </div>
          </div>
          <JsonEditor label="Advanced" value={entity} onSave={(value) => creatorAction("replaceEntity", { originalId: entity.id, value })} />
        </div>}
      </li>;
    })}
  </ul>;
}

function SceneTab({ draft }: { draft: SceneDraft }) {
  const [selectorText, setSelectorText] = useState(JSON.stringify(draft.selectors ?? [], null, 2));
  useEffect(() => setSelectorText(JSON.stringify(draft.selectors ?? [], null, 2)), [draft.id, draft.selectors]);
  return <>
    <CreatorSection title="Scene" icon={<Clapperboard size={15} />}>
      <form onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); try { creatorAction("metadata", { id: form.get("id"), label: form.get("label"), priority: Number(form.get("priority")), selectors: JSON.parse(selectorText) }); } catch {  } }}>
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
    <button className="wide-tool" onClick={() => creatorAction("setAnchor")}><Crosshair size={15} />Set anchor at crosshair</button>
    <button className="wide-tool" onClick={() => creatorAction("placeCharacter")}><Crosshair size={15} />Place character at crosshair</button>
  </>;
}

function CamerasTab({ draft }: { draft: SceneDraft }) {
  return <CreatorSection title={`Cameras · ${draft.cameras.length}`} icon={<Camera size={15} />}>
    <div className="object-list">{draft.cameras.map((camera, index) => <div className="object-editor" key={camera.id}>
      <div className="object-row"><span><strong>{camera.id}</strong><small>FOV {String(camera.fov ?? 45)}</small></span><div className="row-tools">
        <button aria-label={`Move ${camera.id} up`} disabled={index === 0} onClick={() => creatorAction("reorderCamera", { index: index + 1, delta: -1 })}><ChevronUp size={13} /></button>
        <button aria-label={`Move ${camera.id} down`} disabled={index === draft.cameras.length - 1} onClick={() => creatorAction("reorderCamera", { index: index + 1, delta: 1 })}><ChevronDown size={13} /></button>
        <button aria-label={`Delete ${camera.id}`} disabled={draft.cameras.length <= 1} onClick={() => creatorAction("removeCamera", { id: camera.id })}><Trash2 size={13} /></button>
      </div></div>
      <JsonEditor label="Edit camera data" value={camera} onSave={(value) => creatorAction("replaceCamera", { index: index + 1, value })} />
    </div>)}</div>
    <form className="inline-add" onSubmit={(event) => { event.preventDefault(); const form = new FormData(event.currentTarget); creatorAction("captureCamera", { id: form.get("id"), fov: Number(form.get("fov")), transitionMs: 900 }); }}><input name="id" placeholder="shot_id" required /><input name="fov" type="number" min="10" max="100" defaultValue="45" /><button className="mini-button"><Camera size={13} />Capture</button></form>
  </CreatorSection>;
}

function TimelineTab({ draft }: { draft: SceneDraft }) {
  const [cueText, setCueText] = useState('{"at":5200,"type":"camera","camera":"establishing","transitionMs":2400}');
  const [scrub, setScrub] = useState(0);
  return <CreatorSection title="Timeline" icon={<Clapperboard size={15} />}>
    <div className="timeline-heading"><label>Duration <input type="number" defaultValue={draft.timeline.durationMs} onBlur={(event) => creatorAction("timeline", { durationMs: Number(event.target.value), loop: draft.timeline.loop })} /></label><label className="check"><input type="checkbox" checked={draft.timeline.loop} onChange={(event) => creatorAction("timeline", { durationMs: draft.timeline.durationMs, loop: event.target.checked })} />Loop</label></div>
    <input className="scrubber" aria-label="Scrub timeline" type="range" min="0" max={draft.timeline.durationMs || 1} value={scrub} onChange={(event) => { const at = Number(event.target.value); setScrub(at); creatorAction("scrub", { at }); }} />
    <div className="cue-list">{draft.timeline.cues.map((cue, i) => <div className="cue-editor" key={`${String(cue.type)}-${i}`}>
      <div className="cue"><b>{Number(cue.at ?? 0) / 1000}s</b><span>{String(cue.type)}</span><div className="row-tools">
        <button aria-label="Move cue up" disabled={i === 0} onClick={() => creatorAction("reorderCue", { index: i + 1, delta: -1 })}><ChevronUp size={12} /></button>
        <button aria-label="Move cue down" disabled={i === draft.timeline.cues.length - 1} onClick={() => creatorAction("reorderCue", { index: i + 1, delta: 1 })}><ChevronDown size={12} /></button>
        <button aria-label="Delete cue" onClick={() => creatorAction("removeCue", { index: i + 1 })}><X size={12} /></button>
      </div></div>
      <JsonEditor label="Edit cue data" value={cue} onSave={(value) => creatorAction("replaceCue", { index: i + 1, value })} />
    </div>)}</div>
    <div className="cue-add"><input value={cueText} onChange={(event) => setCueText(event.target.value)} /><button className="mini-button" onClick={() => { try { creatorAction("addCue", JSON.parse(cueText)); } catch {  } }}><Plus size={13} />Add cue JSON</button></div>
  </CreatorSection>;
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
