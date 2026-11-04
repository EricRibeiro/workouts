---
name: xcode-project
description: Change Workouts.xcodeproj safely — add or link a local/remote Swift package, read or set a build setting, add a target — using Xcode 27's `xcrun xcodeproj` CLI instead of editing project.xcproj by hand. Use whenever a task needs a project-file change.
---

# Changing the Xcode project

`Workouts.xcodeproj/project.xcproj` is Xcode 27's folder-based format. Source folders are synced,
so **adding a `.swift` file needs no project change**. Everything else goes through the CLI,
then the formatter, then a build to prove it.

```
xcrun xcodeproj <subcommand> ...        # auto-discovers Workouts.xcodeproj from the repo root
xcrun xcprojformatter --update Workouts.xcodeproj
./dev build
```

## Recipes (all verified on this repo)

Local package (this is how `Packages/WorkoutsKit` was added):
```
xcrun xcodeproj pkg add-local Packages/<Name>
xcrun xcodeproj pkg link <Product> --package <Name> --target Workouts
xcrun xcodeproj pkg list
```
Remote package (ask first; the contract says no new remote dependencies unprompted):
```
xcrun xcodeproj pkg add https://github.com/org/repo --from 1.2.0 --product <P> --target Workouts
```
Build settings:
```
xcrun xcodeproj setting get  IPHONEOS_DEPLOYMENT_TARGET --target Workouts
xcrun xcodeproj setting set  SOME_SETTING value --target Workouts     # omit --target for project level
xcrun xcodeproj setting list --target Workouts
```
Targets and phases:
```
xcrun xcodeproj target list
xcrun xcodeproj target info --target Workouts
xcrun xcodeproj target add --help
```
`xcrun xcodeproj help <subcommand>` documents the rest (`group`, `config`, `pkg link-plugin`).

## What the file looks like after a package add (so a diff review knows what is normal)

```
"packages": [ { "kind": "local", "path": "Packages/WorkoutsKit" } ],
...
"package-product-members": [
  { "package": "WorkoutsKit", "product-name": "WorkoutsKit", "build-phase": { "build-phase": "frameworks" } },
],
```

## Rules

- Never hand-edit `project.xcproj`. If the CLI cannot express a change, say so and stop.
- Always run `xcprojformatter --update` after the CLI, so diffs stay canonical.
- Don't touch `SUPPORTED_PLATFORMS` (iOS only), `TARGETED_DEVICE_FAMILY` (1), deployment target,
  or signing settings without being asked.
- Xcode's MCP `UpdateTargetBuildSetting` / `AddEntitlement` / `AddInfoPlist` do the same job
  from inside Xcode; either route is fine, but finish with the formatter and a build.

## Add an app extension target (verified: `WorkoutsLiveActivity`, a WidgetKit / Live Activity extension)

Order matters: **add the build phases before including the synced folder**, or `group include` records every existing
file as a membership exclusion (the target then builds with 0 sources and `./dev build` still "succeeds").

```
# 0. Write the sources first: WorkoutsLiveActivity/*.swift and WorkoutsLiveActivity/Info.plist (see "Info.plist" below)
xcrun xcodeproj target add WorkoutsLiveActivity --product-type app-extension      # blank: no phases, only PRODUCT_NAME
xcrun xcodeproj target phase add --target WorkoutsLiveActivity sources            # phases are NOT created for you
xcrun xcodeproj target phase add --target WorkoutsLiveActivity frameworks
xcrun xcodeproj target phase add --target WorkoutsLiveActivity resources
xcrun xcodeproj group add WorkoutsLiveActivity --filesystem-path WorkoutsLiveActivity   # synced folder
xcrun xcodeproj group include --group WorkoutsLiveActivity --target WorkoutsLiveActivity
xcrun xcodeproj pkg link WorkoutsKit --package WorkoutsKit --target WorkoutsLiveActivity
# files shared with the app: a second synced folder that BOTH targets include (see "Sharing files")
xcrun xcodeproj group add Shared --filesystem-path Shared
xcrun xcodeproj group include --group Shared --target Workouts
xcrun xcodeproj group include --group Shared --target WorkoutsLiveActivity
# embed in the app
xcrun xcodeproj target add-dependency Workouts WorkoutsLiveActivity
xcrun xcodeproj target phase add-copy --target Workouts --destination plugins --name "Embed Foundation Extensions"
xcrun xcodeproj target info --target Workouts            # the copy phase is the last index (4 here)
xcrun xcodeproj group include WorkoutsLiveActivity.appex --group Products --target Workouts --phase 4
# build settings (target add only sets PRODUCT_NAME; nothing else is inherited from the app)
T="--target WorkoutsLiveActivity"
xcrun xcodeproj setting set PRODUCT_BUNDLE_IDENTIFIER com.ericribeiro.Workouts.LiveActivity $T   # must be prefixed by the app's id
xcrun xcodeproj setting set GENERATE_INFOPLIST_FILE YES $T
xcrun xcodeproj setting set INFOPLIST_FILE WorkoutsLiveActivity/Info.plist $T
xcrun xcodeproj setting set INFOPLIST_KEY_CFBundleDisplayName "Workouts Live Activity" $T
xcrun xcodeproj setting set IPHONEOS_DEPLOYMENT_TARGET 27.2 $T            # same for SDKROOT=auto, SUPPORTED_PLATFORMS="iphoneos iphonesimulator", TARGETED_DEVICE_FAMILY=1
xcrun xcodeproj setting set SWIFT_VERSION 5.0 $T                          # and SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor, SWIFT_APPROACHABLE_CONCURRENCY=YES,
                                                                          # SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY=YES, SWIFT_EMIT_LOC_STRINGS=YES
xcrun xcodeproj setting set CODE_SIGN_STYLE Automatic $T                  # and CURRENT_PROJECT_VERSION=1, MARKETING_VERSION=1.0 (must equal the app's), SKIP_INSTALL=YES
xcrun xcodeproj setting set-multi LD_RUNPATH_SEARCH_PATHS "@executable_path/Frameworks" "@executable_path/../../Frameworks" $T
xcrun xcodeproj setting set INFOPLIST_KEY_NSSupportsLiveActivities YES --target Workouts   # the app's Info is generated, so this is the key
xcrun xcprojformatter --update Workouts.xcodeproj
./dev build
```

Gotchas:

- **`--destination plugins`, not `extensions`.** `extensions` is `$(EXTENSIONS_FOLDER_PATH)` (`Workouts.app/Extensions`, for
  ExtensionKit); WidgetKit and other Foundation extensions belong in `Workouts.app/PlugIns` (Xcode's "Embed Foundation
  Extensions"). The appex product reference already exists in the Products group after `target add`; `group include
  <name>.appex --group Products --phase <n>` is how it gets into the copy phase.
- **Info.plist.** `target add` defaults `GENERATE_INFOPLIST_FILE=YES` only for app/framework/bundle/test types, and there is no
  `INFOPLIST_KEY_` for `NSExtension`. So the extension uses both: `GENERATE_INFOPLIST_FILE=YES` (bundle id, version, platform
  keys) merged with `INFOPLIST_FILE` pointing at a minimal plist that holds only
  `NSExtension > NSExtensionPointIdentifier = com.apple.widgetkit-extension`. The plist may live inside the synced folder: the
  synced group excludes `Info.plist` automatically (it shows up in `membership-exceptions`, no CLI step).
- **Sharing files.** `group include <file> --group <synced-group>` only addresses files directly at the root of a synced folder
  (nested subfolders are not addressable, there is no per-file exception for them), so a file in `Workouts/App/...` cannot be
  added to a second target. Put shared files in a top-level synced folder (`Shared/`) that both targets include. Anything the
  extension must see (`ActivityAttributes`, later the `LiveActivityIntent`s) goes there; the kit still holds logic.
- A synced folder's `include` with 0 phases or before phases exist silently excludes files (see the order note above); after
  `target info` the extension's `sources` count should be the number of `.swift` files in its folder plus `Shared/`.
- `./dev lint`/`format` only cover `LINT_PATHS` in `dev`; a new source folder must be added there.
- Verify the product, not just the build: `plutil -p .build/DerivedData/Build/Products/Debug-iphonesimulator/Workouts.app/PlugIns/<T>.appex/Info.plist`
  (`NSExtensionPointIdentifier`) and `plutil -p .../Workouts.app/Info.plist | grep NSSupportsLiveActivities`.
- No signing change is needed for the simulator; do not touch `DEVELOPMENT_TEAM` until the TestFlight task.
