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
