# First-time hints ("tutorial") — behaviour and the yellow-outline bug

## Root cause of the persistent yellow outline (desk-checked, not reproduced in Studio)
The hint card was a `CanvasGroup` with a gold `UIStroke`. When no hint was active the code only faded
`GroupTransparency` to 1 and never set `Visible = false`. A `UIStroke` parented to the CanvasGroup itself is drawn outside the
group's canvas, so it ignores `GroupTransparency`: the text and fill faded, the rounded gold outline stayed. It was in the
bottom-centre because that is where the card lived. (Matches the report: empty yellow outline during normal play, also while
the journal was open.) No other bottom-centre gold-outlined element exists (the carry panel is gold but only visible while carrying).

## New design (`GuideController`, `GuideSpec`)
* ONE plain `Frame` owns background, outline, title, body and the Skip button. No active hint ⇒ `Visible = false` for the whole
  frame. There are no tweens or delayed callbacks, so a stale transition cannot bring an old step back.
* `Build`/`Init` are idempotent (second call returns), so there are never two cards or duplicate connections.
* Steps advance from actual state (`GuideSpec`): mine (4 blocks dug), backpack (timed 9 s / until first sale), sell, upgrade
  (second tool owned), elevator (timed), artifact (first deposit), collection (journal opened / timed). Finished steps are saved in
  the profile (`Guide`), so respawn / rejoin / death never replays them.
* Hidden whenever a menu is open (shop, settings, journal, Roblox menu) and shown again after, only if the step is still the active one.
* **Skip tutorial**: button on the card (use Alt for the cursor) or Settings → *Skip tutorial*. Server marks every step done plus
  `Guide.skipped = true`.
* **Restart tutorial**: Settings → *Restart tutorial*. Server clears `Guide` and stores a `GuideBase` baseline of lifetime counters so a
  veteran's old progress is not counted as new (everything is evaluated relative to the baseline, `GuideSpec.StateFrom`).
* Guidance is separate from the objective line and toasts; nothing else was changed or removed.

## Verified (offline, `tests/collection_test.luau` "tutorial lifecycle")
fresh profile → first hint is "mine"; partial profile resumes at the next step and never replays finished ones; completed profile shows
nothing; skip shows nothing even for a new state and re-reports nothing; restart for a veteran starts at "mine" and auto-completes
nothing; new activity after restart completes steps; counters never go negative.
## Not verified (needs Studio): that the outline is actually gone on screen, death/respawn/rejoin, menu transitions — see PLAYTEST_PLAN.
