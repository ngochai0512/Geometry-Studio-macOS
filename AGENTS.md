# AGENTS.md — Working Agreement

This file instructs AI coding agents working in this repo. Humans: `README.md` is the product doc; this is the collaboration contract. Keep both current — when a rule below is violated and it hurts, fix the code; when a rule is wrong, fix this file.

## Orientation

Read this before exploring; it saves a full README pass.

- Native macOS SwiftUI app: a dynamic geometry sketchpad (points, lines, circles, polygons, constructions, measurements, transforms, a graph). Built for Apple silicon; macOS 27 floor.
- Build system: two descriptions, one source of truth per job. `Package.swift` defines the executable and test targets and drives `swift build`, `swift test` and `swift run`. `project.yml` (XcodeGen 2.46) generates `GeometryStudio.xcodeproj`, the app target that carries `Info.plist`, the exported `gsp` document type and the icon. Never hand-edit the generated project: change `project.yml` and run `xcodegen generate`.
- Entry point: `main.swift` → `GeometryStudioApp.main()` in `App/GeometryStudioApp.swift`. That file must not gain `@main` while `main.swift` exists — two entry points do not compile.
- Layering, one concern per file:
  - `Geometry/` — value types and math, no document state: `Vec2.swift` (`Vec2`, `WorldRect`), `EvalPath.swift` (+ intersection helpers, `clipLine`), `Expression.swift`, `Style.swift` (`RGBA`, `ObjectStyle`, dash/shape), `Units.swift` (`LengthUnit`, `AngleUnit`, `SketchMetrics`), `GridMetrics.swift` (grid step, label density, number text).
  - `Model/` — `ObjectModel.swift` (`SketchObject`, `ObjectKind`), `Document.swift` (`CanvasSettings`, `SketchDocument`, revision and salvage), `SketchFileDocument.swift` (the observable `Document` SwiftUI reads and writes, plus the `SketchSnapshot` file codec), `AppPreferences.swift` (new-sketch defaults), `GeometryEval.swift` (parent→child resolution), `SketchTool.swift`, and `SketchModel` split across `SketchModel.swift` (state, lifecycle, undo, object helpers) plus `SketchModel+{Geometry,Editing,ToolActions,Animation,Construction,Measurement,Transforms}.swift`.
  - `Views/` — `ContentView.swift` (chrome, toolbar, sheets), `DocumentWorkspace.swift` (document/model sync and focused values), `InspectorView.swift`, `SettingsView.swift`, `SketchCanvas.swift` (state and body), `CanvasDrawing.swift`, `CanvasGestures.swift`, `FlowChips.swift`, `AboutView.swift`.
  - `Printing/` — `SketchPrinter.swift` (page fit, `NSPrintOperation`, page setup) and `SketchPrintView.swift` (one-page print view).
  - `Export/` — `SketchExportFormat.swift` (format list and export canvas size), `SketchRenderOutput.swift` (fitted snapshot; PNG, vector PDF and print images), `SVGExporter.swift` (vector SVG writer), `SketchExporter.swift` (save panel and file write).
  - `App/` — `GeometryStudioApp.swift` (document scene), `FocusedSketchModel.swift` (active window for menus), `SketchCommands.swift` (menus), `Notifications.swift`, `Screenshot.swift` (headless render path); bundle resources in `App/Info.plist` and `App/Assets.xcassets`.
- `SketchModel` extensions cannot add stored properties: new `@Published` state belongs in `SketchModel.swift`; behavior goes in the extension file matching its area.
- Object graph: `SketchObject` is identified by `UUID`; parents are referenced by `UUID` inside `ObjectKind` (e.g. `.transformed(source:spec:)`, `.locus(driver:target:)`). `GeometryEval` resolves parents before children on every redraw. Pass IDs, never object references.
- Persisted shape: `SketchDocument { version, objects, settings, title }`, encoded as pretty-printed sorted-key JSON with a `.gsp` extension. The document carries a schema revision (`SketchDocument.currentVersion`) and migrates older revisions while decoding; models decode missing keys with their defaults, so a new field does not invalidate old sketches. Refuse a revision from a newer build instead of dropping keys.
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

Verify API availability against the macOS 27.0 floor (section 5) before using a symbol; ask first if it is newer.

## 0. Clean-Room and Provenance

This project is an independent reimplementation, not a port. `MECHANICS.md` is the spec: it records what was observed in the original 2013 32-bit the legacy framework binary — addresses, struct layout, factory defaults.

- Never commit the original `the reference app bundle` bundle, its `Localizable.strings` extracts, its help book, or any other extracted resource. `MECHANICS.md` may cite an address or quote one diagnostic string; bulk resource dumps do not belong in this repo.
- The `.gsp` files this app writes are its own JSON format. Never claim the original binary format is read or written, and do not add a decoder that pretends to.
- Do not use "the reference application" or "the reference app" as a product name, bundle identity, repo name, or marketing claim.

## 1. Verify, Don't Assume

- Read the code before changing it. Never edit from memory of an earlier turn.
- Use the two build paths directly, with no wrapper scripts:

  ```sh
  # Package targets: fast loop, tests and the headless render
  swift build
  swift build -c release
  swift test
  swift run GeometryStudio
  ./.build/release/GeometryStudio --screenshot /tmp/geometry-studio.png

  # App bundle: Info.plist, exported gsp type, icon
  xcodegen generate
  open GeometryStudio.xcodeproj
  xcodebuild -project GeometryStudio.xcodeproj -scheme GeometryStudio -configuration Debug build
  ```

  Both paths compile the same `GeometryStudio/` sources; keep both green. The generated project is disposable — regenerate it from `project.yml` rather than editing it.

- Tests cover the pure-value core: `swift test` runs the `GeometryStudioTests` suite. They use no windows, timers, files or network — keep them that way.
- If a build fails because a nested sandbox blocks SwiftPM's manifest or the compiler's macro plugin server, stop and report it. Do not add sandbox-bypass flags such as `--disable-sandbox` (section 2).
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
- Never try to disable, bypass, escape or loosen the sandbox such as "-disable-sandbox" or any equivalent parameters like that.
- Never skip hooks or amend someone else's commit.
- Never run `sudo`, `rm -rf`, or `defaults write` / `defaults delete`. Don't touch system settings or files outside the repo.
- Only touch files/folders explicitly named in the task or a path the user gives you. If a task seems to require anything outside that scope, stop and ask rather than assuming it is in bounds.
- Off-limits without an explicit ask: `Package.swift` (target layout and manifest), `project.yml` (bundle identity, resources and app settings), `MECHANICS.md` (the observed spec), `.gitignore`. Structural changes here invalidate the build or the record of what was verified.

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

- `swift-tools-version: 5.9`; Swift 5 language mode; minimum deployment target macOS 27.0; builds `arm64` on Apple silicon. Keep `MACOSX_DEPLOYMENT_TARGET` at 27.0: Xcode's "recommended" upgrade rewrites it to `$(RECOMMENDED_MACOSX_DEPLOYMENT_TARGET)`, which is the SDK's floor (14.0 under Xcode 27), not the app's. CI fails if that happens.
- XcodeGen 2.46 generates `GeometryStudio.xcodeproj` from `project.yml`; run `xcodegen generate` after changing the spec. The generated project is not the source of truth. Xcode 27 may upgrade it to `objectVersion = 110`, while XcodeGen emits 77; regenerate rather than committing an upgraded project. CI reads the checked-in value, regenerates to the 77 baseline, and fails if the installed XcodeGen emits a newer format.
- Xcode 27 or later builds the app target (`objectVersion = 77`), because only it ships the macOS 27 SDK. Xcode is still optional for the package targets: `swift build` and `swift test` must keep working without opening the project, and both paths compile the same sources.
- The compiler expression-time threshold is pinned to 110 seconds: `Other Swift Flags` in `project.yml` for the app target, and `-Xswiftc -Xfrontend -Xswiftc -solver-expression-time-threshold=110` on the CI and release `swift build` / `swift test` steps. Keep those in sync. If an expression still times out, split the expression; do not raise the threshold to hide it.
- If local Xcode and the command line differ, say which one you built with rather than silently reporting a result from the other.
- The app bundle declares `com.geometrystudio.gsp` (conforms to `public.json`) and owns `.gsp` files. `UTType.geometryStudioSketch` mirrors that declaration so the open and save panels filter correctly under `swift run` too. Bundle identifier `com.geometrystudio.GeometryStudio` and marketing version `0.1.0` are provisional.
- There are no entitlements and no App Sandbox yet; signing is automatic/ad-hoc, and notarization is not set up (item #9). Do not claim the app is sandboxed or notarized. Printing uses AppKit's print panels; enabling App Sandbox later also needs the printing entitlement.

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
- **API currency:** do not use deprecated or soon-to-be-deprecated APIs. Prefer current alternatives; check the symbol against macOS 27 availability.

## 7. Error Handling

- SwiftUI's `DocumentGroup`/`Document` owns opening and saving. `SketchSnapshot.decode(from:)` throws on unreadable files and falls back to `SketchDocument.salvage` for partly damaged ones; the window surfaces that once. Do not reintroduce hand-rolled open/save panels. Interactive failures still report through `statusMessage`. Never crash and never fail silently.
- `try?` and empty `catch` blocks require a one-line comment explaining why ignoring the error is safe.
- Decoding must tolerate a missing new field. Never add a non-optional `Codable` property without a default value; that turns every previously saved sketch into an error. When a change cannot be additive, bump `SketchDocument.currentVersion` and add a step to its migration ladder.
- No force-unwraps or `try!` in model or math code. `!` is acceptable only where the invariant is local and obvious within a few lines.
- Don't dump raw `localizedDescription` into a panel without review; it is technical text, not product copy.

## 8. Testing

- The test target is `GeometryStudioTests`, built from `GeometryStudioTests/` and linked with `@testable import GeometryStudio`. Do not add a second test target without a reason.
- Keep the suites pure-value: `EvalPath` intersections (line/line, line/circle, circle/circle), `Expression` parsing and evaluation, unit conversion, `GeometryEval` parent ordering, document round-trip. Construct `SketchObject` values directly.
- A new pure type arrives with a test in the matching suite. UI behavior is verified with `--screenshot`, never by adding test infrastructure that needs a window.
- Determinism: no windows, no timers, no wall-clock, no filesystem.
- Compare doubles with a tolerance of `1e-7`, matching the dedupe threshold already used in `EvalPath`.
- Rendering is verified with `--screenshot` and an eyeball check, never with pixel assertions or performance timing.

## 9. Definition of Done

Before reporting a change as finished, confirm all of the following:

- [ ] `swift build` succeeds with zero new warnings.
- [ ] `xcodegen generate` reflects `project.yml`, and the app target builds with zero new warnings.
- [ ] `swift test` passes (43 tests, 8 suites) — or the report says which suite could not run and why.
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

A bundle target exists: `project.yml` generates the Xcode app with `Info.plist`, the exported `gsp` document type, an icon, and version `0.1.0`. CI (`.github/workflows/ci.yml`) builds the package, runs the tests, builds the app and runs the screenshot check. Tagged `v*` releases build an arm64 Developer ID app, notarize and staple it, and publish a zip to GitHub Releases (`RELEASING.md`). Still missing: a signing identity and notarization secrets in this repo, Sparkle updates, DMG packaging and a versioning policy beyond tags. The bundle identifier, icon and marketing copy are provisional, and `project.yml` is a design decision — propose structural changes before building them. Shipping a reimplementation of a trademarked product still needs its own naming and legal review.

`README.md` still describes a Rust launcher and `cargo build` from the project this code came from; that launcher is not in this repo. When you next touch the README, correct the build section to the SwiftPM commands in section 1.
