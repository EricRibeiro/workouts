# RestTimerPickerSheet: UI coverage research

## 1 Current state

- **Sheet** (`Workouts/Features/Shared/SetTable/RestTimerPickerSheet.swift`): a `NavigationStack` > `List` over options `[nil, 0, 30, 60, 90, 120, 180, 300]`, plus the current value as an extra row when it is custom. A tap calls `onSelect(seconds)` then `dismiss()`.
  - Ids: sheet `restTimer.sheet` (`:63`), rows `restTimer.option.<seconds|default>` (`:50`), Cancel `restTimer.cancel` (`:56`).
  - Row titles: "Default (1:00)" (follows `SettingsStore.defaultRestSeconds`, 60 by default), "Off", then `ClockFormat.clock` ("0:30", "1:30" ...).
- **Presented** from `BlockActionSheets.swift:115-118` via `host.setRest`. The menu entry is `Button("Update Rest Timer…")`, id `settable.menu.rest` (`SetTable.swift:245-247`). It is shown only when `actions.updateRest != nil`.
- **Hosts and `setRest` per host:**

| Host | `setRest` | Visible effect |
|---|---|---|
| Logging cover (`ActiveWorkoutCover.swift:330`) | `engine.setRest(seconds, for: row)` sets `row.restSeconds` and commits (`ActiveWorkoutEngine+BlockEdits.swift:27`). | None immediate. `startRest(afterChecking:)` (`RestTimer.swift:264`) reads `row.restSeconds ?? settings.defaultRestSeconds` the next time a set is checked. 0 starts nothing; a running rest is left alone. |
| Template editor (`TemplateEditor.swift:203`) | `draft.updateRestTimers($1, for: $0)`. Persisted on Save. | Immediate: the block header shows a caption `Rest m:ss`, `Rest m:ss (default)` or `Rest off` (`SetTable.swift:208-212`, `SetTableLayout.restCaption`). It has no accessibility id, so match it by label. |
| Past editor (`PastWorkoutEditor.swift:276`) | No-op closure. | None. The entry is hidden: `updateRest` is nil via `noteActions` (`BlockActionSheets.swift:~81`). `PastEditorUITests.testBlockMenuOffersOnlyTheNotes` (`:111-117`) already asserts `settable.menu.rest` is absent. |

- **Hosts that can open it:** only the logging cover and the template editor. The past editor cannot, and a past-editor picker test would be a negative check that already exists.
- **Existing tests:**
  - No UI test touches `restTimer.*`. `LoggingBlockMenuUITests` and `TemplateEditorBlockMenuUITests` cover note, warm-up, remove, reorder, superset and preferences. The preferences test only asserts that `preferences.rest` is absent (`TemplateEditorBlockMenuUITests.swift:164`).
  - Kit tests cover the values, not the UI:
    - `TemplateDraftTests.newRowsKeepRestNilAndOffStaysZero` (`:168-176`) covers `updateRestTimers` with 0 and nil.
    - `ActiveWorkoutEngineTests` covers replace keeping rest (`:744-753`) and the copied rest (`:142`).
    - `RestTimerTests` covers the timer arithmetic.
    - I found no kit test of `engine.setRest` followed by a check. Check `ActiveWorkoutEngine*Tests` for `startRest`; if it is missing, add a kit test (about 15 minutes).
- **Launch fixtures** (`WorkoutsUITests/Support/XCUIApplication+Launch.swift`):
  - `launchedInActiveWorkout([extra])` passes `-startSampleWorkout … -openWorkoutCover` and waits for `screen.activeWorkout`. The launch also starts a 300 s rest on the ring (`rest.ring`).
  - `launchedForTesting(["-seedSampleData"])` is the template-editor path, with the `launchEditor()` card > preview > `template.edit` navigation copied per suite.
  - `XCUIElement+Waiting.swift` has `waitUntilGone`, `waitUntil { }` and `assertStaysAbsent`.
  - Ring helpers in `RestRingUITests` (`seconds(from:)`, `ringTime`) are `private`. The ring label reads "Rest timer, 4:57".
- **Accessibility:**
  - Each option is a `Button` with a text label ("Off", "1:30", "Default (1:00)"), and the checkmark is hidden. VoiceOver reads the title.
  - `.isSelected` is added to the current row.
  - Cancel has the label "Cancel".
  - The sheet has `.navigationTitle("Rest Timer")`.
  - Gap: the spoken labels "0:30" and "1:30" are not unit-friendly; "30 seconds" would be better. The "Default" row does not say it follows Settings.

## 2 Options

### A. Template editor test: immediate caption (recommended first)
- **Mechanism:** open the block menu, tap `settable.menu.rest`, assert the sheet and which row is selected, pick a row, assert the caption changed.
- **What it proves:** the sheet opens from the menu, the `current` binding and `.isSelected` are right, `onSelect` plus dismiss works, `draft.updateRestTimers` is wired, and Default/Off/value captions render.
- **Cannot prove:** the persisted value after Save, or the engine path.
- **Cost:** about 1 h. **Flakiness:** low. It is a plain sheet, and the caption is a static text.

```swift
@MainActor
func testUpdateRestTimerChangesTheCaptionAndDefaultRestores() throws {
    let app = launchEditor()
    let any = app.descendants(matching: .any)
    let (menu, _) = firstMenu(app)
    let caption = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Rest '")).firstMatch
    XCTAssertTrue(caption.waitForExistence(timeout: 5))
    let original = caption.label
    openMenuEntry(app, menu: menu, entry: "settable.menu.rest")   // copy the helper from the logging suite
    XCTAssertTrue(any["restTimer.sheet"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["restTimer.option.default"].isSelected || original != "Rest 1:30")
    app.buttons["restTimer.option.90"].tap()
    XCTAssertTrue(any["restTimer.sheet"].waitUntilGone(), "choosing a row did not close the sheet")
    XCTAssertTrue(caption.waitUntil { caption.label == "Rest 1:30" })
    // Off, then Default
    openMenuEntry(app, menu: menu, entry: "settable.menu.rest")
    app.buttons["restTimer.option.0"].tap()
    XCTAssertTrue(caption.waitUntil { caption.label == "Rest off" })
    openMenuEntry(app, menu: menu, entry: "settable.menu.rest")
    app.buttons["restTimer.option.default"].tap()
    XCTAssertTrue(caption.waitUntil { caption.label == "Rest 1:00 (default)" })
}

@MainActor
func testRestTimerCancelKeepsTheValue() throws { /* open, restTimer.cancel, sheet gone, caption == original */ }
```

- **Open point:** I did not confirm whether the seeded template rows carry a rest. `SampleData` has per-exercise `restSeconds` at lines 131-218 (150, 120, 90, 60, 180). Those may be catalog values copied into the template. If the first block is already 90, pick another value, or assert `caption.label != original`. Read `original` first to be safe.

### B. Logging cover test: next rest length
- **Mechanism:** skip the 300 s launch rest through the ring. Open the picker from the block menu and pick 30. Check the first unchecked set (`setrow.*.check`, as in `LoggingUITests`). Read the ring with the `ringTime` / `seconds(from:)` helpers.
- **What it proves:** the engine write path from the UI (`row.restSeconds`) feeds `startRest`. Assert the remaining time is ≤30 and > 15, versus the roughly 60 default.
- **Cannot prove:** persistence beyond the in-memory store. A "default" restore check costs one more round trip: set Default, uncheck and re-check a set, and expect the ring to read about 1:00.
- **Cost:** about 2 h. **Flakiness:** medium. The ring ticks, so use an upper bound plus a lower bound, as `RestRingUITests` does. Checking a set must come after the sheet is gone (`waitUntilGone`). The rest started by checking replaces any running rest.
- To lower the risk, skip the initial rest first and assert `rest.ring` goes idle (label without ", "), as `RestRingUITests` does.

```swift
let app = XCUIApplication.launchedInActiveWorkout()
// skip the launch rest: ring.tap(); rest.skip.tap()
openMenuEntry(app, menu: menu, entry: "settable.menu.rest")
app.buttons["restTimer.option.30"].tap()
XCTAssertTrue(any["restTimer.sheet"].waitUntilGone())
let check = firstUncheckedSet(app) // as in LoggingUITests
check.tap()
let t = seconds(from: ringTime(ring)); XCTAssertTrue((16...30).contains(t))
```

Do not duplicate the ring helpers: move `seconds(from:)` and `ringTime` into `Support/XCUIApplication+Controls.swift` or a new `Support/RestRing+Helpers.swift`.

### C. Snapshot test
- **Mechanism:** a `SnapshotRestTimerPickerTests` in `WorkoutsTests/Snapshot/`, using `SnapshotVariant.all` and `engine: .hostedFitting`, with `current` set to nil, 0, 90 and a custom 45. It needs `SettingsStore` in the environment.
- **What it proves:** the checkmark layout, the custom-row insertion and the Default title.
- **Cannot prove:** interaction or sheet detents.
- **Cost:** about 1 h plus recording references. **Value:** low-medium. The checkmark's position is a layout risk only if the font or width logic changes. `List` needs `.hostedFitting`.
- **Flakiness:** the NavigationStack chrome in a hosted window may differ per run. Snapshot the `List` only, not the sheet.

### D. Add VoiceOver labels
- **Mechanism:** give each row `.accessibilityLabel` ("30 seconds", "Off", "Default, 1 minute") via a duration formatter.
- **What it proves:** with an `XCTAssertEqual(row.label, …)` line in test A or B it pins the spoken strings.
- **Cost:** 0.5 h. **Risk:** the label change must keep `restTimer.option.*` ids as they are.

## 3 Recommendation (in order)

1. **Option A**, template editor, with the Cancel variant. It is the cheapest and most stable way to cover the whole file: sheet, current-row selection, every option branch and dismiss.
2. **Option B**, the logging cover, as a single test (30 s, then Default restores). This is the only test of the engine-fed behaviour. Move the ring helpers to the Support folder first.
3. **Past editor:** no new test. Keep the absence assertion in `PastEditorUITests`.
4. **Snapshot (C):** skip for now. Do D with it only if you want custom-row spoken labels.
5. If missing, add a kit test `setRest` → `check` → `restTimer.total == row.restSeconds` (0 leaves a running rest alone) so the UI test B asserts wiring, not logic.

No new identifiers are required for A or B (`restTimer.sheet`, `restTimer.option.*`, `restTimer.cancel`, `settable.menu.rest` all exist). Optional: `settable.restCaption.<sectionID>` on the template caption `Text` (`SetTable.swift:208`) to avoid matching on the label prefix.

## 4 Open questions for Eric

1. Does the seeded template's first block already have a rest of 90 (or another value you would pick)? I could not confirm it from `SampleData`; the test reads the caption first, so this only affects the chosen value.
2. Do you want the picker's spoken labels changed to "30 seconds" style (option D)? It changes VoiceOver output for the picker.
3. Should the caption get an identifier, or is label matching fine?
4. Is the 300 s launch rest the right starting state for test B, or do you prefer `-sampleRestSeconds` set high to avoid the skip step?
5. Is a Save-then-reopen persistence check for the template worth one extra test (kit tests cover only the draft)?

Sources: none external; everything above is from the repo (Apple's `Menu`, `.sheet` and accessibility behaviour was not in question).
