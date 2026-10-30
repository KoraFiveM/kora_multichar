// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
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
    expect(screen.getByText('Jane Doe')).toBeTruthy();
    expect(screen.getByText('Setting your scene')).toBeTruthy();
    expect(nui.fetch).not.toHaveBeenCalledWith('multichar:select', expect.anything());

    act(() => vi.advanceTimersByTime(121));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:preview', { citizenid: 'JANE1' });

    message('multichar:previewReady', { scene: 'police', ok: true });
    expect(screen.queryByText('Setting your scene')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: /continue/i }));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:select', { citizenid: 'JANE1' });
  });

  it('shows dossier fields and requires the exact typed name before deletion', () => {
    render(<App />);
    message('multichar:show', { characters: [jane], maxCharacters: 1 });
    expect(screen.getByText('SELECTED IDENTITY')).toBeTruthy();
    expect(document.querySelector('.profile-count')?.textContent).toBe('01/01');
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
    fireEvent.click(screen.getByRole('button', { name: 'Female model' }));
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
    expect(screen.getByText('Bob Doe')).toBeTruthy();
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
    message('multichar:spawn:show', { visible: true });

    await act(async () => { resolutions.shift()?.({ ok: true }); await Promise.resolve(); });
    fireEvent.click(screen.getByRole('button', { name: 'Next location' }));
    expect(screen.getByRole('heading', { name: 'Paleto Bay' })).toBeTruthy();
    expect(screen.getByRole('status').textContent).toContain('Flying to Paleto Bay');
    expect(screen.queryByText('Scouting your arrival')).toBeNull();
    expect((screen.getByRole('button', { name: 'Next location' }) as HTMLButtonElement).disabled).toBe(false);

    await act(async () => { resolutions.shift()?.({ ok: true }); await Promise.resolve(); });
    expect(screen.queryByRole('status')).toBeNull();
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

    it('asks before X or Escape discards typed data', () => {
      const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
      openCreate();
      fireEvent.click(screen.getByRole('button', { name: 'Close' }));
      fireEvent.keyDown(window, { key: 'Escape' });
      expect(confirm).toHaveBeenCalledTimes(2);
      expect(screen.getByLabelText('First name')).toBeTruthy();

      confirm.mockReturnValue(true);
      fireEvent.keyDown(window, { key: 'Escape' });
      expect(screen.queryByLabelText('First name')).toBeNull();
      confirm.mockRestore();
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
