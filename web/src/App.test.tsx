// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from './App';

const nui = vi.hoisted(() => ({
  fetch: vi.fn(() => Promise.resolve({})),
  theme: vi.fn(),
}));

vi.mock('./nui', () => ({ fetchNui: nui.fetch, applyTheme: nui.theme }));

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
  nui.theme.mockClear();
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

  it('relays controller navigation and acceptance to the active character', () => {
    const bob = { ...jane, citizenid: 'BOB2', cid: 2, charinfo: { ...jane.charinfo, firstname: 'Bob' } };
    render(<App />);
    message('multichar:show', { characters: [jane, bob], maxCharacters: 2 });
    message('multichar:input', { key: 'right' });
    expect(screen.getByText('Bob Doe')).toBeTruthy();
    message('multichar:previewReady', { scene: 'police', ok: true });
    message('multichar:input', { key: 'accept' });
    expect(nui.fetch).toHaveBeenCalledWith('multichar:select', { citizenid: 'BOB2' });
  });
});

describe('spawn and studio', () => {
  it('focuses the selected live spawn behind a blackout, refuses Escape, and confirms explicitly', async () => {
    render(<App />);
    message('multichar:spawn:locations', { locations: [{ id: 'legion', label: 'Legion Square', description: 'City centre' }] });
    message('multichar:spawn:show', { visible: true });
    expect(nui.fetch).toHaveBeenCalledWith('multichar:spawn:focus', { id: 'legion' });
    expect(screen.getByText('Scouting your arrival')).toBeTruthy();
    await act(async () => { await Promise.resolve(); });
    expect(screen.queryByText('Scouting your arrival')).toBeNull();

    fireEvent.keyDown(window, { key: 'Escape' });
    expect(nui.fetch).toHaveBeenCalledWith('multichar:spawn:exit');
    fireEvent.click(screen.getByRole('button', { name: /spawn here/i }));
    expect(nui.fetch).toHaveBeenCalledWith('multichar:spawn:choose', { id: 'legion' });
  });

  it('keeps destination flyovers visible and locks navigation until the camera lands', async () => {
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
    expect((screen.getByRole('button', { name: 'Next location' }) as HTMLButtonElement).disabled).toBe(true);

    await act(async () => { resolutions.shift()?.({ ok: true }); await Promise.resolve(); });
    expect(screen.queryByRole('status')).toBeNull();
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
});
