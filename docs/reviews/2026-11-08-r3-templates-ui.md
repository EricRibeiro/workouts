# R3 facet: Workout tab, templates, settings

Scope read end to end: `Workouts/Features/Workout/{WorkoutView,StartWorkoutFlow,FolderSection,TemplateCard,TemplateEditor,TemplatePreview}.swift`,
`Workouts/Features/Settings/{SettingsView,SettingsFlow,SettingsControl,DataTransfer}.swift`, `Workouts/App/RootView.swift`, plus
`AppNavigation`, `ResumeControl` (the cover-request recovery), `SaveErrors`/`EditorCoverHost`, `FolderOperations.create/rename/duplicate`,
`TemplateDraft.insertNew`, and the start-while-running UI tests in `WorkoutsUITests/TemplatePreviewUITests.swift`.

Paths I checked and found correct (none reported):
- Start while running: Empty Workout and the preview's Start both go through `StartWorkoutFlow`. Resume, Discard and Start New, and Cancel are
  right in the sheet case (the cover opens from `onDismiss`) and in the push case. A failed start never presents an empty cover. Both paths have UI tests.
- Edit from the sheet (the cover opens from `onDismiss`), from the push (the cover sits over the preview and Save/Cancel return to it) and
  from the card menu. Deferring a Live Activity open while the editor is up (`setEditorCoverOnScreen`).
- Folders: collapse is `@AppStorage` keyed by id and its key is removed when the folder is deleted. Move Up/Down are gated by `canMove`.
  The delete dialog covers both the move-to-Unfiled and the delete-templates cases. Rename and create trim blank names in the kit.
- New template goes into the first folder (settled by JC). There is no template drag-reorder (JC44). The folder header is a `Menu` with a
  primary action (JC33).
- Settings: the off-list rest value stays selectable. Video turn-off handles the case where the download was mid-file (cancel, then
  re-measure; Cancel resumes it). Apple Fitness off offers Keep, Remove or Cancel, and the toggle stays on until the person answers. Import holds the
  security-scoped access and runs to completion. The backfill is tied to the sheet's lifetime, and the foreground pass restarts it.
- RootView: the Live Activity or notification link closes the root sheets and leaves tab sheets alone (JC101). The resume ring
  recovers a cover request that is stuck while a sheet is up. Cover restore runs on relaunch.

## Findings

| ID | Sev | Where | Scenario | Fix direction |
|---|---|---|---|---|
| T3-1 | P3 | `Workouts/Features/Workout/WorkoutView.swift:137-139` (New Folder "Create"), `:147-152` (Rename), `TemplateEditor.swift:111` (Rename Template "Save") | Clear the field, or type only spaces, and tap Create or Rename. `FolderOperations.cleanedName` returns nil, so the alert closes and nothing happens, with no feedback. Under the HIG the default button should be unavailable until the input is valid. | `.disabled(FolderOperations.cleanedName(newFolderName) == nil)` on Create, Rename and Save. |
| T3-2 | P3 (runtime behaviour not verified) | `Workouts/App/RootView.swift:108` with `TemplatePreview.swift:116` → `StartWorkoutFlow.swift:81` | The only `saveErrorAlert` hosts are the root, the workout cover and the editor covers. If Start in the compact preview sheet fails to save (`engine.start` throws), the error goes to the root's alert, which sits under the sheet. It cannot present over the sheet, so the Start tap does nothing visible until the sheet is closed. The same applies to any `SaveErrors.report` raised from a tab sheet. A save failure is rare. | Host `.saveErrorAlert()` in `TemplatePreviewSheet` and have the root stand down while it is up (a counter like `editorCovers`), or report the start failure through the flow's own alert. |
| T3-3 | NIT | `Workouts/Features/Workout/TemplatePreview.swift:213` | `TemplatePreviewSheet` names no `presentationPlacement`. It is presented only at compact width, but if the Duo is unfolded while the sheet is up it stays a sheet at regular width with the default placement. DECISIONS says every sheet at regular width names one. | `.presentationPlacement(.center)` (ignored at compact width), or leave as is and note it as compact-only. |

Nothing at P0–P2.

VERDICT: NITS-ONLY
