(function () {
  const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : "qbmultichar";

  const root = document.getElementById("root");
  const kickerEl = document.getElementById("kicker");
  const charStageEl = document.getElementById("char-stage");
  const slotsEl = document.getElementById("slots");
  const spawnStageEl = document.getElementById("spawn-stage");
  const spawnSlotsEl = document.getElementById("spawn-slots");
  const toastEl = document.getElementById("toast");
  const toastMessageEl = document.getElementById("toast-message");
  const overlayEl = document.getElementById("overlay");
  const createForm = document.getElementById("create-form");
  const firstnameInput = document.getElementById("firstname");
  const lastnameInput = document.getElementById("lastname");
  const deleteConfirmEl = document.getElementById("delete-confirm");
  const deleteConfirmName = document.getElementById("delete-confirm-name");
  const deleteConfirmButton = document.getElementById("delete-confirm-button");

  const ICON_PLAY =
    '<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>';
  const ICON_TRASH =
    '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M3 4.5h10M6.5 4.5V3a1 1 0 0 1 1-1h1a1 1 0 0 1 1 1v1.5M6 7v4.5M10 7v4.5M4 4.5l.6 8a1 1 0 0 0 1 .9h4.8a1 1 0 0 0 1-.9l.6-8"/></svg>';
  const ICON_PIN =
    '<svg width="22" height="22" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M8 1.5c-2.2 0-4 1.8-4 4 0 3 4 9 4 9s4-6 4-9c0-2.2-1.8-4-4-4z"/><circle cx="8" cy="5.5" r="1.5"/></svg>';

  let characters = [];
  let maxCharacters = 5;
  let focusedIndex = 0;
  let busy = false;
  let toastTimer = null;
  let pendingDeleteId = null;

  function fetchNui(callback, data) {
    return fetch(`https://${resourceName}/${callback}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data || {}),
    }).catch(() => null);
  }

  function applyTokens(tokens) {
    if (!tokens) return;
    const style = document.documentElement.style;
    for (const [key, value] of Object.entries(tokens)) {
      style.setProperty(`--${key}`, value);
    }
  }

  function characterName(character) {
    const info = character.charinfo || {};
    const name = `${info.firstname || ""} ${info.lastname || ""}`.trim();
    if (name) return name;
    if (character.name) return character.name;
    // A literal cid is only meaningful when it's actually present -- string-
    // interpolating an undefined one silently reads as "Character undefined"
    // (indistinguishable from a real bug) instead of an obvious placeholder.
    return typeof character.cid === "number" ? `Character ${character.cid}` : "Unnamed Character";
  }

  function initials(name) {
    return name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0].toUpperCase())
      .join("");
  }

  function formatAccount(character, account) {
    const value = character.money && typeof character.money[account] === "number" ? character.money[account] : 0;
    return `$${value.toLocaleString()}`;
  }

  function jobLabel(character) {
    return (character.job && character.job.label) || "Unemployed";
  }

  function setBusy(value) {
    busy = value;
    slotsEl.classList.toggle("busy", value);
    slotsEl.style.pointerEvents = value ? "none" : "";
    slotsEl.style.opacity = value ? "0.6" : "";
  }

  let spawnBusy = false;

  function setSpawnBusy(value) {
    spawnBusy = value;
    spawnSlotsEl.style.pointerEvents = value ? "none" : "";
    spawnSlotsEl.style.opacity = value ? "0.6" : "";
  }

  function chooseSpawn(typeLoc, spawnloc) {
    if (spawnBusy) return;
    setSpawnBusy(true);
    fetchNui("multichar:spawn:choose", { typeLoc, spawnloc });
  }

  function renderSpawnLocations(data) {
    const locations = (data && data.locations) || {};
    spawnSlotsEl.innerHTML = "";

    const current = document.createElement("div");
    current.className = "slot spawn";
    current.tabIndex = 0;
    current.innerHTML = `
      <div class="slot-avatar slot-avatar-spawn">${ICON_PIN}</div>
      <div class="slot-name">Stay Here</div>
      <div class="slot-meta"><span class="chip">Last location</span></div>
    `;
    current.addEventListener("click", () => chooseSpawn("current"));
    spawnSlotsEl.appendChild(current);

    Object.keys(locations).forEach((key) => {
      const location = locations[key];
      const slot = document.createElement("div");
      slot.className = "slot spawn";
      slot.tabIndex = 0;
      slot.innerHTML = `
        <div class="slot-avatar slot-avatar-spawn">${ICON_PIN}</div>
        <div class="slot-name">${location.label || key}</div>
      `;
      slot.addEventListener("click", () => chooseSpawn("normal", key));
      spawnSlotsEl.appendChild(slot);
    });
  }

  function showSpawnStage(data) {
    const visible = !!(data && data.visible);
    if (!visible) {
      close();
      return;
    }
    setSpawnBusy(false);
    charStageEl.hidden = true;
    spawnStageEl.hidden = false;
    if (kickerEl) kickerEl.textContent = "SELECT SPAWN LOCATION";
    root.hidden = false;
    requestAnimationFrame(() => root.classList.add("visible"));
  }

  function render() {
    slotsEl.innerHTML = "";

    characters.forEach((character, index) => {
      const name = characterName(character);
      const slot = document.createElement("div");
      slot.className = "slot filled";
      slot.tabIndex = 0;
      slot.innerHTML = `
        <button type="button" class="slot-delete" aria-label="Delete ${name}">${ICON_TRASH}</button>
        <div class="slot-avatar">${initials(name) || "?"}</div>
        <div class="slot-name">${name}</div>
        <div class="slot-meta">
          <span class="chip">${jobLabel(character)}</span>
          <span class="chip">Cash ${formatAccount(character, "cash")}</span>
          <span class="chip">Bank ${formatAccount(character, "bank")}</span>
        </div>
        <div class="slot-actions">
          <button type="button" class="btn btn-primary btn-sm slot-play">${ICON_PLAY}Play</button>
        </div>
      `;

      slot.addEventListener("click", (event) => {
        if (event.target.closest(".slot-delete")) {
          openDeleteConfirm(character.citizenid, name);
          return;
        }
        focusedIndex = index;
        updateFocusClasses();
        selectCharacter(character.citizenid);
      });

      slot.addEventListener("focus", () => {
        focusedIndex = index;
        updateFocusClasses();
      });

      slotsEl.appendChild(slot);
    });

    if (characters.length < maxCharacters) {
      const slot = document.createElement("div");
      slot.className = "slot empty";
      slot.tabIndex = 0;
      slot.innerHTML = `
        <div class="slot-plus">+</div>
        <div class="slot-empty-label">Create Character</div>
      `;
      slot.addEventListener("click", openCreateForm);
      slot.addEventListener("focus", () => {
        focusedIndex = characters.length;
        updateFocusClasses();
      });
      slotsEl.appendChild(slot);
    }

    focusedIndex = Math.min(focusedIndex, slotsEl.children.length - 1);
    updateFocusClasses();
  }

  function updateFocusClasses() {
    Array.from(slotsEl.children).forEach((el, index) => {
      el.classList.toggle("focused", index === focusedIndex);
    });
  }

  function moveFocus(delta) {
    const count = slotsEl.children.length;
    if (!count) return;
    focusedIndex = (focusedIndex + delta + count) % count;
    updateFocusClasses();
    slotsEl.children[focusedIndex].focus();
  }

  function activateFocused() {
    const el = slotsEl.children[focusedIndex];
    if (!el) return;
    el.click();
  }

  function deleteFocused() {
    const el = slotsEl.children[focusedIndex];
    if (!el || !el.classList.contains("filled")) return;
    el.querySelector(".slot-delete").click();
  }

  function selectCharacter(citizenid) {
    if (busy) return;
    setBusy(true);
    fetchNui("multichar:select", { citizenid });
  }

  function openCreateForm() {
    if (busy) return;
    firstnameInput.value = "";
    lastnameInput.value = "";
    overlayEl.hidden = false;
    createForm.hidden = false;
    deleteConfirmEl.hidden = true;
    firstnameInput.focus();
  }

  function openDeleteConfirm(citizenid, name) {
    if (busy) return;
    pendingDeleteId = citizenid;
    deleteConfirmName.textContent = name;
    overlayEl.hidden = false;
    deleteConfirmEl.hidden = false;
    createForm.hidden = true;
    deleteConfirmButton.focus();
  }

  function closeModal() {
    overlayEl.hidden = true;
    createForm.hidden = true;
    deleteConfirmEl.hidden = true;
    pendingDeleteId = null;
  }

  createForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const firstname = firstnameInput.value.trim();
    const lastname = lastnameInput.value.trim();
    if (!firstname || !lastname) return;

    closeModal();
    setBusy(true);
    fetchNui("multichar:create", { firstname, lastname });
  });

  deleteConfirmButton.addEventListener("click", () => {
    const citizenid = pendingDeleteId;
    closeModal();
    if (!citizenid) return;
    setBusy(true);
    fetchNui("multichar:delete", { citizenid });
  });

  document.querySelectorAll("[data-close-modal]").forEach((button) => {
    button.addEventListener("click", closeModal);
  });

  document.getElementById("toast-close").addEventListener("click", hideToast);

  function showToast(message) {
    toastMessageEl.textContent = message;
    toastEl.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 6000);
  }

  function hideToast() {
    toastEl.hidden = true;
    clearTimeout(toastTimer);
  }

  function show(data) {
    // A genuinely empty Lua table ({}) has no way to tell qbcore's JSON
    // encoder "I'm an array" -- SendNUIMessage serializes it as an empty
    // OBJECT ({}), not []. A brand-new player with zero characters hits this
    // every time, so characters.forEach below would throw
    // "characters.forEach is not a function" and silently abort show()
    // before the UI ever becomes visible. Normalize defensively instead of
    // relying on the Lua side to always emit an array shape.
    const rawCharacters = (data && data.characters) || [];
    characters = Array.isArray(rawCharacters) ? rawCharacters : Object.values(rawCharacters);
    maxCharacters = (data && data.maxCharacters) || maxCharacters;
    focusedIndex = 0;
    setBusy(false);
    closeModal();
    hideToast();
    spawnStageEl.hidden = true;
    charStageEl.hidden = false;
    if (kickerEl) kickerEl.textContent = "CHARACTER SELECT";
    render();

    root.hidden = false;
    requestAnimationFrame(() => root.classList.add("visible"));
    if (slotsEl.children.length) slotsEl.children[0].focus();
  }

  function close() {
    root.classList.remove("visible");
    setTimeout(() => {
      root.hidden = true;
      charStageEl.hidden = false;
      spawnStageEl.hidden = true;
    }, 180);
  }

  document.addEventListener("keydown", (event) => {
    if (root.hidden) return;

    if (!spawnStageEl.hidden) {
      if (event.key === "Escape") fetchNui("multichar:spawn:exit");
      return;
    }

    if (!overlayEl.hidden) {
      if (event.key === "Escape") closeModal();
      return;
    }

    if (event.key === "ArrowRight") moveFocus(1);
    else if (event.key === "ArrowLeft") moveFocus(-1);
    else if (event.key === "Enter") activateFocused();
    else if (event.key === "Delete") deleteFocused();
  });

  window.addEventListener("message", (event) => {
    const { action, data } = event.data || {};
    switch (action) {
      case "multichar:show":
        show(data);
        break;
      case "multichar:close":
        close();
        break;
      case "multichar:error":
        setBusy(false);
        showToast(data);
        break;
      case "multichar:theme":
        applyTokens(data);
        break;
      case "multichar:spawn:show":
        showSpawnStage(data);
        break;
      case "multichar:spawn:locations":
        setSpawnBusy(false);
        renderSpawnLocations(data);
        break;
    }
  });

  // Pull-on-mount: gets the current theme immediately rather than waiting on
  // a live push message, which may have already fired before this script ran.
  fetchNui("multichar:getTheme")
    .then((resp) => (resp ? resp.json() : null))
    .then(applyTokens)
    .catch(() => {});
})();
