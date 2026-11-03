# Workouts

Native iOS (SwiftUI) rewrite of the Workouts web app, built for the iPhone Duo.

Requires Xcode 27.2+ with the iOS 27.2 simulator runtime and an `iPhone Duo` simulator.

```
./dev help      # all commands
./dev kit       # fast package tests (macOS, seconds)
./dev check     # lint + package tests + build + simulator tests
./dev run       # launch on the iPhone Duo simulator
```

Logic lives in `Packages/WorkoutsKit`; the app in `Workouts/` is a thin SwiftUI shell.
Agent workflow and conventions are in [`AGENTS.md`](AGENTS.md).
