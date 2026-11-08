// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from './App';
import { SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS } from './lib';

const nui = vi.hoisted(() => ({
  fetch: vi.fn(() => Promise.resolve({})),
}));

vi.mock('./nui', () => ({ fetchNui: nui.fetch }));

function message(action: string, data: unknown) {
  act(() => window.dispatchEvent(new MessageEvent('message', { data: { action, data } })));
}

const jane = {
  citizenid: 'JANE1', cid: 1,
  charinfo: { firstname: 'Jane', lastname: 'Doe', birthdate: '2000-02-29', nationality: 'Canada' },
  job: { name: 'police', label: 'Police', grade: { level: 3, name: 'Sergeant' }, onduty: true },
  gang: { name: 'ballas', label: 'Ballas', grade: { level: 1, name: 'Soldier' } },
  money: { cash: 250, bank: 12500 },
};

beforeEach(() => {
  vi.useFakeTimers();
  nui.fetch.mockClear();
  nui.fetch.mockImplementation(() => Promise.resolve({}));
});

afterEach(() => {
  cleanup();
  vi.runOnlyPendingTimers();
  vi.useRealTimers();
});

describe('character selection', () => {
  it('previews after the debounce but logs in only when Continue is pressed', () => {
    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 2 });
    expect(screen.getByRole('heading', { name: 'Jane Doe' })).toBeTruthy();
    expect(screen.getByText('Setting your scene')).toBeTruthy();
    expect(nui.fetch).not.toHaveBeenCalledWith('multichar:select', expect.anything());

    act(() => vi.advanceTimersByTime(121));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:preview', { citizenid: 'JANE1' });

    message('multichar:previewReady', { scene: 'police', ok: true });
    expect(screen.queryByText('Setting your scene')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: /continue/i }));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:select', { citizenid: 'JANE1' });
  });

  it('lists every slot on the right, names the character or free slot each arrow leads to, and disables the arrows with a single slot', () => {
    const bob = { ...jane, citizenid: 'BOB2', cid: 2, charinfo: { ...jane.charinfo, firstname: 'Bob' } };
    const { unmount } = render(<App />);
    message('multichar:show', { characters: [jane, bob], maxCharacters: 3 });
    expect(screen.getByTestId('slot-rail').textContent).toBe('Jane DoeBob DoeNew character');
    expect(document.querySelector('.profile-count')?.textContent).toBe('1 of 3');
    expect(screen.getByRole('button', { name: 'Next, Character 2: Bob Doe' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Previous, Character 3: Create New Character' })).toBeTruthy();
    unmount();

    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 1 });
    expect(screen.getByTestId('slot-rail').textContent).toBe('Jane Doe');
    expect((screen.getByRole('button', { name: 'Next' }) as HTMLButtonElement).disabled).toBe(true);
  });

  it('labels profile cards from config and hides empty descriptions', () => {
    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 1 });
    fireEvent.click(screen.getByRole('button', { name: /profile/i }));
    expect(screen.getByText('Citizen ID')).toBeTruthy();
    expect(screen.queryByText('Citizen record')).toBeNull();
    expect(screen.queryByText('Registered identity')).toBeNull();
    expect(screen.queryByText('Permanent identifier')).toBeNull();
    expect(screen.getByText('Place of origin')).toBeTruthy();
    expect(screen.getByText('2000-02-29').parentElement?.querySelector('em')).toBeNull();
  });

  it('applies configured profile text', () => {
    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 1, ui: { profile: { birthDate: { label: 'DOB', description: 'Born' }, citizenId: { label: 'State ID', description: '' } } } });
    fireEvent.click(screen.getByRole('button', { name: /profile/i }));
    expect(screen.getByText('DOB')).toBeTruthy();
    expect(screen.getByText('Born')).toBeTruthy();
    expect(screen.getByText('State ID')).toBeTruthy();
  });

  it('shows dossier fields and requires the exact typed name before deletion', () => {
    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 1 });
    expect(screen.getByRole('heading', { name: 'Jane Doe' })).toBeTruthy();
    expect(document.querySelector('.profile-count')?.textContent).toBe('1 of 1');
    fireEvent.click(screen.getByRole('button', { name: /profile/i }));

    for (const value of ['Police', 'Sergeant', 'Ballas', 'Soldier', '$12,500 bank', '$250 cash', '2000-02-29', 'Canada', 'JANE1']) {
      expect(screen.getAllByText(value).length).toBeGreaterThan(0);
    }

    fireEvent.click(screen.getByRole('button', { name: /delete character/i }));
    const confirm = screen.getByRole('button', { name: /delete forever/i }) as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Character name'), { target: { value: 'Jane' } });
    expect(confirm.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Character name'), { target: { value: 'Jane Doe' } });
    expect(confirm.disabled).toBe(false);
    fireEvent.click(confirm);
    expect(nui.fetch).toHaveBeenCalledWith('multichar:delete', { citizenid: 'JANE1' });
  });

  it('collects the complete validated identity payload', () => {
    render(<App />);
    message('multichar:show', { characters: [], maxCharacters: 1 });
    act(() => vi.advanceTimersByTime(121));
    message('multichar:previewReady', { scene: 'civilian', ok: true });
    fireEvent.click(screen.getByRole('button', { name: /^create$/i }));

    fireEvent.change(screen.getByLabelText('First name'), { target: { value: 'Alex' } });
    fireEvent.change(screen.getByLabelText('Last name'), { target: { value: 'Rivera' } });
    fireEvent.change(screen.getByLabelText('Birth date'), { target: { value: '2001-04-25' } });
    fireEvent.change(screen.getByLabelText('Nationality'), { target: { value: 'Mexico' } });
    fireEvent.click(screen.getByRole('button', { name: 'Female' }));
    fireEvent.click(screen.getByRole('button', { name: /create identity/i }));

    expect(nui.fetch).toHaveBeenCalledWith('multichar:create', {
      firstname: 'Alex', lastname: 'Rivera', birthdate: '2001-04-25', nationality: 'Mexico', gender: 1,
    });
  });

  it('handles focused NUI keyboard navigation and acceptance', () => {
    const bob = { ...jane, citizenid: 'BOB2', cid: 2, charinfo: { ...jane.charinfo, firstname: 'Bob' } };
    render(<App />);
    message('multichar:show', { characters: [jane, bob], maxCharacters: 2 });
    fireEvent.keyDown(window, { key: 'ArrowRight' });
    expect(screen.getByRole('heading', { name: 'Bob Doe' })).toBeTruthy();
    message('multichar:previewReady', { scene: 'police', ok: true });
    fireEvent.keyDown(window, { key: 'Enter' });
    expect(nui.fetch).toHaveBeenCalledWith('multichar:select', { citizenid: 'BOB2' });
  });
});

describe('spawn and studio', () => {
  it('focuses the selected live spawn without obscuring the scene, allows Escape, and confirms explicitly', async () => {
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true });
    expect(document.querySelector('.vignette')).toBeNull();
    expect(nui.fetch).toHaveBeenCalledWith('multichar:spawn:focus', { id: 'legion' });
    expect(screen.getByText('Scouting your arrival')).toBeTruthy();
    await act(async () => { await Promise.resolve(); });
    expect(screen.queryByText('Scouting your arrival')).toBeNull();

    fireEvent.keyDown(window, { key: 'Escape' });
    expect(nui.fetch).toHaveBeenCalledWith('multichar:spawn:exit');
    fireEvent.click(screen.getByRole('button', { name: /spawn here/i }));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:spawn:choose', { id: 'legion' });
  });

  it('keeps destination flyovers visible and lets navigation supersede them', async () => {
    const resolutions: Array<(value: { ok?: boolean }) => void> = [];
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? new Promise((resolve) => resolutions.push(resolve))
      : Promise.resolve({}));
    render(<App />);
    message('multichar:spawn:locations', { locations: [
      { id: 'legion', label: 'Legion Square', description: 'City centre' },
      { id: 'paleto', label: 'Paleto Bay', description: 'North coast' },
    ] });
    message('multichar:spawn:show', { visible: true, settleMs: 0, lockWhileMoving: false });

    await act(async () => { resolutions.shift()?.({ ok: true }); await Promise.resolve(); });
    fireEvent.click(screen.getByRole('button', { name: 'Next location' }));
    expect(screen.getByRole('heading', { name: 'Paleto Bay' })).toBeTruthy();
    expect(screen.getByRole('status').textContent).toContain('Flying to Paleto Bay');
    expect(screen.queryByText('Scouting your arrival')).toBeNull();
    expect((screen.getByRole('button', { name: 'Next location' }) as HTMLButtonElement).disabled).toBe(false);

    await act(async () => { resolutions.shift()?.({ ok: true }); await Promise.resolve(); });
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('ignores location switches inside the cooldown for buttons and A/D/arrow keys alike, and shows key hints', async () => {
    let clock = 1_000_000;
    const now = vi.spyOn(Date, 'now').mockImplementation(() => clock);
    render(<App />);
    message('multichar:spawn:locations', { locations: [
      { id: 'a', label: 'Alpha', description: '' },
      { id: 'b', label: 'Bravo', description: '' },
      { id: 'c', label: 'Charlie', description: '' },
    ] });
    message('multichar:spawn:show', { visible: true, switchCooldownMs: 600, hints: { next: 'Weiter' } });
    await act(async () => { await Promise.resolve(); });
    expect(screen.getByText('Weiter')).toBeTruthy();
    expect(screen.getByText('A')).toBeTruthy();
    expect(screen.getByText('D')).toBeTruthy();

    fireEvent.keyDown(window, { key: 'd' });
    fireEvent.keyDown(window, { key: 'd' });
    fireEvent.keyDown(window, { key: 'ArrowRight' });
    fireEvent.click(screen.getByRole('button', { name: 'Next location' }));
    expect(screen.getByRole('heading', { name: 'Bravo' })).toBeTruthy();
    clock += 601;
    fireEvent.keyDown(window, { key: 'a' });
    expect(screen.getByRole('heading', { name: 'Alpha' })).toBeTruthy();
    now.mockRestore();
  });

  it('browses freely but flies only once the player settles, and locks switching until the camera arrives', async () => {
    const resolutions: Array<(value: { ok?: boolean }) => void> = [];
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? new Promise((resolve) => resolutions.push(resolve))
      : Promise.resolve({}));
    const focusCalls = () => nui.fetch.mock.calls
      .filter((call: unknown[]) => call[0] === 'multichar:spawn:focus')
      .map((call: unknown[]) => (call[1] as { id: string }).id);
    render(<App />);
    message('multichar:spawn:locations', { locations: [
      { id: 'a', label: 'Alpha', description: '' },
      { id: 'b', label: 'Bravo', description: '' },
      { id: 'c', label: 'Charlie', description: '' },
    ] });
    message('multichar:spawn:show', { visible: true, switchCooldownMs: 0, settleMs: 1000, lockWhileMoving: true });
    expect(focusCalls()).toEqual(['a']);
    await act(async () => { resolutions.shift()?.({ ok: true }); await Promise.resolve(); });

    // Rapid browsing: the label follows every press, the camera does nothing.
    fireEvent.keyDown(window, { key: 'd' });
    fireEvent.keyDown(window, { key: 'ArrowRight' });
    expect(screen.getByRole('heading', { name: 'Charlie' })).toBeTruthy();
    act(() => vi.advanceTimersByTime(999));
    expect(focusCalls()).toEqual(['a']);
    act(() => vi.advanceTimersByTime(1));
    expect(focusCalls()).toEqual(['a', 'c']);

    // Locked while flying.
    expect(screen.getByRole('status').textContent).toContain('Flying to Charlie');
    expect((screen.getByRole('button', { name: 'Next location' }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.keyDown(window, { key: 'd' });
    expect(screen.getByRole('heading', { name: 'Charlie' })).toBeTruthy();
    await act(async () => { resolutions.shift()?.({ ok: true }); await Promise.resolve(); });
    expect((screen.getByRole('button', { name: 'Next location' }) as HTMLButtonElement).disabled).toBe(false);

    // Browsing away and back to the shown place costs no flight.
    fireEvent.keyDown(window, { key: 'd' });
    fireEvent.keyDown(window, { key: 'a' });
    act(() => vi.advanceTimersByTime(2000));
    expect(focusCalls()).toEqual(['a', 'c']);

    // Spawning during the wait goes straight to the pick, with no flight after.
    fireEvent.keyDown(window, { key: 'd' });
    expect(screen.getByRole('heading', { name: 'Alpha' })).toBeTruthy();
    fireEvent.keyDown(window, { key: 'Enter' });
    expect(nui.fetch).toHaveBeenCalledWith('multichar:spawn:choose', { id: 'a' });
    act(() => vi.advanceTimersByTime(2000));
    expect(focusCalls()).toEqual(['a', 'c']);
  });

  it('releases the spawn selector when an arrival preview fails', async () => {
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? Promise.resolve({ ok: false })
      : Promise.resolve({}));
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true });

    await act(async () => { await Promise.resolve(); });
    expect(screen.queryByText('Scouting your arrival')).toBeNull();
    expect(screen.getByText('That arrival could not be previewed. You can still spawn here.')).toBeTruthy();
    expect((screen.getByRole('button', { name: /spawn here/i }) as HTMLButtonElement).disabled).toBe(false);
  });

  it('waits out the preview budget Lua reported before calling an arrival timed out', async () => {
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? new Promise(() => {})
      : Promise.resolve({}));
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true, previewBudgetMs: 40_000 });

    // Lua is still legitimately working here -- a preview allowed 40s must not
    // be declared broken at 15s, which is what the old hardcoded timeout did
    // to every slow world stream.
    await act(async () => { vi.advanceTimersByTime(20_000); await Promise.resolve(); });
    expect(screen.getByText('Scouting your arrival')).toBeTruthy();
    expect(screen.queryByText('Arrival preview timed out. You can still spawn here.')).toBeNull();

    await act(async () => { vi.advanceTimersByTime(30_000); await Promise.resolve(); });
    expect(screen.queryByText('Scouting your arrival')).toBeNull();
    expect(screen.getByText('Arrival preview timed out. You can still spawn here.')).toBeTruthy();
    expect((screen.getByRole('button', { name: /spawn here/i }) as HTMLButtonElement).disabled).toBe(false);
  });

  it('releases the spawn selector even when no preview budget was reported', async () => {
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? new Promise(() => {})
      : Promise.resolve({}));
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true });

    await act(async () => { vi.advanceTimersByTime(SPAWN_PREVIEW_FALLBACK_TIMEOUT_MS); await Promise.resolve(); });
    expect(screen.queryByText('Scouting your arrival')).toBeNull();
    expect((screen.getByRole('button', { name: /spawn here/i }) as HTMLButtonElement).disabled).toBe(false);
  });

  it('drops the cover as soon as Lua says the camera is live, without waiting for the callback', async () => {
    // This is the "stuck on Scouting your arrival" report. The focus callback
    // only answers once the whole preview has settled, and the NUI races it
    // against a budget derived from the real worst case -- over a minute. The
    // camera is usually live long before that, so the cover has to come down on
    // Lua's own signal rather than on the answer.
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? new Promise(() => {})
      : Promise.resolve({}));
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true, previewBudgetMs: 70_000 });

    expect(screen.getByText('Scouting your arrival')).toBeTruthy();

    await act(async () => { message('multichar:spawn:previewLive', { generation: 1 }); await Promise.resolve(); });

    expect(screen.queryByText('Scouting your arrival')).toBeNull();
    expect((screen.getByRole('button', { name: /spawn here/i }) as HTMLButtonElement).disabled).toBe(false);

    // And the still-pending callback must not then report a timeout for a
    // preview the player has already been looking at.
    await act(async () => { vi.advanceTimersByTime(80_000); await Promise.resolve(); });
    expect(screen.queryByText('Arrival preview timed out. You can still spawn here.')).toBeNull();
  });

  it('names what a long preview is waiting on instead of one fixed line', async () => {
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? new Promise(() => {})
      : Promise.resolve({}));
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true, previewBudgetMs: 70_000 });

    expect(screen.getByText(/Streaming the world and finding a clear camera angle/i)).toBeTruthy();

    await act(async () => { message('multichar:spawn:previewStage', { stage: 'streaming' }); await Promise.resolve(); });
    expect(screen.getByText('Streaming the area around your arrival point')).toBeTruthy();

    // An unknown stage falls back to the generic line rather than rendering
    // nothing -- a blank subtitle reads as a broken panel.
    await act(async () => { message('multichar:spawn:previewStage', { stage: 'something-new' }); await Promise.resolve(); });
    expect(screen.getByText(/Streaming the world and finding a clear camera angle/i)).toBeTruthy();
  });

  it('stays silent when a preview is superseded by the next one the player picks', async () => {
    nui.fetch.mockImplementation((...args: unknown[]) => args[0] === 'multichar:spawn:focus'
      ? Promise.resolve({ ok: false, reason: 'superseded' })
      : Promise.resolve({}));
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true });

    await act(async () => { await Promise.resolve(); });
    expect(screen.queryByText('Scouting your arrival')).toBeNull();
    expect(screen.queryByText('That arrival could not be previewed. You can still spawn here.')).toBeNull();
    expect((screen.getByRole('button', { name: /spawn here/i }) as HTMLButtonElement).disabled).toBe(false);
  });

  it('sends scene metadata and placement edits through the studio action channel', () => {
    const draft = {
      id: 'test_scene', label: 'Test Scene', priority: 0, selectors: [], environment: { hour: 18, minute: 0, weather: 'CLEAR' },
      character: { offset: { x: 0, y: 0, z: 0, w: 0 } }, entities: [],
      cameras: [{ id: 'hero', offset: { x: 1, y: 1, z: 1 }, lookAt: { x: 0, y: 0, z: 0 } }],
      timeline: { durationMs: 10000, loop: true, cues: [{ at: 0, type: 'camera', camera: 'hero' }] },
    };
    render(<App />);
    message('multichar:creator:show', { draft, scenes: {}, cursor: true });

    const label = screen.getByDisplayValue('Test Scene');
    fireEvent.change(label, { target: { value: 'Edited Scene' } });
    fireEvent.submit(label.closest('form')!);
    expect(nui.fetch).toHaveBeenCalledWith('multichar:creator:action', {
      action: 'metadata', payload: { id: 'test_scene', label: 'Edited Scene', priority: 0, selectors: [] },
    });

    fireEvent.click(screen.getByRole('button', { name: /place character/i }));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:creator:action', { action: 'placeCharacter', payload: {} });
  });

  describe('scene studio add flow', () => {
    const draft = {
      id: 'test_scene', label: 'Test Scene', priority: 0, selectors: [], environment: { hour: 18, minute: 0, weather: 'CLEAR' },
      character: { offset: { x: 0, y: 0, z: 0, w: 0 } },
      entities: [{ id: 'prop_1', type: 'prop', model: 'prop_tool_box_04', offset: { x: 1, y: 2, z: 0, w: 0 } }],
      cameras: [{ id: 'hero', offset: { x: 1, y: 1, z: 1 }, lookAt: { x: 0, y: 0, z: 0 } }],
      timeline: { durationMs: 10000, loop: true, cues: [] },
    };
    const library = { ped: [['s_m_y_cop_01', 'Police officer'], ['a_m_y_skater_01', 'Skater']], vehicle: [['sultan', 'Sultan']], prop: [['prop_tool_box_04', 'Toolbox']] };
    const open = () => { render(<App />); message('multichar:creator:show', { draft, scenes: {}, cursor: true, library }); nui.fetch.mockClear(); };

    it('adds from the list with only a type and a model: no id or type to type', () => {
      open();
      fireEvent.click(screen.getByRole('button', { name: /^ped$/i }));
      fireEvent.click(screen.getByRole('button', { name: /police officer/i }));
      expect(nui.fetch).toHaveBeenCalledWith('multichar:creator:action', { action: 'addEntity', payload: { type: 'ped', model: 's_m_y_cop_01' } });
      expect(screen.queryByLabelText('Search models')).toBeNull();
    });

    it('filters the list and accepts any typed model name with Enter', () => {
      open();
      fireEvent.click(screen.getByRole('button', { name: /^vehicle$/i }));
      const search = screen.getByLabelText('Search models');
      fireEvent.change(search, { target: { value: 'zentorno' } });
      expect(screen.queryByRole('button', { name: /sultan/i })).toBeNull();
      fireEvent.submit(search.closest('form')!);
      expect(nui.fetch).toHaveBeenCalledWith('multichar:creator:action', { action: 'addEntity', payload: { type: 'vehicle', model: 'zentorno' } });
    });

    it('Escape and Back leave the picker without adding anything', () => {
      open();
      fireEvent.click(screen.getByRole('button', { name: /^prop$/i }));
      fireEvent.keyDown(screen.getByLabelText('Search models'), { key: 'Escape' });
      expect(screen.queryByLabelText('Search models')).toBeNull();
      expect(nui.fetch).not.toHaveBeenCalled();
    });

    it('selects an entity to reveal Move, and Move sends the id', () => {
      open();
      expect(screen.queryByRole('button', { name: /^move$/i })).toBeNull();
      fireEvent.click(screen.getByRole('button', { name: /prop_1/ }));
      fireEvent.click(screen.getByRole('button', { name: /^move$/i }));
      expect(nui.fetch).toHaveBeenCalledWith('multichar:creator:action', { action: 'moveEntity', payload: { id: 'prop_1' } });
    });

    it('selects the entity Lua just added and steps aside while the placement tool runs', () => {
      open();
      message('multichar:creator:state', { draft, selected: 'prop_1' });
      expect(screen.getByRole('button', { name: /^move$/i })).toBeTruthy();
      message('multichar:creator:state', { draft, placing: true });
      expect(screen.queryByText('Scene Studio')).toBeNull();
      message('multichar:creator:state', { draft, placing: false });
      expect(screen.getByText('Scene Studio')).toBeTruthy();
    });

    it('keeps cameras and timeline one tab away', () => {
      open();
      fireEvent.click(screen.getByRole('tab', { name: /cameras/i }));
      expect(screen.getByText('hero')).toBeTruthy();
      fireEvent.click(screen.getByRole('tab', { name: /timeline/i }));
      expect(screen.getByLabelText('Scrub timeline')).toBeTruthy();
    });
  });

  it('does not softlock on the loading cover when a brand-new account browses its single slide', () => {
    render(<App />);
    message('multichar:show', { characters: [], maxCharacters: 1 });
    act(() => vi.advanceTimersByTime(121));
    message('multichar:previewReady', { scene: 'civilian', ok: true });
    nui.fetch.mockClear();

    for (const key of ['ArrowRight', 'ArrowLeft', 'd', 'a']) fireEvent.keyDown(window, { key });
    expect(screen.queryByText('Setting your scene')).toBeNull();
    act(() => vi.advanceTimersByTime(500));
    expect(nui.fetch).not.toHaveBeenCalled();

    fireEvent.keyDown(window, { key: 'Enter' });
    expect(screen.getByLabelText('First name')).toBeTruthy();
  });

  it('still browses between several characters', () => {
    const bob = { ...jane, citizenid: 'BOB2', cid: 2 };
    render(<App />);
    message('multichar:show', { characters: [jane, bob], maxCharacters: 2 });
    act(() => vi.advanceTimersByTime(121));
    message('multichar:previewReady', { scene: 'civilian', ok: true });
    fireEvent.keyDown(window, { key: 'ArrowRight' });
    expect(screen.getByText('Setting your scene')).toBeTruthy();
    act(() => vi.advanceTimersByTime(121));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:preview', { citizenid: 'BOB2' });
  });

  it('clears a preview that never resolves after the configured watchdog', () => {
    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 1, previewWatchdogMs: 5000 });
    expect(screen.getByText('Setting your scene')).toBeTruthy();
    act(() => vi.advanceTimersByTime(4999));
    expect(screen.getByText('Setting your scene')).toBeTruthy();
    act(() => vi.advanceTimersByTime(2));
    expect(screen.queryByText('Setting your scene')).toBeNull();
    expect(screen.getByText('The scene preview took too long to load.')).toBeTruthy();
  });

  it('keeps the watchdog off when disabled', () => {
    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 1, previewWatchdogMs: 0 });
    act(() => vi.advanceTimersByTime(60000));
    expect(screen.getByText('Setting your scene')).toBeTruthy();
  });

  describe('create identity dialog', () => {
    function openCreate(ui?: { closeCreateOnBackdrop: boolean }) {
      render(<App />);
      message('multichar:show', { characters: [], maxCharacters: 1, ui });
      act(() => vi.advanceTimersByTime(121));
      message('multichar:previewReady', { scene: 'civilian', ok: true });
      fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
      fireEvent.change(screen.getByLabelText('First name'), { target: { value: 'Alex' } });
    }

    it('shows an inline error instead of the native bubble when the first name is empty', () => {
      openCreate();
      fireEvent.change(screen.getByLabelText('First name'), { target: { value: '' } });
      nui.fetch.mockClear();
      expect(document.querySelector<HTMLFormElement>('.create-modal')!.noValidate).toBe(true);
      fireEvent.click(screen.getByRole('button', { name: /create identity/i }));
      const input = screen.getByLabelText('First name') as HTMLInputElement;
      const alert = document.getElementById('create-firstname-error')!;
      expect(alert.getAttribute('role')).toBe('alert');
      expect(alert.textContent).toBe('Enter a first name.');
      expect(input.getAttribute('aria-invalid')).toBe('true');
      expect(input.getAttribute('aria-describedby')).toBe(alert.id);
      expect(document.activeElement).toBe(input);
      expect(nui.fetch).not.toHaveBeenCalledWith('multichar:create', expect.anything());
      fireEvent.change(input, { target: { value: 'A' } });
      expect(document.getElementById('create-firstname-error')).toBeNull();
      expect(input.getAttribute('aria-invalid')).toBe('false');
    });

    it('ignores backdrop clicks by default', () => {
      openCreate();
      fireEvent.click(document.querySelector('.modal-backdrop')!);
      expect((screen.getByLabelText('First name') as HTMLInputElement).value).toBe('Alex');
    });

    it('closes on backdrop click when enabled and restores the typed values on reopen', () => {
      openCreate({ closeCreateOnBackdrop: true });
      fireEvent.click(document.querySelector('.modal-backdrop')!);
      expect(screen.queryByLabelText('First name')).toBeNull();
      // Closing restarts the carousel preview, which must finish before Create is enabled.
      act(() => vi.advanceTimersByTime(121));
      message('multichar:previewReady', { scene: 'civilian', ok: true });
      fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
      expect((screen.getByLabelText('First name') as HTMLInputElement).value).toBe('Alex');
    });

    it('asks in the page, never via window.confirm, before X or Escape discards typed data', () => {
      // The game browser answers window.confirm with "no"; the dialog must not depend on it.
      const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
      openCreate();
      fireEvent.click(screen.getByRole('button', { name: 'Close' }));
      expect(screen.getByText('Discard the identity details you entered?')).toBeTruthy();
      fireEvent.click(screen.getByRole('button', { name: 'Keep editing' }));
      expect((screen.getByLabelText('First name') as HTMLInputElement).value).toBe('Alex');

      fireEvent.keyDown(window, { key: 'Escape' });
      expect(screen.getByText('Discard the identity details you entered?')).toBeTruthy();
      fireEvent.keyDown(window, { key: 'Escape' });
      expect(screen.queryByText('Discard the identity details you entered?')).toBeNull();

      fireEvent.keyDown(window, { key: 'Escape' });
      fireEvent.click(screen.getByRole('button', { name: 'Discard' }));
      expect(screen.queryByLabelText('First name')).toBeNull();
      expect(confirm).not.toHaveBeenCalled();
      confirm.mockRestore();
    });

    it('asks before disconnecting and only disconnects on confirm', () => {
      render(<App />);
      message('multichar:show', { characters: [], maxCharacters: 1, ui: {} });
      act(() => vi.advanceTimersByTime(121));
      fireEvent.click(screen.getByRole('button', { name: 'Disconnect' }));
      expect(nui.fetch).not.toHaveBeenCalledWith('multichar:disconnect');
      fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
      expect(screen.queryByRole('alertdialog', { name: 'Disconnect' })).toBeNull();
      fireEvent.click(screen.getByRole('button', { name: 'Disconnect' }));
      fireEvent.click(within(screen.getByRole('alertdialog', { name: 'Disconnect' })).getByRole('button', { name: 'Disconnect' }));
      expect(nui.fetch).toHaveBeenCalledWith('multichar:disconnect');
    });

    it('closes at once when confirmDiscardOnClose is off', () => {
      render(<App />);
      message('multichar:show', { characters: [], maxCharacters: 1, ui: { confirmDiscardOnClose: false } });
      act(() => vi.advanceTimersByTime(121));
      message('multichar:previewReady', { scene: 'civilian', ok: true });
      fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
      fireEvent.change(screen.getByLabelText('First name'), { target: { value: 'Alex' } });
      fireEvent.click(screen.getByRole('button', { name: 'Close' }));
      expect(screen.queryByLabelText('First name')).toBeNull();
    });

    it('keeps the draft and stays usable while the model is toggled any number of times', () => {
      openCreate();
      fireEvent.change(screen.getByLabelText('Last name'), { target: { value: 'User' } });
      for (const name of ['Female', 'Male', 'Female', 'Male']) {
        fireEvent.click(screen.getByRole('button', { name }));
        expect(document.querySelector('.scene-transition')).toBeNull();
        expect((screen.getByLabelText('First name') as HTMLInputElement).value).toBe('Alex');
        expect((screen.getByLabelText('Last name') as HTMLInputElement).value).toBe('User');
      }
      message('multichar:previewReady', { scene: 'civilian', ok: true });
      expect(nui.fetch).toHaveBeenLastCalledWith('multichar:createPreview', { gender: 0 });
      fireEvent.click(screen.getByRole('button', { name: 'Close' }));
      expect(screen.getByRole('button', { name: 'Keep editing' })).toBeTruthy();
    });

    it('never lets a stuck loading cover sit on top of the dialog', () => {
      render(<App />);
      message('multichar:show', { characters: [], maxCharacters: 1 });
      act(() => vi.advanceTimersByTime(121));
      message('multichar:previewReady', { scene: 'civilian', ok: true });
      fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
      message('multichar:previewLoading', { citizenid: 'new' });
      expect(document.querySelector('.scene-transition')).toBeNull();
      fireEvent.click(screen.getByRole('button', { name: 'Female' }));
    });

    it('closes without a prompt when the form is untouched', () => {
      const confirm = vi.spyOn(window, 'confirm');
      render(<App />);
      message('multichar:show', { characters: [], maxCharacters: 1 });
      act(() => vi.advanceTimersByTime(121));
      message('multichar:previewReady', { scene: 'civilian', ok: true });
      fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
      fireEvent.click(screen.getByRole('button', { name: 'Close' }));
      expect(confirm).not.toHaveBeenCalled();
      expect(screen.queryByLabelText('First name')).toBeNull();
      confirm.mockRestore();
    });
  });
});

describe('branding, theme and nationality', () => {
  const openCreateWith = (ui?: Record<string, unknown>, characters: unknown[] = []) => {
    render(<App />);
    message('multichar:show', { characters, maxCharacters: 3, ui });
    act(() => vi.advanceTimersByTime(121));
    message('multichar:previewReady', { scene: 'civilian', ok: true });
  };

  it('shows the configured brand, defaulting to Kora, and never QBCORE', () => {
    openCreateWith();
    expect(document.querySelector('.brand-mark')!.textContent).toBe('Kora');
    cleanup();
    openCreateWith({ brandName: 'Aurora' });
    expect(document.querySelector('.brand-mark')!.textContent).toBe('Aurora');
    expect(document.body.textContent).not.toMatch(/qbcore/i);
  });

  it('hides the NEW badge on the free slot unless the flag is on', () => {
    openCreateWith();
    expect(document.querySelector('.new-slot-chip')).toBeNull();
    cleanup();
    openCreateWith({ showNewSlotBadge: true });
    expect(document.querySelector('.new-slot-chip')!.textContent).toBe('New');
  });

  it('renders no decorative accent rail in the create dialog', () => {
    openCreateWith();
    fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
    expect(document.querySelector('.create-modal .modal-rail')).toBeNull();
  });

  it('offers the configured nationalities in a select and submits the choice', () => {
    openCreateWith({ nationalities: ['Canadian', 'Mexican', 'American'], defaultNationality: 'Mexican' });
    fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
    const select = screen.getByLabelText('Nationality') as HTMLSelectElement;
    expect(select.tagName).toBe('SELECT');
    expect(Array.from(select.options).map((option) => option.value)).toEqual(['Canadian', 'Mexican', 'American']);
    expect(select.value).toBe('Mexican');
    fireEvent.change(screen.getByLabelText('First name'), { target: { value: 'Alex' } });
    fireEvent.change(screen.getByLabelText('Last name'), { target: { value: 'Rivera' } });
    fireEvent.change(select, { target: { value: 'Canadian' } });
    fireEvent.click(screen.getByRole('button', { name: /create identity/i }));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:create', expect.objectContaining({ nationality: 'Canadian' }));
  });

  it('falls back to the first entry when the default is not in the list', () => {
    openCreateWith({ nationalities: ['Canadian', 'Mexican'], defaultNationality: 'Atlantean' });
    fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
    expect((screen.getByLabelText('Nationality') as HTMLSelectElement).value).toBe('Canadian');
  });

  it('keeps a free-text field when the config allows it', () => {
    openCreateWith({ nationalities: ['Canadian'], allowFreeTextNationality: true, defaultNationality: 'Canadian' });
    fireEvent.click(screen.getByRole('button', { name: /^create$/i }));
    const field = screen.getByLabelText('Nationality') as HTMLInputElement;
    expect(field.tagName).toBe('INPUT');
    fireEvent.change(field, { target: { value: 'Quasar' } });
    expect(field.value).toBe('Quasar');
  });
});
