# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_multichar — game tests

  @kora_multichar @legacy:mc-select-opens @target:3 @checklist @checklist:kora_multichar:char-select-screen @cat:character-and-ui @manual
  Scenario: Select: opens on join
    """
    1. Connect with at least one character.
    Expect: after loading, a cinematic scene with two panels: "Who" (your characters as cards, plus Create character) on the left and "Where" (arrival points) on the right, a Profile and a Play button at the bottom, Disconnect top left and key hints. You are not logged in yet and cannot walk around.
    Also checklist kora_multichar:char-select-screen (Character select on join): Connect to server; character select opens with a cinematic scene, characters listed as cards in a carousel in a private bucket.
    """
    When I manually: connect to the server with an account that has at least one character and wait for loading to finish
    Then I confirm: a cinematic scene shows a "Who" panel on the left with my characters as cards plus a Create character card
    And I confirm: a "Where" panel with arrival points is on the right
    And I confirm: a Profile button and a Play button are at the bottom, Disconnect is top left and key hints are shown
    And I confirm: I am not logged in yet and cannot walk around

  @kora_multichar @legacy:mc-select-who @target:3 @manual
  Scenario: Select: the Who list
    """
    1. Click each character card, and use A/D, then select the Create character card.
    Expect: the selected card is highlighted and the ped, scene, name and job in the bottom bar follow. The header says "n characters". Clicking the already selected card does nothing. You cannot switch while a login or dialog is busy.
    """
    When I manually: click each character card in the Who list
    And I manually: use A and D to switch characters
    And I manually: select the Create character card
    Then I confirm: the selected card is highlighted and the ped, scene, name and job in the bottom bar follow it
    And I confirm: the header says "n characters" with the correct number
    When I manually: click the already selected card
    Then I confirm: nothing happens when clicking the already selected card
    When I manually: try to switch characters while a login or dialog is busy
    Then I confirm: I cannot switch while a login or dialog is busy

  @kora_multichar @legacy:mc-select-where @target:3 @manual
  Scenario: Select: pick an arrival point
    """
    1. In the Where list click different arrival points and use Up/Down.
    2. Change character and look again.
    Expect: the selected point is highlighted and shown in the bottom bar as "Job → Place". Choosing does nothing in the world: no flight, delay, cooldown or loading cover. The same point stays selected for the next character if it has it.
    """
    When I manually: click different arrival points in the Where list and use Up/Down
    Then I confirm: the selected point is highlighted and shown in the bottom bar as "Job → Place"
    And I confirm: choosing a point does nothing in the world: no flight, delay, cooldown or loading cover
    When I manually: change character and look at the Where list again
    Then I confirm: the same arrival point stays selected for the next character if it has that point

  @kora_multichar @legacy:mc-select-hud-hidden @target:3
  Scenario: Select: HUD and controls stay off until you arrive
    """
    1. Connect and look for the HUD during character select, then press Play and watch the fly-in.
    Expect: no HUD at all during select and the flight, and you cannot move. The HUD and controls come back only when the arrival has finished and you have faded in, never early.
    """
    When I manually: connect and look for the HUD during character select
    Then the HUD should be hidden
    And the minimap should be hidden
    When I manually: press Play and watch the fly-in
    Then I confirm: during the flight there is no HUD at all and I cannot move
    And I confirm: the HUD and controls come back only after the arrival has finished and I have faded in, never early

  @kora_multichar @legacy:mc-select-isolation @target:2 @manual
  Scenario: Select: you are alone in your scene
    """
    Two testers. 1. Both sit on character select at the same time, then both press Play so the fly-ins overlap.
    Expect: neither sees the other during select or the fly-in, and no ambient traffic or pedestrians wander through the scene backgrounds. After arriving you are back in the normal world and can see other players again.
    """
    When I manually: ask a second player to sit on character select at the same time as me
    And I manually: press Play at the same time as the second player so the fly-ins overlap
    Then I confirm: I do not see the other player during select or the fly-in
    And I confirm: no ambient traffic or pedestrians wander through the scene backgrounds
    And I confirm: after arriving I am back in the normal world and can see other players again

  @kora_multichar @legacy:mc-select-keys @target:3
  Scenario: Select: keyboard A/D, arrows, Enter
    """
    1. Use A and D (or Left/Right) to change character, Up/Down to change the arrival point, and Enter to Play.
    2. Open Create and type a name containing the letters a, d and w.
    Expect: A/D switch character, Up/Down move the arrival point, Enter plays. While typing in the Create form (or any text box) the keys only type; they do not browse or confirm anything.
    """
    When I press the "A" key
    And I press the "D" key
    And I manually: use Left/Right to change character, Up/Down to change the arrival point, and Enter to Play
    Then I confirm: A/D switch character, Up/Down move the arrival point and Enter plays
    When I manually: open Create and type a name containing the letters a, d and w
    Then I confirm: while typing in the Create form the keys only type and do not browse or confirm anything

  @kora_multichar @legacy:mc-select-preview-rapid @target:3 @manual
  Scenario: Select: rapid switching shows the right character
    """
    1. Click through the cards or tap A/D quickly through 4-5 characters, then stop.
    Expect: the ped, the scene and the Where list settle on the character you stopped on (previews and lists wait about 0.12 s and old answers are dropped). No flicker, no wrong ped or arrival list after it settles, "Loading scene..." clears.
    """
    When I manually: click through the cards or tap A/D quickly through 4-5 characters, then stop
    Then I confirm: the ped, the scene and the Where list settle on the character I stopped on
    And I confirm: there is no flicker and no wrong ped or arrival list after it settles
    And I confirm: "Loading scene..." clears

  @kora_multichar @legacy:mc-select-preview-clothes @target:3 @manual
  Scenario: Select: saved clothing and tattoos in preview
    """
    1. Browse characters that have custom clothing or tattoos.
    Expect: each previewed ped wears that character's saved outfit and tattoos with the right body model (male or female), not a default or naked ped and not the previous character's look.
    """
    When I manually: browse characters that have custom clothing or tattoos
    Then I confirm: each previewed ped wears that character's saved outfit and tattoos with the right body model (male or female)
    And I confirm: no ped is default or naked or shows the previous character's look

  @kora_multichar @legacy:mc-select-preview-fallback @target:1 @needs:admin @manual
  Scenario: Select: preview when clothing cannot load
    """
    Admin only. 1. Stop kora_clothing, then reconnect and browse characters.
    Expect: you still get a preview with a default ped of the right gender, the screen does not stay on the loading cover or flash, and there is no stuck state. Start kora_clothing again afterwards.
    """
    When I manually: stop kora_clothing, then reconnect and browse characters
    Then I confirm: I still get a preview with a default ped of the right gender
    And I confirm: the screen does not stay on the loading cover or flash and there is no stuck state
    When I manually: start kora_clothing again

  @kora_multichar @legacy:mc-scene-civilian @target:3 @manual
  Scenario: Scenes: civilian beach sunset
    """
    1. Preview a character with no job (unemployed).
    Expect: Vespucci Beach at sunset: two jet-skis with riders moving on the water, a person standing on the sand, a parasol and a towel. Your character stands in the foreground wearing their own clothes (no forced uniform).
    """
    When I manually: preview a character with no job (unemployed) on character select
    Then I confirm: the scene is Vespucci Beach at sunset with two jet-skis with riders moving on the water
    And I confirm: a person stands on the sand, with a parasol and a towel
    And I confirm: my character stands in the foreground wearing their own clothes (no forced uniform)

  @kora_multichar @legacy:mc-scene-police @target:3 @manual
  Scenario: Scenes: police robbery response
    """
    1. Preview a police character.
    Expect: the Strawberry 24/7 scene: police car with lights, a cop on the radio, a suspect with hands up, a getaway car and a bag. Saved clothing is kept.
    """
    When I manually: preview a police character on character select
    Then I confirm: the Strawberry 24/7 scene shows a police car with lights, a cop on the radio, a suspect with hands up, a getaway car and a bag
    And I confirm: the character's saved clothing is kept

  @kora_multichar @legacy:mc-scene-ems @target:3 @manual
  Scenario: Scenes: EMS medical response
    """
    1. Preview an ambulance (EMS) character.
    Expect: an outdoor Pillbox scene: ambulance with open doors and lights, a patient on the ground, two paramedics (one kneeling), a stretcher and a kit.
    """
    When I manually: preview an ambulance (EMS) character on character select
    Then I confirm: an outdoor Pillbox scene shows an ambulance with open doors and lights, a patient on the ground, two paramedics (one kneeling), a stretcher and a kit

  @kora_multichar @legacy:mc-scene-mechanic @target:3 @manual
  Scenario: Scenes: mechanic workshop
    """
    1. Preview a mechanic character.
    Expect: Benny's workshop: a car with an open door, a mechanic working on it, a tool box. Saved clothing is kept.
    """
    When I manually: preview a mechanic character on character select
    Then I confirm: Benny's workshop shows a car with an open door, a mechanic working on it and a tool box
    And I confirm: the character's saved clothing is kept

  @kora_multichar @legacy:mc-scene-gangs @target:3 @manual
  Scenario: Scenes: gang scenes and priority
    """
    1. Preview a Ballas member, a Vagos member, then a police or mechanic character who is also in a gang.
    Expect: Ballas shows Davis, Vagos shows Rancho (lowriders and members hanging out). Someone with both a career and a gang gets the career scene (careers beat gangs, gangs beat civilian).
    """
    When I manually: preview a Ballas member, then a Vagos member, then a police or mechanic character who is also in a gang
    Then I confirm: Ballas shows Davis and Vagos shows Rancho, with lowriders and members hanging out
    And I confirm: the character with both a career and a gang gets the career scene

  @kora_multichar @legacy:mc-scene-camera-focus @target:3 @manual
  Scenario: Scenes: camera stays on your character
    """
    1. Stay on one character for 30+ seconds, then switch characters.
    Expect: the camera settles on the ped and stays there (no cutting between close, focal and wide shots). It only moves, smoothly, when you change selection. Animations, vehicles and effects in the scene keep playing.
    """
    When I manually: stay on one character for 30 seconds or more
    Then I confirm: the camera settles on the ped and stays there with no cutting between close, focal and wide shots
    When I manually: switch characters
    Then I confirm: the camera only moves, smoothly, when I change selection
    And I confirm: animations, vehicles and effects in the scene keep playing

  @kora_multichar @legacy:mc-scene-environment @target:3 @manual
  Scenario: Scenes: time and weather, then the real world
    """
    1. Preview scenes with different lighting (sunset beach, night or day scenes).
    2. Press Play and watch the end of the fly-in.
    Expect: each scene has its own time and weather. The scene weather and clock are released before the descent, so you see the real world as you arrive, with no leftover colour filter, tint or blur.
    """
    When I manually: preview scenes with different lighting (sunset beach, night or day scenes)
    Then I confirm: each scene has its own time and weather
    When I manually: press Play and watch the end of the fly-in
    Then I confirm: the scene weather and clock are released before the descent and I see the real world as I arrive
    And I confirm: there is no leftover colour filter, tint or blur

  @kora_multichar @legacy:mc-scene-cleanup @target:3
  Scenario: Scenes: nothing left behind after arriving
    """
    1. Preview a few scenes, especially ones with sirens, particles or sounds, then press Play and arrive.
    Expect: no scene sounds or sirens still playing, no stray scene peds, vehicles or props following you, no leftover particle effects other than the arrival effect, and the camera is back to normal gameplay.
    """
    When I manually: preview a few scenes, especially ones with sirens, particles or sounds
    And I manually: press Play and arrive
    Then I confirm: no scene sounds or sirens are still playing
    And I confirm: no stray scene peds, vehicles or props follow me
    And I confirm: no particle effects are left other than the arrival effect
    And I confirm: the camera is back to normal gameplay
    And there should be no script errors

  @kora_multichar @legacy:mc-play-login @target:3 @checklist @checklist:kora_multichar:continue-login @cat:character-and-ui @manual
  Scenario: Play: the only login
    """
    1. Browse several characters and arrival points without pressing Play.
    2. Press Play on one.
    Expect: browsing and Profile never log anyone in. Play shows a spinner, logs that character in and starts the fly-in to the arrival point you picked. The character you chose is the one you play.
    Also checklist kora_multichar:continue-login (Continue to log in): Press Continue on a character; only then is it logged in and the spawn carousel opens.
    """
    When I manually: browse several characters and arrival points without pressing Play
    Then I confirm: browsing and Profile never log anyone in
    When I manually: press Play on one character
    Then I confirm: Play shows a spinner, logs that character in and starts the fly-in to the arrival point I picked
    And I confirm: the character I chose is the one I play

  @kora_multichar @legacy:mc-play-spam @target:3
  Scenario: Play: double click and Enter spam
    """
    1. Double-click Play, or hold or spam Enter.
    Expect: only one login and one fly-in happen: Play goes busy and ignores the extra presses. No double arrival, no error toast, no stuck spinner.
    """
    When I manually: on the character select screen, double-click Play, or hold or spam Enter
    Then I confirm: only one login and one fly-in happen and Play goes busy and ignores the extra presses
    And I confirm: there is no double arrival, no error toast and no stuck spinner
    And there should be no script errors

  @kora_multichar @legacy:mc-play-disabled @target:3 @manual
  Scenario: Play: waits for the arrival list
    """
    1. Switch character and press Enter or Play at once.
    Expect: Play stays disabled while the Where panel says "Finding arrival points…" and until a point is selected. A character with no points shows "No arrival points are available for this character." instead of a dead button.
    """
    When I manually: on the character select screen, switch character and press Enter or Play at once
    Then I confirm: Play stays disabled while the Where panel says "Finding arrival points…" and until a point is selected
    And I confirm: a character with no arrival points shows "No arrival points are available for this character." instead of a dead button

  @kora_multichar @legacy:mc-profile-details @target:3 @checklist @checklist:kora_multichar:character-dossier @cat:character-and-ui @manual
  Scenario: Profile: details panel
    """
    1. Press Profile on a character.
    Expect: Career (job and grade), Affiliation (gang and grade, or None / Independent), Finances (bank and cash), Birth date, Nationality (with "Place of origin") and Citizen ID. Close it with X; browsing to another character closes it.
    Also checklist kora_multichar:character-dossier (Character dossier details): Open dossier for a character: grade, gang/rank, cash, bank, birth date, nationality, citizen ID are shown.
    """
    When I manually: press Profile on a character
    Then I confirm: the panel shows Career (job and grade), Affiliation (gang and grade, or None / Independent) and Finances (bank and cash)
    And I confirm: the panel shows Birth date, Nationality (with "Place of origin") and Citizen ID
    When I manually: close the Profile panel with X
    Then I confirm: the Profile panel closes
    When I manually: open Profile again, then browse to another character
    Then I confirm: the Profile panel closes when I browse to another character

  @kora_multichar @legacy:mc-profile-values @target:3 @manual
  Scenario: Profile: values match the real character
    """
    1. Note the Profile values, then press Continue and spawn.
    2. Check job and grade, gang, cash and bank in game (menus, banking, /me style commands).
    Expect: they all match what the Profile showed. Names, dates and the citizen ID are not cut off or mangled.
    """
    When I manually: note the Profile values (job and grade, gang, cash, bank, name, birth date, citizen ID)
    And I manually: press Continue and spawn
    And I manually: check job and grade, gang, cash and bank in game (menus, banking, /me style commands)
    Then I confirm: job and grade, gang, cash and bank all match what the Profile showed
    And I confirm: names, dates and the citizen ID are not cut off or mangled

  @kora_multichar @legacy:mc-create-slot @target:3 @manual
  Scenario: Create: the Create character card
    """
    1. Find the "Create character" card at the end of the Who list (when below the character limit) and select it.
    Expect: the card says "Begin a new story", the Where panel says "New characters begin at the first arrival point", and the bottom button is Create. No NEW badge by default (it is a config option).
    """
    When I manually: find the "Create character" card at the end of the Who list (when below the character limit) and select it
    Then I confirm: the card says "Begin a new story"
    And I confirm: the Where panel says "New characters begin at the first arrival point"
    And I confirm: the bottom button is Create
    And I confirm: there is no NEW badge on the card (only shown when the config option is enabled)

  @kora_multichar @legacy:mc-create-form @target:3 @manual
  Scenario: Create: the form
    """
    1. Press Create.
    Expect: a dialog with First name, Last name, Birth date (date picker, no future dates), Nationality dropdown (American preselected) and a Male / Female switch, plus Cancel and Create identity. The first name field is focused.
    """
    When I manually: press Create
    Then I confirm: a dialog shows First name, Last name, Birth date (date picker, no future dates), Nationality dropdown (American preselected) and a Male / Female switch
    And I confirm: the dialog has Cancel and Create identity buttons
    And I confirm: the first name field is focused

  @kora_multichar @legacy:mc-create-gender-preview @target:3 @manual
  Scenario: Create: Male/Female changes the ped
    """
    1. In the Create dialog press Female, then Male.
    2. Select Female, type a name, close with X and Discard, reopen.
    Expect: the preview ped switches model each time. A kept female draft shows the female ped again when you reopen the dialog.
    """
    When I manually: in the Create dialog press Female, then Male
    Then I confirm: the preview ped switches model each time
    When I manually: select Female, type a name, close with X and press Discard, then reopen the dialog
    Then I confirm: the kept female draft shows the female ped again when I reopen the dialog

  @kora_multichar @legacy:mc-create-validation @target:3 @manual
  Scenario: Create: form validation
    """
    1. Try to create with: no first name; no last name; a 25+ character name; a future or blank birth date; no nationality.
    Expect: nothing is sent; a red message under each bad field ("Enter a first name.", "Names must be between 1 and 24 characters.", "Enter a real, non-future birth date." ...) and the first bad field gets focus. Errors clear when you edit the field.
    """
    When I manually: try to create with no first name, then with no last name, then with a 25+ character name, then with a future or blank birth date, then with no nationality
    Then I confirm: nothing is sent for any invalid attempt
    And I confirm: a red message shows under each bad field ("Enter a first name.", "Names must be between 1 and 24 characters.", "Enter a real, non-future birth date.")
    And I confirm: the first bad field gets focus
    When I manually: edit a field that shows an error
    Then I confirm: the error clears when I edit the field

  @kora_multichar @legacy:mc-create-nationality @target:3 @manual
  Scenario: Create: nationality list
    """
    1. Open the Nationality dropdown, scroll the whole list, pick a few.
    Expect: a long list of nationalities with American preselected. American sits near the end of the list instead of in A-Z order: say in Feedback if that looks wrong to you. Only listed values can be chosen. Your choice shows in Profile after creation.
    """
    When I manually: open the Nationality dropdown, scroll the whole list and pick a few
    Then I confirm: the dropdown shows a long list of nationalities with American preselected
    And I confirm: American sits near the end of the list instead of in A-Z order (say in Feedback if that looks wrong)
    And I confirm: only listed values can be chosen
    When I manually: finish creating the character and open Profile
    Then I confirm: my chosen nationality shows in Profile after creation

  @kora_multichar @legacy:mc-create-draft @target:3 @manual
  Scenario: Create: draft kept and discard prompt
    """
    1. Type a name, close with X, Cancel and Escape (each time) and answer both prompt buttons.
    2. Click the dark area outside the dialog.
    Expect: with text typed you get "Discard the identity details you entered?" with Keep editing / Discard; Escape inside the prompt keeps editing. An empty form closes at once. Clicking outside does not close it. Discard clears the draft.
    """
    When I manually: type a name in the Create dialog, close with X, and answer both prompt buttons
    And I manually: repeat with Cancel and then with Escape, answering both prompt buttons each time
    Then I confirm: with text typed I get "Discard the identity details you entered?" with Keep editing / Discard
    And I confirm: Escape inside the prompt keeps editing
    And I confirm: an empty form closes at once
    And I confirm: Discard clears the draft
    When I manually: click the dark area outside the dialog
    Then I confirm: clicking outside does not close the dialog

  @kora_multichar @legacy:mc-create-success @target:3 @checklist @checklist:kora_multichar:create-character @cat:character-and-ui
  Scenario: Create: new character flies in to the first arrival
    """
    1. Create a new character with valid details.
    Expect: no arrival choice: the camera flies to First Arrival (Legion Square) and you appear there like any other arrival. The clothing creator (kora_clothing) opens only after you have arrived and the HUD is back, not over the fly-in. Your name, birth date and nationality are what you typed.
    Also checklist kora_multichar:create-character (Create new character): Use free slot > Create Identity: first/last name, real past birth date, gender, nationality dropdown; character created and logged in.
    """
    When I manually: create a new character with valid details
    Then I confirm: there is no arrival choice and the camera flies to First Arrival (Legion Square)
    And I should be within 20 metres of "legion_square"
    And I confirm: the clothing creator (kora_clothing) opens only after I have arrived and the HUD is back, not over the fly-in
    And the HUD should be visible
    And I confirm: my name, birth date and nationality are what I typed

  @kora_multichar @legacy:mc-create-starter-outfit @target:3 @checklist @checklist:kora_multichar:new-char-starter-outfit @cat:character-and-ui @manual
  Scenario: Create: starter outfit, not the last look
    """
    1. Play a character with distinctive clothing, /logout (admin) or reconnect.
    2. Create a new character, once Male and once Female.
    Expect: the new ped wears the starter outfit when the creator opens, never the previous character's clothes, and the model matches the chosen gender.
    Also checklist kora_multichar:new-char-starter-outfit (New character starts with starter outfit): Create a new character after using one with custom clothes; new ped wears the starter outfit, not the old look.
    """
    When I manually: play a character with distinctive clothing, then use /logout (admin) or reconnect
    And I manually: create a new character as Male
    Then I confirm: the new ped wears the starter outfit when the creator opens, not the previous character's clothes, and the model is male
    When I manually: repeat creating a new character as Female
    Then I confirm: the new ped wears the starter outfit, not the previous character's clothes, and the model is female

  @kora_multichar @legacy:mc-create-max @target:3 @manual
  Scenario: Create: character limit
    """
    1. Fill every slot (default 5, or your license limit).
    Expect: no "Create character" card is offered once you are at the limit; the Who list shows characters only. If you can still trigger a create, it is refused with "You have reached the maximum number of characters."
    """
    When I manually: fill every character slot (default 5, or my license limit)
    Then I confirm: no "Create character" card is offered once at the limit and the Who list shows characters only
    And I confirm: if I can still trigger a create, it is refused with "You have reached the maximum number of characters."

  @kora_multichar @legacy:mc-create-names @target:3 @manual
  Scenario: Create: odd names are handled
    """
    1. Try names with spaces at both ends, accents (José), an apostrophe (O'Neil), a hyphen, digits, emoji and <b>html</b>.
    Expect: leading/trailing spaces are trimmed, nothing breaks the UI, and text is shown as plain text (never rendered as HTML) in select, Profile and in game. If a name is rejected or changed by the server, say which one and how.
    """
    When I manually: try creating characters with names with spaces at both ends, accents (José), an apostrophe (O'Neil), a hyphen, digits, emoji and <b>html</b>
    Then I confirm: leading and trailing spaces are trimmed and nothing breaks the UI
    And I confirm: text is shown as plain text, never rendered as HTML, in select, Profile and in game
    And I confirm: if a name is rejected or changed by the server, I note which one and how in Feedback

  @kora_multichar @legacy:mc-delete-flow @target:3 @checklist @checklist:kora_multichar:delete-character @cat:character-and-ui @manual
  Scenario: Delete: type the name to confirm
    """
    1. Profile > Delete character on a throwaway character.
    2. Type the name wrong, in the wrong case, then exactly. Try Cancel, X and the dark area.
    Expect: "Delete forever" stays disabled until the text matches the visible name exactly. Cancel, X and clicking outside close without deleting. Delete removes it, the list refreshes and the selection resets. Reconnect: it is still gone.
    Also checklist kora_multichar:delete-character (Delete character with name confirmation): Use Delete on a character; must type the exact visible character name to confirm; list refreshes after.
    """
    When I manually: open Profile > Delete character on a throwaway character
    And I manually: type the name wrong, then in the wrong case, then exactly
    Then I confirm: "Delete forever" stays disabled until the text matches the visible name exactly
    When I manually: try Cancel, X and clicking the dark area
    Then I confirm: Cancel, X and clicking outside close the dialog without deleting
    When I manually: type the name exactly and press Delete forever
    Then I confirm: the character is removed, the list refreshes and the selection resets
    When I manually: reconnect to the server
    Then I confirm: the deleted character is still gone

  @kora_multichar @legacy:mc-delete-last @target:3 @manual
  Scenario: Delete: deleting the last character
    """
    1. On an account with one throwaway character, delete it.
    Expect: you end up on the "Create character" slot with a working preview ped, no error, no stuck loading cover, and you can create a new character straight away.
    """
    When I manually: on an account with one throwaway character, delete it
    Then I confirm: I end up on the "Create character" slot with a working preview ped
    And I confirm: there is no error and no stuck loading cover
    When I manually: create a new character straight away
    Then I confirm: character creation works

  @kora_multichar @legacy:mc-disconnect @target:3 @checklist @checklist:kora_multichar:disconnect-button @cat:character-and-ui @manual
  Scenario: Disconnect button
    """
    1. Press Disconnect (top left). Try Cancel, X and Escape.
    2. Press Disconnect in the dialog.
    Expect: a "Disconnect?" dialog; Cancel, X and Escape close it. Confirming drops you from the server back to the FiveM menu with the message "Disconnected from character selection."
    Also checklist kora_multichar:disconnect-button (Disconnect from select screen): Use the disconnect action on the selection screen; player is dropped with 'Disconnected from character selection'.
    """
    When I manually: press Disconnect (top left)
    Then I confirm: a "Disconnect?" dialog appears
    When I manually: try Cancel, X and Escape
    Then I confirm: Cancel, X and Escape each close the dialog
    When I manually: press Disconnect again and confirm in the dialog
    Then I confirm: I am dropped from the server back to the FiveM menu with the message "Disconnected from character selection."

  @kora_multichar @legacy:mc-spawn-order @target:3 @checklist @checklist:kora_multichar:spawn-picker @cat:character-and-ui @manual
  Scenario: Arrival: the Where list and its order
    """
    1. Select each of your characters and read the Where list. Move with Up/Down and by clicking.
    Expect: Last Location first (already selected), then Legion Square, Pillbox Hill, Sandy Shores, Paleto Bay, then owned properties by name. Each has a short description and the panel shows "n arrival points". The list refreshes when you change character, and Up/Down wrap around.
    Also checklist kora_multichar:spawn-picker (Spawn location carousel): After Continue on an existing character, browse Last location, Legion Square, Pillbox Hill, Sandy Shores, Paleto Bay and owned properties.
    """
    When I manually: select each of my characters and read the Where list
    And I manually: move with Up/Down and by clicking
    Then I confirm: the order is Last Location first (already selected), then Legion Square, Pillbox Hill, Sandy Shores, Paleto Bay, then owned properties by name
    And I confirm: each point has a short description and the panel shows "n arrival points"
    And I confirm: the list refreshes when I change character
    And I confirm: Up/Down wrap around

  @kora_multichar @legacy:mc-spawn-last-location @target:3 @manual
  Scenario: Arrival: Last Location is exact
    """
    1. Play, walk or drive somewhere distinctive (mountain top, pier, far town), then disconnect.
    2. Reconnect, select that character, keep Last Location selected and press Play.
    Expect: the camera flies to that exact place and you arrive on the same spot facing the same way, not at a city fallback. (Its coordinates are only known after login, so check it every time.)
    """
    When I manually: play, walk or drive to a distinctive place (mountain top, pier, far town), then disconnect
    And I manually: reconnect, select that character, keep Last Location selected and press Play
    Then I confirm: the camera flies to that exact place
    And I confirm: I arrive on the same spot facing the same way, not at a city fallback

  @kora_multichar @legacy:mc-spawn-order-new @target:3 @manual
  Scenario: Arrival: new character list
    """
    1. Select the Create character card and look at the Where panel and the Play/Create button.
    Expect: no list: the panel says "New characters begin at the first arrival point." The button reads Create (not Play) and opens the form.
    """
    When I manually: select the Create character card and look at the Where panel and the Play/Create button
    Then I confirm: the Where panel shows no list and says "New characters begin at the first arrival point."
    And I confirm: the button reads Create (not Play) and opens the form

  @kora_multichar @legacy:mc-spawn-fixed @target:3 @manual
  Scenario: Arrival: each fixed location
    """
    1. For each of Legion Square, Pillbox Hill, Sandy Shores and Paleto Bay: select it and press Play.
    Expect: the fly-in ends over the place its description names and you arrive on solid ground (not under the map, in the air or inside a building), facing sensibly, and can move as soon as control returns.
    """
    When I manually: for each of Legion Square, Pillbox Hill, Sandy Shores and Paleto Bay, select it and press Play
    Then I confirm: the fly-in ends over the place its description names
    And I confirm: I arrive on solid ground, not under the map, in the air or inside a building
    And I confirm: I am facing sensibly and can move as soon as control returns

  @kora_multichar @legacy:mc-spawn-flight @target:3 @manual
  Scenario: Arrival: the camera flight
    """
    1. Press Play and watch from the first moment to the end.
    Expect: the camera lifts out of your character scene, cruises across the map, then descends into the arrival view. A caption reads "Flying to <place>", then "Arriving at <place>", with your name and a progress bar. The scene stays loaded while rising. No black flashes and no camera left behind.
    """
    When I manually: press Play and watch from the first moment to the end
    Then I confirm: the camera lifts out of my character scene, cruises across the map, then descends into the arrival view
    And I confirm: a caption reads "Flying to <place>", then "Arriving at <place>", with my name and a progress bar
    And I confirm: the scene stays loaded while rising
    And I confirm: there are no black flashes and no camera left behind

  @kora_multichar @legacy:mc-arrival-appear @target:3 @manual
  Scenario: Arrival: you appear with the effect
    """
    1. Watch the end of the flight, near your feet.
    Expect: the ped is placed while invisible and settles onto the ground (no hovering or falling), a particle effect plays at your feet, you fade in over about a second and the camera blends back to gameplay. HUD and controls come back only at the end. Your saved outfit is already on.
    """
    When I manually: watch the end of the flight, near my feet
    Then I confirm: the ped is placed while invisible and settles onto the ground, with no hovering or falling
    And I confirm: a particle effect plays at my feet
    And I confirm: I fade in over about a second and the camera blends back to gameplay
    And I confirm: HUD and controls come back only at the end
    And I confirm: my saved outfit is already on

  @kora_multichar @legacy:mc-arrival-skip @target:3 @manual
  Scenario: Arrival: Space skips the flight
    """
    1. Press Play and press Space during the flight, then try once without pressing it.
    Expect: the camera travel is shortened but the destination still streams and you still arrive and appear normally, never under the map or in a void. A "Space Skip" hint shows during the flight. Pressing Space repeatedly causes nothing odd.
    """
    When I manually: press Play and press Space during the flight, then try once without pressing it
    Then I confirm: the camera travel is shortened but the destination still streams and I arrive and appear normally, never under the map or in a void
    And I confirm: a "Space Skip" hint shows during the flight
    And I confirm: pressing Space repeatedly causes nothing odd

  @kora_multichar @legacy:mc-arrival-synced @target:2 @manual
  Scenario: Arrival: nearby players see the effect
    """
    Two testers. 1. One stands in the world near a spawn point (e.g. Legion Square).
    2. The other arrives there with Play. Repeat with the first one far away and with one still on character select.
    Expect: the nearby player sees the arrival effect once (within about 150 m). Players far away or still on character select do not see it, and a second arrival right after is not spammed.
    """
    When I manually: ask a second player to stand in the world near a spawn point such as Legion Square
    And I manually: arrive there with Play from character select, then repeat with the second player far away and with one still on character select
    Then I confirm: the other player near the spawn sees the arrival effect once (within about 150 m)
    And I confirm: the other players far away or still on character select do not see it
    And I confirm: a second arrival right after is not spammed for the other player

  @kora_multichar @legacy:mc-arrival-errors @target:3 @manual
  Scenario: Play: slow or refused login
    """
    Only if you can get a slow login (just after a restart, loaded server). 1. Press Play.
    Expect: if loading takes over 20 seconds you see "Loading your character took too long. Try again." and Play works again; a refusal from the server shows its message. You are never left on select with a dead Play button.
    """
    When I manually: press Play on a slow login (only if one can be reproduced, e.g. just after a restart)
    Then I confirm: if loading takes over 20 seconds I see "Loading your character took too long. Try again." and Play works again
    And I confirm: a refusal from the server shows its message
    And I confirm: I am never left on select with a dead Play button

  @kora_multichar @legacy:mc-arrival-fallback @target:1 @needs:admin @manual
  Scenario: Arrival: plain spawn if the flight cannot run
    """
    Admin or developer. 1. Press Play many times and watch the F8 console for "arrival flight did not complete".
    Expect: normally never. If it appears you should still end up at the chosen place after a fade out and in (not stuck on select), and the F8 line is worth reporting with what you did just before.
    """
    When I manually: press Play many times
    And the F8 console should show no errors
    Then I confirm: normally the F8 line "arrival flight did not complete" never appears
    And I confirm: if it appears I still end up at the chosen place after a fade out and in, not stuck on select

  @kora_multichar @legacy:mc-legacy-picker @target:1 @needs:admin @manual
  Scenario: Admin: classic Continue + spawn picker (config)
    """
    Admin only. 1. Set Config.arrival.enabled = false, restart kora_multichar and reconnect.
    2. Pick a character, press Continue, then browse the spawn carousel and press Spawn here.
    Expect: the original flow works: arrows and counter, Continue, then "Where do you wake up?" with flying previews. Set it back to true afterwards and check the Who/Where screen returns.
    """
    When I manually: set Config.arrival.enabled = false, restart kora_multichar and reconnect
    And I manually: pick a character, press Continue, then browse the spawn carousel and press Spawn here
    Then I confirm: the original flow works with arrows and counter, Continue, then "Where do you wake up?" with flying previews
    When I manually: set Config.arrival.enabled back to true
    Then I confirm: the Who/Where screen returns

  @kora_multichar @legacy:mc-spawn-slow-stream @target:3
  Scenario: Arrival: slow-loading destinations
    """
    1. On a cold client pick a far location (Paleto Bay or Sandy Shores) and press Play.
    Expect: the flight waits for the destination to stream, then descends, and props may pop in behind the shot. You always arrive at the place you picked, never at a different spot. Skipping with Space still waits for the stream.
    """
    When I manually: on a cold client pick a far location (Paleto Bay or Sandy Shores) and press Play
    Then I confirm: the flight waits for the destination to stream, then descends, and props may pop in behind the shot
    And I should be within 100 metres of "paleto_bay"
    When I manually: repeat and skip with Space
    Then I confirm: skipping with Space still waits for the stream

  @kora_multichar @legacy:mc-spawn-houses @target:1 @manual
  Scenario: Arrival: owned property (when available)
    """
    Only if a housing resource is running and you own a property. 1. Select that character and look at the Where list.
    Expect: the property is listed after the fixed locations, sorted by name, and Play flies to and arrives at its coordinates. With no property or no housing resource, skip this one.
    """
    When I manually: select a character that owns a property and look at the Where list (only if a housing resource is running; otherwise skip)
    Then I confirm: the property is listed after the fixed locations, sorted by name
    When I manually: press Play
    Then I confirm: I fly to and arrive at the property's coordinates

  @kora_multichar @legacy:mc-logout-command @target:1 @needs:admin
  Scenario: Admin: /logout returns to select
    """
    Admin only. 1. While playing run /logout.
    2. Pick a character and spawn again. Try it while driving.
    Expect: you fade out and land back on character select (the same as at join). If you were in a vehicle the next character does not spawn seated in it. Not logged in: "You are not on a character."
    """
    When I run the command "/logout"
    Then I confirm: I fade out and land back on character select, the same as at join
    When I manually: pick a character and spawn again
    And I manually: run /logout again while driving a vehicle
    Then I confirm: the next character does not spawn seated in the vehicle
    When I manually: run /logout while not logged in on a character
    Then I should see a notification containing "You are not on a character."

  @kora_multichar @legacy:mc-logout-denied @target:2 @needs:admin
  Scenario: Logout and studio: permissions and refusals
    """
    1. As a normal player and as a mod (not admin), try /logout and /multicharscene.
    2. As an admin, run /logout (F8 console) on character select, during the fly-in and inside the studio.
    Expect: no access for non-admins. Admins get "You are not on a character." on character select, and "Finish the current character-select session first." during the fly-in or in the studio. /multicharscene before loading a character says "Load a character before opening the scene studio."
    """
    When I manually: as a normal player and as a mod (not admin), try /logout and /multicharscene
    Then I confirm: non-admins have no access
    When I manually: as an admin, run /logout from the F8 console on character select
    Then I should see a notification containing "You are not on a character."
    When I manually: as an admin, run /logout from the F8 console during the fly-in and inside the studio
    Then I should see a notification containing "Finish the current character-select session first."
    When I manually: as an admin, run /multicharscene before loading a character
    Then I should see a notification containing "Load a character before opening the scene studio."

  @kora_multichar @legacy:mc-closenui @target:3
  Scenario: Command: /closeNUI
    """
    1. While playing, run /closeNUI.
    2. During select or spawn picker, run /closeNUI.
    Expect: while playing nothing breaks. During a select or spawn session it is refused with "Finish the current character-select session first." and your session carries on normally.
    """
    When I run the command "/closeNUI"
    Then there should be no script errors
    And I confirm: nothing breaks while playing
    When I manually: during select or the spawn picker, run /closeNUI
    Then I should see a notification containing "Finish the current character-select session first."
    And I confirm: my session carries on normally

  @kora_multichar @legacy:mc-restart-midsession @target:1 @needs:admin
  Scenario: Admin: restart kora_multichar while playing
    """
    Admin only. 1. While playing on a character run ensure kora_multichar on the server.
    2. Then /logout.
    Expect: you are not thrown back into character select or frozen, and you keep playing. After /logout you land on character select as normal.
    """
    When I manually: while playing on a character, run ensure kora_multichar on the server
    Then I confirm: I am not thrown back into character select or frozen, and I keep playing
    When I run the command "/logout"
    Then I confirm: I land on character select as normal

  @kora_multichar @legacy:mc-studio-open @target:1 @needs:admin
  Scenario: Studio: open and close
    """
    Admin only. 1. Run /multicharscene on a loaded character.
    2. Close it with the X.
    Expect: the Scene Studio opens with a scene dropdown, New, Duplicate and a "Fly camera" (Tab) button on top, one side panel (Add Ped / Vehicle / Prop, the entity list and Scene / Cameras / Timeline tabs) and an actions bar. Closing returns you to normal: camera, controls, HUD and position are back, nothing stuck.
    """
    When I run the command "/multicharscene"
    Then I confirm: the Scene Studio opens with a scene dropdown, New, Duplicate and a "Fly camera" (Tab) button on top
    And I confirm: one side panel shows Add Ped / Vehicle / Prop, the entity list and Scene / Cameras / Timeline tabs, plus an actions bar
    When I manually: close the studio with the X
    Then I confirm: camera, controls, HUD and position are back and nothing is stuck

  @kora_multichar @legacy:mc-studio-freecam @target:1 @needs:admin @checklist @checklist:kora_multichar:scene-studio-controls @cat:character-and-ui
  Scenario: Studio: Tab toggles cursor and freecam
    """
    Admin only. 1. In the studio press Tab (or the Fly camera button), then move with W A S D, Q and E, hold Shift, and look with the mouse.
    2. Press Tab again.
    Expect: Tab switches between the cursor (the button reads "Fly camera") and freecam ("Back to editing"), with on-screen key hints in freecam. Shift moves faster. Pressing Tab returns the cursor.
    Also checklist kora_multichar:scene-studio-controls (Scene studio cursor/freecam toggle): In the studio press TAB to toggle between UI cursor and freecam; move with configured speed keys.
    """
    When I press the "TAB" key
    And I manually: move with W A S D, Q and E, hold Shift, and look with the mouse
    Then I confirm: the button reads "Back to editing" and on-screen key hints show in freecam
    And I confirm: Shift moves faster
    When I press the "TAB" key
    Then I confirm: the cursor returns and the button reads "Fly camera"

  @kora_multichar @legacy:mc-studio-scenes @target:1 @needs:admin @manual
  Scenario: Studio: new, duplicate, load, anchor
    """
    Admin only. 1. Use New, Duplicate, and load one of the bundled scenes from the dropdown.
    2. In the Scene tab press "Set anchor at crosshair" and "Place character at crosshair".
    Expect: each action updates the scene and the view. The anchor and the character land where the crosshair points and the other entities keep their place relative to the anchor.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: use New, Duplicate, and load one of the bundled scenes from the dropdown
    Then I confirm: each action updates the scene and the view
    When I manually: in the Scene tab press "Set anchor at crosshair"
    And I manually: in the Scene tab press "Place character at crosshair"
    Then I confirm: the anchor and the character land where the crosshair points
    And I confirm: the other entities keep their place relative to the anchor

  @kora_multichar @legacy:mc-studio-metadata @target:1 @needs:admin @manual
  Scenario: Studio: scene metadata and environment
    """
    Admin only. 1. In the Scene tab change id, label, priority and selectors JSON and press Apply metadata.
    2. Change hour, minute, weather, timecycle and strength and press Apply environment.
    Expect: valid changes apply and show in the view. Bad selector JSON or a clashing id does not wipe the scene and says why. Environment changes show in the preview.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: in the Scene tab change id, label, priority and selectors JSON and press Apply metadata
    Then I confirm: valid changes apply and show in the view
    When I manually: enter bad selector JSON and a clashing id and press Apply metadata
    Then I confirm: the scene is not wiped and a message says why
    When I manually: change hour, minute, weather, timecycle and strength and press Apply environment
    Then I confirm: the environment changes show in the preview

  @kora_multichar @legacy:mc-studio-model-picker @target:1 @needs:admin @manual
  Scenario: Studio: model picker and search
    """
    Admin only. 1. Press Add Ped, Add Vehicle and Add Prop, search the list by name or model, press Enter to take the first match, and type a custom model name.
    2. Press Back or Escape. Try a made-up name and a name with odd characters.
    Expect: a searchable list per kind and "Use “name”" for any game model. Back and Escape return. A made-up name says it is not a model in the game; odd characters are refused.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: press Add Ped, Add Vehicle and Add Prop, search the list by name or model, press Enter to take the first match, and type a custom model name
    Then I confirm: there is a searchable list per kind and "Use “name”" is offered for any game model
    When I manually: press Back, then Escape
    Then I confirm: Back and Escape return to the previous view
    When I manually: try a made-up name and a name with odd characters
    Then I confirm: the made-up name says it is not a model in the game
    And I confirm: odd characters are refused

  @kora_multichar @legacy:mc-studio-add-auto @target:1 @needs:admin @manual
  Scenario: Studio: new entities land at the crosshair
    """
    Admin only. 1. Add several peds, vehicles and props, in freecam and from the cursor view.
    Expect: each appears at your crosshair (or in front of you without a camera), gets an id like ped_1, vehicle_1, prop_1 that never clashes, and is selected in the list so you can act on it straight away.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: add several peds, vehicles and props, in freecam and from the cursor view
    Then I confirm: each appears at my crosshair (or in front of me without a camera)
    And I confirm: each gets an id like ped_1, vehicle_1, prop_1 that never clashes
    And I confirm: each new entity is selected in the list so I can act on it straight away

  @kora_multichar @legacy:mc-studio-move @target:1 @needs:admin @manual
  Scenario: Studio: Move an entity
    """
    Admin only. 1. Select an entity in the list and press Move.
    2. Position and rotate it and confirm, then try again and cancel.
    Expect: the studio hides while you place the model; confirming saves the new position relative to the anchor, cancelling leaves it where it was. The studio, cursor and scene preview return afterwards.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: select an entity in the list and press Move
    And I manually: position and rotate it and confirm
    Then I confirm: the studio hides while I place the model and the new position is saved relative to the anchor
    When I manually: press Move again, place the entity and cancel
    Then I confirm: the entity stays where it was
    And I confirm: the studio, cursor and scene preview return afterwards

  @kora_multichar @legacy:mc-studio-entities @target:1 @needs:admin @manual
  Scenario: Studio: entity list, reorder, delete, Advanced
    """
    Admin only. 1. Select an entity, move it up and down the list, delete one.
    2. Edit one with Advanced (JSON), also with broken JSON.
    Expect: the list reorders and deletes cleanly and the preview follows. Broken JSON says "Enter a valid JSON object." and changes nothing; a clash in id is refused.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: select an entity, move it up and down the list, and delete one
    Then I confirm: the list reorders and deletes cleanly and the preview follows
    When I manually: edit an entity with Advanced (JSON) using broken JSON
    Then I confirm: it says "Enter a valid JSON object." and changes nothing
    When I manually: edit an entity with Advanced (JSON) to use an id that clashes with another entity
    Then I confirm: the clashing id is refused

  @kora_multichar @legacy:mc-studio-cameras @target:1 @needs:admin @manual
  Scenario: Studio: cameras tab
    """
    Admin only. 1. In the Cameras tab capture two cameras with different FOV, reorder them, edit one with JSON, delete one.
    2. Try to delete the last remaining camera.
    Expect: captured cameras use the freecam view and the FOV you set. The last camera cannot be deleted. Edits show in the preview.
    """
    When I manually: open the scene studio with the command /multicharscene and go to the Cameras tab
    And I manually: capture two cameras with different FOV, reorder them, edit one with JSON and delete one
    Then I confirm: captured cameras use the freecam view and the FOV I set
    And I confirm: edits show in the preview
    When I manually: try to delete the last remaining camera
    Then I confirm: the last camera cannot be deleted

  @kora_multichar @legacy:mc-studio-timeline @target:1 @needs:admin @manual
  Scenario: Studio: timeline tab and cues
    """
    Admin only. 1. In the Timeline tab change duration and loop, drag the scrubber, add a cue with the JSON box, edit, reorder and delete cues, press Play timeline.
    Expect: the scrubber previews the moment you drag to, Play runs the timeline with cues firing in order and looping if set. Bad cue JSON does not crash the studio.
    """
    When I manually: open the scene studio with the command /multicharscene and go to the Timeline tab
    And I manually: change duration and loop, drag the scrubber, add a cue with the JSON box, edit, reorder and delete cues
    Then I confirm: the scrubber previews the moment I drag to
    When I manually: press Play timeline
    Then I confirm: the timeline runs with cues firing in order and looping if set
    When I manually: enter bad cue JSON
    Then I confirm: the studio does not crash

  @kora_multichar @legacy:mc-studio-export @target:1 @needs:admin @manual
  Scenario: Studio: validate and copy to Lua
    """
    Admin only. 1. Press Validate on a good scene and on a broken one.
    2. Press Copy config and Copy registration, paste into a text editor.
    Expect: a clear valid/invalid message. The copied Lua is tidy, sorted, with three-decimal coordinates, and the registration version is a RegisterScene call. Nothing is saved to disk by the studio itself.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: press Validate on a good scene and on a broken one
    Then I confirm: a clear valid/invalid message is shown each time
    When I manually: press Copy config and Copy registration and paste each into a text editor
    Then I confirm: the copied Lua is tidy, sorted, with three-decimal coordinates
    And I confirm: the registration version is a RegisterScene call
    And I confirm: nothing is saved to disk by the studio itself

  @kora_multichar @legacy:mc-studio-limits @target:1 @needs:admin @manual
  Scenario: Studio: scene limits
    """
    Admin only. 1. Try to exceed limits: more than 8 peds, 6 vehicles, 24 props, 8 cameras, 64 cues, or a timeline over 120 seconds.
    Expect: a clear message each time (for example "This scene is at its limit of 8 ped entities.") rather than a silent failure or crash.
    """
    When I manually: open the scene studio with the command /multicharscene
    And I manually: try to exceed limits: more than 8 peds, 6 vehicles, 24 props, 8 cameras, 64 cues, or a timeline over 120 seconds
    Then I confirm: a clear message appears each time (for example "This scene is at its limit of 8 ped entities.")
    And I confirm: there is no silent failure or crash

  @kora_multichar @legacy:mc-runtime-scenes @target:1 @manual
  Scenario: Developer: RegisterScene from another resource
    """
    Developer. 1. From another resource call exports.kora_multichar:RegisterScene with a valid scene whose selector matches a test character, while that character is on select.
    2. Stop the resource.
    Expect: it returns true and the preview refreshes live to the new scene. Stopping the owning resource removes the scene and falls back. A different resource cannot replace or remove it.
    """
    When I manually: ask a developer to register a scene through the server console using a resource that calls RegisterScene, with a selector matching my test character, while that character is on the character select screen
    Then I confirm: the registration succeeds and my character preview refreshes live to the new scene
    When I manually: ask a developer to stop the resource that registered the scene
    Then I confirm: the scene is removed and the preview falls back to the default scene
    And I confirm: a different resource cannot replace or remove the scene

  @kora_multichar @legacy:mc-edge-quit-midway @target:3 @manual
  Scenario: Edge: quitting mid selection, flight or studio
    """
    1. Quit the game during character select, during the fly-in (after pressing Play) and while in the studio.
    2. Reconnect each time.
    Expect: you come back to normal character select, and your saved position is the real last place you played, never a camera or preview spot.
    """
    When I manually: quit the game during character select, reconnect and check
    And I manually: quit the game during the fly-in after pressing Play, and reconnect
    And I manually: quit the game while in the studio, and reconnect
    Then I confirm: each time I come back to normal character select
    And I confirm: my saved position is the real last place I played, never a camera or preview spot

  @kora_multichar @legacy:mc-edge-slow-join @target:3 @manual
  Scenario: Edge: slow or cold join
    """
    1. Join with a cold cache or while the server is just restarted.
    Expect: character select still appears (it retries) and characters and scenes load. If scenes cannot load you see the message "Scenes could not be loaded from the server. Previews will be unavailable." instead of a frozen cover.
    """
    When I manually: join with a cold cache or while the server has just restarted
    Then I confirm: character select still appears and characters and scenes load
    And I confirm: if scenes cannot load I see "Scenes could not be loaded from the server. Previews will be unavailable." instead of a frozen cover

  @kora_multichar @legacy:mc-edge-watchdog @target:3 @checklist @checklist:kora_multichar:scene-preview-watchdog @cat:character-and-ui @manual
  Scenario: Edge: preview watchdog
    """
    Only if you get a very slow preview. 1. Browse characters on a slow connection or loaded client.
    Expect: if a preview takes over 15 seconds the cover is removed and you see "The scene preview took too long to load." You can keep browsing and press Continue. Never a permanent cover.
    Also checklist kora_multichar:scene-preview-watchdog (Preview failure handling): If a preview does not load within 15s, the NUI shows an error instead of staying on the loading cover.
    """
    When I manually: browse characters on a slow connection or loaded client (only if a preview is very slow)
    Then I confirm: if a preview takes over 15 seconds the cover is removed and I see "The scene preview took too long to load."
    And I confirm: I can keep browsing and press Continue
    And I confirm: there is never a permanent cover

  @kora_multichar @legacy:mc-edge-resolution @target:3 @manual
  Scenario: Edge: UI at different resolutions
    """
    1. Check select (Who and Where panels), the create dialog, profile, delete dialog and the flight caption at 1080p, 1440p/4K and a small or ultrawide window.
    Expect: nothing overlaps or is cut off, long arrival descriptions wrap, text is readable, buttons are clickable and dialogs stay on screen.
    """
    When I manually: check select (Who and Where panels), the create dialog, profile, delete dialog and the flight caption at 1080p, 1440p/4K and a small or ultrawide window
    Then I confirm: nothing overlaps or is cut off
    And I confirm: long arrival descriptions wrap and text is readable
    And I confirm: buttons are clickable and dialogs stay on screen

  @kora_multichar @legacy:mc-edge-focus @target:3 @manual
  Scenario: Edge: mouse and keyboard focus
    """
    1. Type in the Create form with W A S D and other game keys.
    2. After spawning, try the mouse, keyboard and menus.
    Expect: nothing leaks into the game while typing (no movement, no game menus). After spawning the cursor is gone, controls are normal and no invisible UI blocks clicks.
    """
    When I manually: type in the Create form with W A S D and other game keys
    Then I confirm: nothing leaks into the game while typing (no movement, no game menus)
    When I manually: after spawning, try the mouse, keyboard and menus
    Then I confirm: the cursor is gone and controls are normal
    And I confirm: no invisible UI blocks clicks
