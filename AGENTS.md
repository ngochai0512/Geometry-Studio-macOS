# AGENTS.md — Working Agreement

This file instructs AI coding agents working in this repo. Humans: `README.md` is the product doc; this is the collaboration contract. Keep both current — when a rule below is violated and it hurts, fix the code; when a rule is wrong, fix this file.

## Orientation

Read this before exploring; it saves a full README pass.

- Native macOS SwiftUI app: a dynamic geometry sketchpad (points, lines, circles, polygons, constructions, measurements, transforms, a graph). Built for Apple silicon; macOS 13 floor.
- Build system: **Swift Package Manager only.** No `.xcodeproj`, no CocoaPods, no CI workflows. `Package.swift` is the single build description; the target declares `path: "Sources/GeometryStudio"`.
- Entry point: `main.swift` → `GeometryStudioApp.main()` in `App/GeometryStudioApp.swift`. That file must not gain `@main` while `main.swift` exists — two entry points do not compile.
- Layering, one concern per file:
  - `Geometry/` — value types and math, no document state: `Vec2.swift` (`Vec2`, `WorldRect`), `EvalPath.swift` (+ intersection helpers, `clipLine`), `Expression.swift`, `Style.swift` (`RGBA`, `ObjectStyle`, dash/shape), `Units.swift` (`LengthUnit`, `AngleUnit`, `SketchMetrics`).
  - `Model/` — `ObjectModel.swift` (`SketchObject`, `ObjectKind`), `Document.swift` (`CanvasSettings`, `SketchDocument`), `GeometryEval.swift` (parent→child resolution), `SketchTool.swift`, and `SketchModel` split across `SketchModel.swift` (state, lifecycle, undo, object helpers) plus `SketchModel+{Geometry,Editing,ToolActions,Animation,Construction,Measurement,Transforms,Document}.swift`.
  - `Views/` — `ContentView.swift` (chrome, toolbar, sheets), `InspectorView.swift`, `SketchCanvas.swift` (state and body), `CanvasDrawing.swift`, `CanvasGestures.swift`, `FlowChips.swift`, `AboutView.swift`.
  - `App/` — `GeometryStudioApp.swift` (scene), `SketchCommands.swift` (menus), `Notifications.swift`, `Screenshot.swift` (headless render path).
- `SketchModel` extensions cannot add stored properties: new `@Published` state belongs in `SketchModel.swift`; behavior goes in the extension file matching its area.
- Object graph: `SketchObject` is identified by `UUID`; parents are referenced by `UUID` inside `ObjectKind` (e.g. `.transformed(source:spec:)`, `.locus(driver:target:)`). `GeometryEval` resolves parents before children on every redraw. Pass IDs, never object references.
- Persisted shape: `SketchDocument { objects, settings, title }`, encoded as pretty-printed sorted-key JSON with a `.gsp` extension. The format is **unversioned** — additive changes only (see section 3).
- Observed defaults, taken from the original's preference initialiser and recorded in `MECHANICS.md`: inches, hundredths, degrees. Do not "correct" these to metric or to whole numbers.
- Third-party dependencies: none. Standard library and system frameworks only.

### Quick Pre-flight

Before saying "done": build, exercise the screenshot path, confirm zero new warnings, and update `README.md` if user-visible behavior changed. Full checklist in section 9.

### Reference Docs

Primary sources for anything unfamiliar. Where a rule below is stricter than a doc, the rule below wins.

| Area | Reference |
| --- | --- |
| Swift language | https://developer.apple.com/documentation/swift |
| API naming & design | https://www.swift.org/documentation/api-design-guidelines/ |
| SwiftUI | https://developer.apple.com/documentation/swiftui |
| AppKit (`NSSavePanel`, `NSOpenPanel`, `NSImage`) | https://developer.apple.com/documentation/appkit |
| Swift Package Manager | https://www.swift.org/documentation/package-manager/ |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines/ |
| Core Graphics geometry | https://developer.apple.com/documentation/coregraphics |
| Swift Testing (when a test target exists) | https://developer.apple.com/documentation/testing |

Verify API availability against the macOS 13.0 floor (section 5) before using a symbol; ask first if it is newer.

## 0. Clean-Room and Provenance

This project is an independent reimplementation, not a port. `MECHANICS.md` is the spec: it records what was observed in the original 2013 32-bit the legacy framework binary — addresses, struct layout, factory defaults.

- Never commit the original `the reference app bundle` bundle, its `Localizable.strings` extracts, its help book, or any other extracted resource. `MECHANICS.md` may cite an address or quote one diagnostic string; bulk resource dumps do not belong in this repo.
- The `.gsp` files this app writes are its own JSON format. Never claim the original binary format is read or written, and do not add a decoder that pretends to.
- Do not use "the reference application" or "the reference app" as a product name, bundle identity, repo name, or marketing claim.

## 1. Verify, Don't Assume

- Read the code before changing it. Never edit from memory of an earlier turn.
- Use SwiftPM directly (no wrapper scripts, no `xcodebuild`):

  ```sh
  # Debug build while iterating
  swift build

  # Release build
  swift build -c release

  # Run the windowed app
  swift run GeometryStudio

  # Headless render used for visual checks: 120 frames, writes a PNG, exits
  ./.build/release/GeometryStudio --screenshot /tmp/geometry-studio.png
  ```

- Tests cover the pure-value core: `swift test` runs the `GeometryStudioTests` suite. They use no windows, timers, files or network — keep them that way.
- If SwiftPM's own manifest sandbox cannot start because it is already nested inside a sandbox (`sandbox-exec: sandbox_apply: Operation not permitted`), pass `--disable-sandbox` to the SwiftPM command. That disables SwiftPM's redundant nested sandbox only; never weaken the app's App Sandbox or entitlements.
- Automated visual checks use `--screenshot`. It must keep working without activating the app or stealing focus; a normal `swift run` does activate it, so don't leave one running in a background job.
- After any change: rebuild and confirm zero new warnings. The warning bar is zero — today's warning is tomorrow's build error.
- When behavior is in question, `MECHANICS.md` wins over "how other geometry apps do it". Do not quietly substitute a standard convention for a documented observation.
- If a check fails, investigate the failure itself — don't "fix" it by weakening the check, unless it is provably wrong (then say so explicitly).

## 2. Small, Reversible Steps

- **Do not commit or push until the user says so.** Implement, verify, and stop with the working tree dirty. Committing, amending, rebasing, tagging, stashing and pushing all require an explicit instruction in the turn that asks for them; a request to build, fix or refactor something is not permission to commit. When the work is ready, report it and say what the commit would contain — then wait.
- One idea per change. Refactors stay behavior-identical; features stay minimal; never mix the two in one diff.
- Pure moves before behavior edits: relocate code first (build green), then change it (build green again).
- Never commit secrets, credentials, or local-only config. Respect `.gitignore` (`.build/`, `.swiftpm/`, `DerivedData/`, `opencode.json` are already ignored).
- Never run destructive or irreversible git commands (e.g. `git reset --hard`, `git clean -fd`, `git checkout -- .`, `git push --force`, `git branch -D`, `git stash drop`, `git rebase` on pushed commits or on main). If one seems necessary, stop and ask first, and describe what would be lost.
- Never skip hooks or amend someone else's commit.
- Never run `sudo`, `rm -rf`, or `defaults write` / `defaults delete`. Don't touch system settings or files outside the repo.
- Only touch files/folders explicitly named in the task or a path the user gives you. If a task seems to require anything outside that scope, stop and ask rather than assuming it is in bounds.
- Off-limits without an explicit ask: `Package.swift` (target layout and manifest), `MECHANICS.md` (the observed spec), `.gitignore`. Structural changes here invalidate the build or the record of what was verified.

### File Deletion Policy

- Always ask for permission (via the dialog in OpenCode) before deleting a file that has become unnecessary after a refactor.
- If the user says no, do not delete it.
- If the user says yes, don't hard-delete — move it to the parent folder of the project it came from.
  - *Illustrative example:* a superseded `GeometryModel.swift` goes to `~/Desktop`, not the bin. Apply the same pattern (project folder → its parent) to whatever project you are in.

## 3. Architecture Hygiene

- Geometry math lives in `Geometry/`. Views never do geometry: `CanvasDrawing` draws what `GeometryEval` returns and `SketchModel+Geometry` owns screen↔world conversion; `ContentView` presents.
- Adding an object kind touches four places, and all four are part of the change: an `ObjectKind` case (`Model/ObjectModel.swift`), a `GeometryEval` branch (position/path/measurement), drawing plus hit-testing (`Views/CanvasDrawing.swift`, `Model/SketchModel+Geometry.swift`), and the inspector/measure UI (`Views/InspectorView.swift`, `Views/ContentView.swift`). Adding the enum case alone ships a half-object that Codable accepts and the canvas cannot draw.
- Units, precision and scale have single sources: `SketchMetrics`, `LengthUnit`, `AngleUnit`, `CanvasSettings`. Never re-derive `72`, `2.54`, or `0.01` at a call site.
- Undo: mutate through `SketchModel`; call `checkpoint()` before a change that should be undoable. Snapshots capture `objects` and `selection` only — settings and `title` are outside history, so don't promise undo for them. Views must not append to model arrays directly.
- Persistence: property names in `SketchDocument`, `SketchObject`, `CanvasSettings`, `ObjectStyle` are the on-disk keys. Renaming one silently discards user data. Add a new property **with a default** instead; the decoder runs without a version field to migrate against.
- Coordinate space: model coordinates are world points where 100% zoom is 72 points per inch. Screen↔world conversion lives in `SketchModel+Geometry`; don't bake zoom or pan into stored geometry.
- `Geometry/Style.swift` imports SwiftUI and AppKit only for the `color`/`nsColor` bridges on `RGBA`; `Geometry/Vec2.swift` imports CoreGraphics for `cg`. Keep new math types in `Geometry/` free of view types so the core stays testable without a window.
- `--screenshot` is a contract used by automated checks. Keep the flag, the frame count, and the no-activation behavior working.
- No dead code, no commented-out code, no "temporary" hacks without a one-line note saying when they go away. Delete rather than comment out.

## 4. Dependencies

- The project has no third-party dependencies, and that is a feature: it builds with Xcode command-line tools alone. A new SPM dependency requires explicit approval before adding — propose it with a one-line reason, don't add one silently while solving an unrelated problem.
- Prefer the standard library or system frameworks. Pin any approved dependency to an exact version range; never "latest" or unbounded.
- Removing a dependency is its own reviewable step — don't bundle it with a feature or refactor commit.

## 5. Toolchain

- `swift-tools-version: 5.9`; Swift 5 language mode; minimum deployment target macOS 13.0; builds `arm64` on Apple silicon.
- Xcode 15 or later to open the package (`open Package.swift`, or `xed .`). Xcode is optional: `swift build` is the source of truth, and the build must succeed without an `.xcodeproj`.
- If local Xcode and the command line differ, say which one you built with rather than silently reporting a result from the other.
- There is no app bundle, `Info.plist`, entitlement, or code signing in this build. Consequence to remember: without an exported `gsp` type declaration, `UTType(filenameExtension: "gsp")` returns `nil` and the open/save panels fall back to `.json`. Don't add a workaround that only works when bundled.

## 6. Conventions

- **Indentation:** 4 spaces, one level per nesting. No tabs, no trailing whitespace. (This codebase uses spaces; do not convert it to tabs.)
- **No one-line code** where it hurts readability. Chains of modifiers, multiple statements, and closures with a real body go multi-line, one modifier per line.
- **Exceptions — one-line is allowed only for these:**
  - A short computed property, e.g. `var id: String { rawValue }`.
  - A single trailing closure with a short body, e.g. `.filter { !$0.isLocked }`.
  - Subscript or optional-chaining access, e.g. `item?.position ?? .zero`.
- **Style for SwiftUI properties:**

  Good:
  ```swift
  Image(nsImage: icon)
      .resizable()
      .frame(width: 96, height: 96)
      .clipShape(RoundedRectangle(cornerRadius: 20))
  ```

  Bad:
  ```swift
  Image(nsImage: icon).resizable().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 20))
  ```

- **Files and types:** `UpperCamelCase` types, one primary type per file where the file is named after it. A new subsystem gets its own file; `SketchModel` behavior belongs in the extension file matching its area.
- **Comments:** one line, one idea. Explain *why*, never restate *what*. When a value comes from the original, cite it the way `CanvasSettings` does (`routine`, `an offset`) instead of re-explaining the derivation. No process markers (`NEW`, ownerless `TODO`, conditional-free `FIXME`).
- **Magic numbers:** name them in `SketchMetrics` or the relevant enum. A literal is acceptable only where the surrounding expression is the definition.
- **Accessibility:** icon-only controls get labels; selection state is exposed; nothing clips at larger text sizes — prefer minimum sizes over fixed frames.
- **UI text:** user-facing copy is product copy — don't "improve" wording unprompted; flag inaccuracies instead.
- **API currency:** do not use deprecated or soon-to-be-deprecated APIs. Prefer current alternatives; check the symbol against macOS 13 availability.

## 7. Error Handling

- Document I/O reports through `statusMessage` and names the operation ("Could not save: …", "That file could not be opened: …"). Never crash and never fail silently.
- `try?` and empty `catch` blocks require a one-line comment explaining why ignoring the error is safe.
- Decoding must tolerate a missing new field. Never add a non-optional `Codable` property without a default value; that turns every previously saved sketch into an error.
- No force-unwraps or `try!` in model or math code. `!` is acceptable only where the invariant is local and obvious within a few lines.
- Don't dump raw `localizedDescription` into a panel without review; it is technical text, not product copy.

## 8. Testing

- The test target is `GeometryStudioTests`, built from `Tests/GeometryStudioTests/` and linked with `@testable import GeometryStudio`. Do not add a second test target without a reason.
- Keep the suites pure-value: `EvalPath` intersections (line/line, line/circle, circle/circle), `Expression` parsing and evaluation, unit conversion, `GeometryEval` parent ordering, document round-trip. Construct `SketchObject` values directly.
- A new pure type arrives with a test in the matching suite. UI behavior is verified with `--screenshot`, never by adding test infrastructure that needs a window.
- Determinism: no windows, no timers, no wall-clock, no filesystem.
- Compare doubles with a tolerance of `1e-7`, matching the dedupe threshold already used in `EvalPath`.
- Rendering is verified with `--screenshot` and an eyeball check, never with pixel assertions or performance timing.

## 9. Definition of Done

Before reporting a change as finished, confirm all of the following:

- [ ] `swift build` succeeds with zero new warnings.
- [ ] `swift test` passes (28 tests, 6 suites) — or the report says which suite could not run and why.
- [ ] The screenshot path still runs: `--screenshot /tmp/geometry-studio.png` writes a non-empty PNG.
- [ ] No dead code, commented-out code, or unexplained temporary hacks left behind.
- [ ] Persisted `Codable` shape changed additively only, or not at all.
- [ ] New object kinds are wired through all four places in section 3.
- [ ] No new dependency added without approval (section 4).
- [ ] No deprecated API introduced (section 6).
- [ ] `README.md` updated if user-visible behavior or build steps changed.
- [ ] Nothing committed, amended, tagged or pushed unless the user asked for it in this turn (section 2).
- [ ] Commit message follows the Conventional style in section 11 — drafted in the report, not applied until asked.

If any box can't be checked, say so explicitly in the report rather than omitting or hiding it.

## 10. Communication

- Plan mode means read-only: observe, analyze, propose. Never edit, run write-shaped commands, or change configs while planning.
- Ask when scope is ambiguous (granularity, defaults, irreversible choices); otherwise decide and state assumptions briefly.
- If stuck on a requirement that can't be resolved by stating an assumption — especially anything irreversible or security-relevant — stop and ask rather than guessing.
- Report in this shape: what changed (files), why, how verified (build result, screenshot path), what's left. Short and factual.
- Push back when asked to do something harmful — deleting or weakening checks to go green, committing secrets, claiming original-format compatibility, or copying the original's resources in. Explain why, and offer the safe alternative instead of just refusing.

## 11. Commits & PRs

- Nothing here happens until the user asks. Prepare the change, leave it uncommitted, and offer the message (section 2).
- Conventional style: `type(scope): imperative summary` — e.g. `feat(locus): sample the driver path into a traced target`.
- Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
- Body (when non-trivial): what moved, why, verification line. Pure refactors state "no behavior change" explicitly.
- One logical change per commit — don't bundle a refactor and a feature, and don't spread one change across unrelated commits.
- PRs: one logical change, targeting `main`, with what/why/how-verified and any unchecked DoD boxes.

## 12. Shipping Status

Nothing is set up yet: no CI workflow, no release process, no signed `.app`, no icon, no versioning scheme. The repo builds and runs as an unbundled executable.

Anything in that list is a design decision, not a chore: propose the approach and get approval before building it. Two constraints to carry into that discussion: a real bundle needs an exported `gsp` document type for the open/save panels to filter correctly, and distributing an app that reimplements a trademarked product needs its own naming and legal review.

`README.md` still describes a Rust launcher and `cargo build` from the project this code came from; that launcher is not in this repo. When you next touch the README, correct the build section to the SwiftPM commands in section 1.
