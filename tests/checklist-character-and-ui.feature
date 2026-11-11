# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_multichar — Character & UI

  @kora_multichar @checklist @checklist:kora_multichar:carousel-navigation @cat:character-and-ui @manual
  Scenario: Carousel navigation (arrows/A/D/mouse)
    """
    Checklist test: Switch characters with left/right, A/D, mouse buttons or controller; preview ped changes after short debounce.
    """
    When I manually: switch characters with left/right arrows, A/D, mouse buttons or a controller
    Then I confirm: the preview ped changes after a short debounce

  @kora_multichar @checklist @checklist:kora_multichar:character-preview @cat:character-and-ui @manual
  Scenario: Saved appearance preview
    """
    Checklist test: Select a character without logging in; ped shows saved clothing/tattoos in a scene matching their job/gang or civilian.
    """
    When I manually: open character select without logging in and highlight a character
    Then I confirm: the ped shows the saved clothing and tattoos
    And I confirm: the scene matches the character's job or gang, or the civilian scene otherwise

  @kora_multichar @checklist @checklist:kora_multichar:scene-by-job @cat:character-and-ui @manual
  Scenario: Career/gang scene selection
    """
    Checklist test: Preview a police/EMS/mechanic/gang character and see their matching scene (priority over civilian fallback).
    """
    When I manually: open character select and preview a police character
    Then I confirm: the police scene is shown instead of the civilian fallback
    When I manually: preview an EMS character, a mechanic character and a gang character in turn
    Then I confirm: each shows its matching scene instead of the civilian fallback

  @kora_multichar @checklist @checklist:kora_multichar:create-validation @cat:character-and-ui @manual
  Scenario: Create form validation
    """
    Checklist test: Try a future birth date, empty name or invalid nationality; error shown; creation blocked at max characters.
    """
    When I manually: in the create form, enter a future birth date and submit
    Then I confirm: an error is shown and creation is blocked
    When I manually: leave the name empty and submit
    Then I confirm: an error is shown and creation is blocked
    When I manually: enter an invalid nationality and submit
    Then I confirm: an error is shown and creation is blocked
    When I manually: try to create a character when at the maximum number of characters
    Then I confirm: creation is blocked

  @kora_multichar @checklist @checklist:kora_multichar:spawn-camera-flight @cat:character-and-ui @manual
  Scenario: Spawn preview camera flight
    """
    Checklist test: Switch spawn locations; camera lifts, cruises and dives to each with live preview; loading cover clears; rapid switching is throttled.
    """
    When I manually: open the spawn carousel and switch between spawn locations
    Then I confirm: the camera lifts, cruises and dives to each location with a live preview
    And I confirm: the loading cover clears
    When I manually: switch locations rapidly
    Then I confirm: rapid switching is throttled

  @kora_multichar @checklist @checklist:kora_multichar:spawn-confirm @cat:character-and-ui
  Scenario: Confirm spawn
    """
    Checklist test: Press Spawn on a location; fade in, ped placed at that location, HUD shows, routing bucket restored.
    """
    When I manually: pick a location in the spawn carousel and press Spawn
    Then I confirm: the screen fades in and my ped is placed at that location
    And the HUD should be visible
    And I confirm: my routing bucket is restored to the normal world

  @kora_multichar @checklist @checklist:kora_multichar:new-char-default-spawn @cat:character-and-ui @manual
  Scenario: New character skips spawn picker
    """
    Checklist test: Create a new character; it spawns directly at the default spawn (Legion Square) and clothing creator follows if installed.
    """
    When I manually: create a new character
    Then I confirm: it spawns directly at the default spawn (Legion Square) without the spawn picker
    And I confirm: the clothing creator opens afterwards if installed

  @kora_multichar @checklist @checklist:kora_multichar:scene-studio-command @cat:character-and-ui @needs:admin
  Scenario: Open scene studio with /multicharscene
    """
    Checklist test: As admin, logged in, run /multicharscene; studio opens. Non-admin is denied; unloaded character gets an error.
    """
    When I manually: log in on a character as admin
    And I run the command "/multicharscene"
    Then I confirm: the scene studio opens
    When I manually: as a non-admin, run /multicharscene
    Then I should see a notification containing "Could not open the scene studio."
    When I manually: run /multicharscene with no character loaded
    Then I should see a notification containing "Load a character before opening the scene studio."

  @kora_multichar @checklist @checklist:kora_multichar:scene-studio-edit @cat:character-and-ui @needs:admin @manual
  Scenario: Scene studio new/duplicate/load/save
    """
    Checklist test: In studio create a new scene, duplicate or load an existing one, edit entities/cameras, save; changes reflect in character select previews.
    """
    When I manually: open the scene studio and create a new scene
    And I manually: duplicate or load an existing scene
    And I manually: edit entities and cameras, then save
    And I manually: open character select and preview a character for that scene
    Then I confirm: the saved changes show in the character select previews
