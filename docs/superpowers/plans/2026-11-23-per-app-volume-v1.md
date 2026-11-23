# Per-app volume v1 — Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open-source menu bar app for macOS. It controls the volume, mute and output of each app, and the EQ, balance and mono of each output device, using Core Audio process taps without drivers.

**Architecture:** Swift Package with four kinds of piece:

- **`PAVCore`**: pure, testable logic (DSP, rules, tap planner, grouping, settings, AutoEQ).
- **`PAVAudio`**: Core Audio wrappers (system monitor, taps and aggregates backend, engine that reconciles the desired state with the real one).
- **`PerAppVolume`**: the SwiftUI `MenuBarExtra` app.
- **Command-line tools**: `pav-diag` (manual diagnostics) and `autoeq-index` (generates the AutoEQ index).

A script packages the executable as a `.app`. The engine follows a "plan and reconcile" pattern: `TapPlanner` computes which taps should exist and `TapEngine` creates, updates or destroys what is needed through the `AudioBackend` protocol, which has a fake implementation for the tests.

**Tech Stack:** Swift 6.3 (Xcode 26.4), SwiftPM, SwiftUI, Core Audio (`CATapDescription`, `AudioHardwareCreateProcessTap`, `AudioHardwareCreateAggregateDevice`), Accelerate/vDSP, Swift Testing, [swift-atomics](https://github.com/apple/swift-atomics) 1.2+, ServiceManagement (`SMAppService`).

**Spec:** `docs/superpowers/specs/2026-11-23-per-app-volume-design.md`. Read it before any task: the `§x` references in this plan point to that document.

## Global Constraints

- Minimum platform: `.macOS("14.4")` in `Package.swift` and `LSMinimumSystemVersion` = `14.4`. Universal binary (arm64 + x86_64) in the packaging.
- Provisional product name: `PerAppVolume`. Prefix for our own UIDs: `io.github.perappvolume.` (taps: `…tap.`, aggregates: `…agg.`). Visible name of the aggregates: `PerAppVolume`.
- Per-app volume: range `0.0…2.0` (0 %–200 %), 1.0 by default. The soft limiter guarantees that no sample exceeds ±1.0.
- Gain ramp of **20 ms** on every volume or mute change.
- Added latency of at most **~20 ms** on wired, built-in or USB outputs. Aggregate I/O buffer: **256 frames**.
- EQ: up to **10** parametric **bands** (peaking, low shelf, high shelf) + preamp.
- Balance in `-1.0…1.0` (0 = center).
- Taps: `isPrivate = true`, `muteBehavior = .mutedWhenTapped`. Aggregates: private, with drift compensation on the subdevice and on the tap, and `TapAutoStart = 1`.
- Excluded from the per-app output menu: AirPlay transport, aggregates and multi-output, and any device whose UID starts with `io.github.perappvolume.`.
- Label of the default output option: **"Automatic (whatever the app uses)"**.
- Settings in `~/Library/Application Support/PerAppVolume/settings.json`, with `"version": 1`.
- The audio callback does not allocate memory, does not take locks, does not use Objective-C or Swift with ARC on class objects, and does no I/O.
- Do not copy code, text, names or resources from other apps.
- No sandbox in v1 (builder's decision, §6). `Info.plist` has `LSUIElement = true` and `NSAudioCaptureUsageDescription` = "PerAppVolume needs access to each app's audio to change its volume and equalize it. Audio never leaves your Mac."
- Commits: messages in English and conventional format (`feat:`, `test:`, `chore:`…). **No `Co-Authored-By` trailer or any attribution to Claude or Anthropic.**
- Language: all code, comments, docs, commit messages and UI strings are in English.

## Review Focus

1. **Tap created but aggregate or IOProc fails.** The tap already mutes the app (`mutedWhenTapped`), so the app would be left silent. Expected: the tap is destroyed immediately, the app plays unprocessed, its row shows ⚠️ and it is not retried in a loop. → Test in Task 9.
2. **Assigned device that disconnects while playing.** Expected: the app moves to the default output and returns to the device on its own when it reconnects, without losing the saved assignment. → Test in Task 3, at planner level.
3. **Chrome or Electron start and stop helpers constantly.** Expected: a single row per app, and the tap is *updated* without being recreated (`updateTap`, never `destroy` + `create`). → Tests in Task 4 (grouping) and Task 9 (reconciliation).
4. **`settings.json` corrupt, empty or from a newer version.** Expected: the app launches with default values and does not crash.
   - If it is corrupt, it is renamed to `settings.corrupt-<timestamp>.json`.
   - If it is from a newer version, it is not overwritten and the app works in memory.
   - → Tests in Task 5.
5. **Extreme gain values.**
   - 200 % on a full-scale signal never gives samples above ±1.0.
   - 0 % gives exact zeros after the ramp.
   - An abrupt slider change does not produce jumps between samples larger than the ramp allows.
   - → Tests in Task 1.

---

## File structure

```
Package.swift
Sources/PAVCore/
  DSP/GainRamp.swift  DSP/SoftLimiter.swift  DSP/Biquad.swift  DSP/EQChain.swift
  DSP/BalanceMono.swift  DSP/ProcessingChain.swift  DSP/ParameterSlot.swift
  Model/AppID.swift  Model/AppSettings.swift  Model/DeviceSettings.swift  Model/SystemSnapshot.swift
  Planning/ProcessingRule.swift  Planning/TapPlanner.swift
  Grouping/AppGrouper.swift
  Persistence/SettingsStore.swift
  AutoEQ/ParametricEQParser.swift  AutoEQ/AutoEQCatalog.swift
Sources/PAVAudio/
  AudioObject+Properties.swift  AudioSystemMonitor.swift  DeviceFilter.swift
  AudioBackend.swift  CoreAudioBackend.swift  AggregateDescription.swift  TapEngine.swift
Sources/PerAppVolume/
  PerAppVolumeApp.swift  AppState.swift
  Views/MenuBarView.swift  Views/AppRowView.swift  Views/DeviceSectionView.swift
  Views/Settings/SettingsView.swift  Views/Settings/DeviceSettingsView.swift
  Views/Settings/AppsSettingsView.swift  Views/Settings/GeneralSettingsView.swift
  Resources/autoeq.json
Sources/pav-diag/main.swift
Sources/autoeq-index/main.swift
Tests/PAVCoreTests/…   Tests/PAVAudioTests/…
App/Info.plist  App/PerAppVolume.entitlements
scripts/build-app.sh  scripts/generate-autoeq.sh
docs/manual-test-checklist.md  README.md  .github/workflows/ci.yml
```

---

### Task 1: Package skeleton + ramped gain + limiter

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `build/`, `*.xcuserstate`)
- Create: `Sources/PAVCore/DSP/GainRamp.swift`, `Sources/PAVCore/DSP/SoftLimiter.swift`
- Test: `Tests/PAVCoreTests/GainRampTests.swift`, `Tests/PAVCoreTests/SoftLimiterTests.swift`

**Interfaces:**
- Produces:
  - `public struct GainRamp { public init(sampleRate: Double, rampDuration: Double = 0.020, initial: Float = 1.0); public mutating func setTarget(_ gain: Float); public mutating func apply(to buffer: UnsafeMutablePointer<Float>, frames: Int, channels: Int); public var current: Float { get }; public var isSettled: Bool { get } }`. The buffer is interleaved.
  - `public struct SoftLimiter { public init(threshold: Float = 0.891); public func process(_ buffer: UnsafeMutablePointer<Float>, count: Int) }`. The 0.891 threshold is equivalent to −1 dBFS.

- [ ] **Step 1: Create `Package.swift`**
  - `platforms: [.macOS("14.4")]`.
  - Targets `PAVCore` (dependency `Atomics` from swift-atomics `from: "1.2.0"`), `PAVAudio` (depends on `PAVCore`) and executables `PerAppVolume` (resources `.process("Resources")`), `pav-diag` and `autoeq-index`.
  - Test targets `PAVCoreTests` and `PAVAudioTests`.
  - Create an empty file in each target so that it compiles.
- [ ] **Step 2: Write the failing tests**

```swift
@Test func rampReachesTargetAfter20ms() {
  var r = GainRamp(sampleRate: 48_000, initial: 1.0); r.setTarget(0.5)
  var buf = [Float](repeating: 1, count: 960 * 2)        // 20 ms stereo
  buf.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 2) }
  #expect(abs(buf[buf.count - 1] - 0.5) < 1e-4); #expect(r.isSettled)
}
@Test func rampHasNoJumpsBiggerThanStep() {   // 1.0 → 0.0 over 960 frames
  var r = GainRamp(sampleRate: 48_000, initial: 1.0); r.setTarget(0)
  var buf = [Float](repeating: 1, count: 960)
  buf.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 1) }
  for i in 1..<buf.count { #expect(abs(buf[i] - buf[i-1]) <= 1.0/960 + 1e-6) }
}
@Test func zeroGainGivesExactZerosAfterRamp() { /* target 0, apply 2×960 frames, the 2nd block is all exact 0.0 */ }
@Test func limiterNeverExceedsFullScaleAt200Percent() {
  // 1 kHz sine amplitude 1.0 × 2.0 (gain applied beforehand) → process → max(|x|) <= 1.0
}
@Test func limiterIsTransparentBelowThreshold() { /* sine amplitude 0.5 → identical output (error < 1e-6) */ }
```

- [ ] **Step 3: Run `swift test --filter GainRampTests` and `--filter SoftLimiterTests`.** Expected: FAIL (the types do not exist).
- [ ] **Step 4: Implement.**
  - `GainRamp`: linear per-frame ramp, with step `(target - current) / (rampDuration * sampleRate)`, computed in `setTarget`.
  - `SoftLimiter`: per sample, identity if `|x| <= threshold`. Above it, `sign(x) * (t + (1 - t) * tanh((|x| - t) / (1 - t)))`, which is continuous and bounded by 1.0.
  - Neither of them allocates memory in `apply`/`process`.
- [ ] **Step 5: Run `swift test`.** Expected: PASS.
- [ ] **Step 6: Commit.** `git init` is already done. `git add -A && git commit -m "feat: package skeleton, gain ramp and soft limiter"`.

---

### Task 2: Biquad EQ, balance/mono, processing chain and lock-free parameter passing

**Files:**
- Create: `Sources/PAVCore/DSP/Biquad.swift`, `EQChain.swift`, `BalanceMono.swift`, `ProcessingChain.swift`, `ParameterSlot.swift`
- Create: `Sources/PAVCore/Model/DeviceSettings.swift`, because the EQ uses it.
- Test: `Tests/PAVCoreTests/BiquadTests.swift`, `BalanceMonoTests.swift`, `ProcessingChainTests.swift`, `ParameterSlotTests.swift`

**Interfaces:**
- Consumes: `GainRamp`, `SoftLimiter` (Task 1).
- Produces:
  - `public enum FilterType: String, Codable, Sendable { case peaking, lowShelf, highShelf }`
  - `public struct EQBand: Codable, Sendable, Equatable { var type: FilterType; var frequency: Float; var gainDB: Float; var q: Float; var enabled: Bool = true }`
  - `public struct DeviceSettings: Codable, Sendable, Equatable`, with:
    - `var eqEnabled = false; var preampDB: Float = 0; var bands: [EQBand] = []`, maximum 10, truncated on decoding
    - `var autoEQName: String? = nil; var balance: Float = 0; var mono = false`
    - `var isActive: Bool { (eqEnabled && (!bands.isEmpty || preampDB != 0)) || balance != 0 || mono }`
  - `public struct BiquadCoefficients: Sendable, Equatable { b0,b1,b2,a1,a2: Double; static func make(_ band: EQBand, sampleRate: Double) -> BiquadCoefficients; func magnitudeDB(at hz: Double, sampleRate: Double) -> Double }`. The formulas are those from RBJ's *Audio EQ Cookbook*.
  - `public struct ChainParameters: Sendable, Equatable { var gain: Float; var muted: Bool; var device: DeviceSettings; var sampleRate: Double }`
  - `public final class ProcessingChain: @unchecked Sendable { public init(channels: Int, maxFrames: Int, sampleRate: Double); public func update(_ p: ChainParameters); public func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frames: Int) }`
    - `update` is called from any thread that is not real-time.
    - `process` is called only from the audio callback. It works with interleaved buffers of `channels` channels.
  - `public final class ParameterSlot<T>: @unchecked Sendable { init(_ initial: T); func publish(_ value: T); func consumeLatest() -> T }`
    - SPSC triple buffer: the writer never blocks the reader.
    - The reader, on the real-time thread, only does atomic operations on a `ManagedAtomic<UInt8>`, where the bits indicate the index of the ready buffer and the "new" flag.
    - The three buffers are preallocated.

- [ ] **Step 1: Write the failing tests.**
  - `peakingBandHasGainAtCenter`: peaking band at 1 kHz, +6 dB, Q 1, at 48 kHz. `abs(magnitudeDB(at: 1000) - 6) < 0.05` and `abs(magnitudeDB(at: 50)) < 0.5` hold.
  - `lowShelfAndHighShelfReachGainAtExtremes`: low shelf at 105 Hz, −3 dB, gives `magnitudeDB(at: 20) ≈ -3 ± 0.3`. The equivalent high shelf at 10 kHz gives ≈ its gain at 20 kHz.
  - `coefficientsChangeWithSampleRate`: the coefficients of the same band at 44.1 kHz and at 48 kHz are different.
  - `balanceFullLeftSilencesRight`: with `balance -1`, the right channel is all 0 and the left one does not change.
  - `monoAveragesChannels`: input L=1, R=0 gives L=R=0.5.
  - `chainAtUnityIsBitTransparent`: gain 1, no mute, default `DeviceSettings()`. The output is identical to the input, with exact `==`.
  - `chainMutedOutputsSilenceAfterRamp`.
  - `chain200PercentNeverClips`: full-scale sine with `gain 2.0`, all `|x| <= 1.0`.
  - `parameterSlotDeliversLatestValue`: `publish(1)`, `publish(2)`, and then `consumeLatest() == 2`. If there are no new publications, it returns the last value.
- [ ] **Step 2: `swift test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `ProcessingChain.process`:
    1. `consumeLatest()` from a `ParameterSlot<PreparedParams>`. `PreparedParams` carries precomputed coefficients for 10 bands (fixed-size array of 10) and the number of active bands.
    2. If there are new parameters, adjust the `GainRamp` target (`muted` → 0).
    3. If `gain == 1 && !muted && !device.isActive && ramp.isSettled`, do a `memcpy` and return. This is the **bypass** of the transparent mode from §8.2.
    4. Otherwise: copy, apply ramp, preamp, biquads with per-channel state (Direct Form II transposed), balance/mono, and the limiter when `gain > 1` or when the sum of preamp + maximum band gain > 0.
  - Coefficient computation is done in `update`, not in `process`.
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: biquad EQ, balance/mono and lock-free processing chain`.

---

### Task 3: Models, processing rule and tap planner

**Files:**
- Create: `Sources/PAVCore/Model/AppID.swift`, `AppSettings.swift`, `SystemSnapshot.swift`, `Sources/PAVCore/Planning/ProcessingRule.swift`, `TapPlanner.swift`
- Test: `Tests/PAVCoreTests/ProcessingRuleTests.swift`, `TapPlannerTests.swift`

**Interfaces:**
- Consumes: `DeviceSettings` (Task 2).
- Produces:
  - `public struct AppID: Hashable, Codable, Sendable { public let rawValue: String }`. It is the bundle ID or, if there is none, the executable path.
  - `public struct AppSettings: Codable, Sendable, Equatable { var volume: Float = 1; var muted = false; var outputDeviceUID: String? = nil; var displayName: String; var lastSeen: Date? }`
  - `public enum TransportKind: String, Sendable { case builtIn, usb, bluetooth, airPlay, aggregate, virtual, hdmi, displayPort, thunderbolt, other }`
  - `public struct OutputDevice: Sendable, Hashable { uid: String; name: String; transport: TransportKind; sampleRate: Double; channels: Int }`
  - `public struct AppGroup: Sendable, Hashable { id: AppID; displayName: String; processObjectIDs: Set<UInt32>; isPlaying: Bool; outputDeviceUIDs: [String] }`
  - `public struct SystemSnapshot: Sendable, Equatable { apps: [AppGroup]; devices: [OutputDevice]; defaultOutputUID: String? }`
  - `public enum TapKind: Hashable, Sendable { case app(AppID), rest(deviceUID: String) }`
  - `public struct TapSpec: Hashable, Sendable`, with:
    - `kind: TapKind; processObjectIDs: Set<UInt32>; exclusive: Bool; outputDeviceUID: String; outputSampleRate: Double`
    - `var structuralKey: StructuralKey { get }`, where `public struct StructuralKey: Hashable, Sendable { kind; exclusive; outputDeviceUID; outputSampleRate }`. If it changes, the tap must be recreated.
  - `public enum ProcessingRule`, with:
    - `static func automaticOutputUID(for app: AppGroup, snapshot: SystemSnapshot) -> String?`: first UID of `app.outputDeviceUIDs` present in `snapshot.devices`; otherwise, `snapshot.defaultOutputUID`.
    - `static func effectiveOutputUID(for app: AppGroup, settings: AppSettings?, snapshot: SystemSnapshot) -> String?`: the assigned output if it exists in `snapshot.devices`; otherwise, `defaultOutputUID` when the assignment is missing (§8.4); if there is no assignment, `automaticOutputUID`.
    - `static func needsProcessing(app: AppGroup, settings: AppSettings?, deviceSettings: [String: DeviceSettings], snapshot: SystemSnapshot) -> Bool`: this is the rule from §8.2.
  - `public enum TapPlanner { static func plan(snapshot: SystemSnapshot, appSettings: [AppID: AppSettings], deviceSettings: [String: DeviceSettings], keepAlive: Set<AppID>) -> [TapSpec] }`
  - `public enum KeepAlive { static func next(current: Set<AppID>, snapshot: SystemSnapshot, plannedApps: Set<AppID>) -> Set<AppID> }`: adds the planned apps that are playing and removes those that are no longer playing (§8.2, transitions).

**Rules the planner must follow** (copied from §8.2–8.4):
- **Per-app tap** if `needsProcessing || keepAlive.contains(id)`, and the app `isPlaying` or was already in `keepAlive`. Uses `exclusive = false`, `processObjectIDs` = those of the app, and `outputDeviceUID` = `effectiveOutputUID`.
- **"rest" tap** for each device `D` with `deviceSettings[D].isActive`, only if `D == defaultOutputUID` or some app that is playing without its own tap has `automaticOutputUID == D`.
  - Uses `exclusive = true`, and `processObjectIDs` = the union of the processes of all apps with their own tap (the excluded ones).
- Apps with their own tap whose effective output is `D` apply `D`'s chain in their own tap. There is no double processing.

- [ ] **Step 1: Write the failing tests** (a fixture `SystemSnapshot` with "Built-in", "USB-DAC" and "AirPods").
  - `untouchedAppAtDefaultsGetsNoTap`: Spotify is playing, with settings `nil`, and `plan` returns `[]`. This is the main anti-goal.
  - `volumeChangeCreatesAppTap`: volume 0.8 gives a `TapSpec(kind: .app(spotify), exclusive: false, outputDeviceUID: "builtin")`.
  - `resetToDefaultsKeepsTapWhilePlaying`: volume 1.0 and `keepAlive = [spotify]` while playing give the tap still present. When `isPlaying = false`, `KeepAlive.next` removes it and the next `plan` gives `[]`.
  - `appKeepsItsOwnDeviceWhenOnlyVolumeChanges`: Zoom with `outputDeviceUIDs = ["usb-dac"]`, default `builtin`, and volume 0.5 give `outputDeviceUID == "usb-dac"`.
  - `assignedDeviceMissingFallsBackToDefault`: assigned `"airpods"` missing from the snapshot gives `"builtin"`, and `settings.outputDeviceUID` is still `"airpods"`. **(Review Focus 2)**
  - `assignedDeviceReturnsWhenReconnected`: the same case with `"airpods"` present gives `"airpods"`. **(Review Focus 2)**
  - `deviceEQCreatesExclusiveRestTapExcludingTappedApps`: EQ active on builtin (default) plus Spotify at 0.8 give two specs. One is `.app(spotify)` and the other `.rest("builtin")`, with `exclusive == true` and `processObjectIDs == spotify.processObjectIDs`.
  - `noRestTapForInactiveNonDefaultDevice`.
  - `sampleRateChangeChangesStructuralKey`.
- [ ] **Step 2: `swift test --filter TapPlannerTests`.** Expected: FAIL.
- [ ] **Step 3: Implement** the types and functions from Interfaces. They are pure functions with no side effects.
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: processing rule and tap planner`.

---

### Task 4: Grouping processes into apps

**Files:**
- Create: `Sources/PAVCore/Grouping/AppGrouper.swift`
- Test: `Tests/PAVCoreTests/AppGrouperTests.swift`

**Interfaces:**
- Consumes: `AppID`, `AppGroup` (Task 3).
- Produces:
  - `public struct AudioProcessInfo: Sendable, Hashable { objectID: UInt32; pid: Int32; bundleID: String?; executablePath: String?; isRunningOutput: Bool; outputDeviceUIDs: [String] }`
  - `public protocol ProcessResolving: Sendable { func responsiblePID(for pid: Int32) -> Int32?; func bundleInfo(forExecutablePath path: String) -> (bundleID: String, name: String)? }`. The tests use a fake.
  - `public enum AppGrouper { static func group(_ processes: [AudioProcessInfo], ownPID: Int32, resolver: ProcessResolving) -> [AppGroup] }`

**Resolution order for a process's app:**
1. Responsible process (if it differs from its own): its bundle.
2. The **outermost** `.app` that contains `executablePath`.
3. The process's `bundleID`.
4. `executablePath`.

Our own PID and processes with neither `bundleID` nor path are excluded. `displayName` comes from `bundleInfo`. `isPlaying` is the OR of the processes and `outputDeviceUIDs` the ordered, deduplicated union.

- [ ] **Step 1: Write the failing tests.**
  - `chromeHelpersCollapseIntoChrome`: two processes in `/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/…` plus the main one give a single `AppGroup` with id `com.google.Chrome` and 3 objectIDs. **(Review Focus 3)**
  - `xpcServiceGroupsUnderResponsibleApp`: `com.apple.WebKit.GPU` with `responsiblePID` = Safari's PID gives the group `com.apple.Safari`.
  - `ownProcessIsExcluded`.
  - `isPlayingIsTrueIfAnyProcessPlays`.
- [ ] **Step 2: `swift test --filter AppGrouperTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `AppGrouper.group`** and a real `SystemProcessResolver: ProcessResolving`, which is not tested:
  - `responsiblePID`: resolve with `dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid")`. If the symbol does not exist, return `nil`.
  - `bundleInfo`: use `Bundle(url:)`.
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: group audio processes into apps`.

---

### Task 5: Settings persistence

**Files:**
- Create: `Sources/PAVCore/Persistence/SettingsStore.swift`
- Test: `Tests/PAVCoreTests/SettingsStoreTests.swift` (uses a temporary directory)

**Interfaces:**
- Consumes: `AppSettings`, `DeviceSettings`, `AppID`.
- Produces:
  - `public struct SettingsFile: Codable, Equatable { var version = 1; var apps: [String: AppSettings] = [:]; var devices: [String: DeviceSettings] = [:]; var launchAtLogin = false }`
  - `public final class SettingsStore`, with:
    - `init(directory: URL)`
    - `private(set) var file: SettingsFile`
    - `private(set) var isReadOnly: Bool`
    - `func load() -> LoadOutcome`, with `enum LoadOutcome { case fresh, loaded, recoveredFromCorrupt(backup: URL), newerVersion(Int) }`
    - `func mutate(_ change: (inout SettingsFile) -> Void)`
    - `func flush() throws`
  - `mutate` schedules an atomic write with a **500 ms** debounce (`Data.write(options: .atomic)`). `flush` writes immediately.

- [ ] **Step 1: Write the failing tests.**
  - `missingFileLoadsDefaults` gives `.fresh`.
  - `roundTripPreservesSettings`.
  - `corruptFileIsBackedUpAndDefaultsUsed`: write `"{nope"`. The result is `.recoveredFromCorrupt` and `settings.corrupt-*.json` exists. **(Review Focus 4)**
  - `emptyFileTreatedAsCorrupt`. **(Review Focus 4)**
  - `newerVersionIsNotOverwritten`: `{"version": 99}` gives `.newerVersion(99)` and `isReadOnly`. After `mutate` + `flush`, the file on disk does not change. **(Review Focus 4)**
  - `moreThanTenBandsAreTruncated`.
- [ ] **Step 2: `swift test --filter SettingsStoreTests`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: versioned settings store with corrupt-file recovery`.

---

### Task 6: AutoEQ — parser, catalog and bundled data

**Files:**
- Create: `Sources/PAVCore/AutoEQ/ParametricEQParser.swift`, `AutoEQCatalog.swift`, `Sources/autoeq-index/main.swift`, `scripts/generate-autoeq.sh`
- Create (generated): `Sources/PerAppVolume/Resources/autoeq.json`, `THIRD_PARTY_NOTICES.md`
- Test: `Tests/PAVCoreTests/ParametricEQParserTests.swift`, `AutoEQCatalogTests.swift`

**Interfaces:**
- Consumes: `EQBand`, `FilterType`, `DeviceSettings`.
- Produces:
  - `public enum ParametricEQParser { static func parse(_ text: String) throws -> (preampDB: Float, bands: [EQBand]) }`
    - AutoEQ format: `Preamp: -6.2 dB` and `Filter N: ON PK|LSC|HSC Fc <hz> Hz Gain <db> dB Q <q>`.
    - Ignores `OFF` filters and accepts at most 10 bands.
  - `public struct AutoEQEntry: Codable, Sendable, Hashable { name: String; source: String; form: String; preampDB: Float; bands: [EQBand] }`
  - `public struct AutoEQCatalog { init(entries: [AutoEQEntry]); static func loadBundled(from url: URL) throws -> AutoEQCatalog; func search(_ query: String, limit: Int = 20) -> [AutoEQEntry] }`
    - Search is case- and accent-insensitive, token-based. Exact prefix results come first.
  - CLI `autoeq-index <path/AutoEq/results> <output.json>`:
    - Walks the `*ParametricEQ.txt` files and infers `source` and `form` from the path (`results/<source>/<form>/<name>/`).
    - Deduplicates by `name` with source priority `oratory1990 > crinacle > rtings > innerfidelity > rest`.

- [ ] **Step 1: Write the failing tests.**
  - `parsesPreampAndFilters`: fixture with 1 LSC, 8 PK and 1 HSC gives `preamp -6.2` and 10 bands with the exact values from the fixture.
  - `ignoresOffFilters`.
  - `rejectsGarbage`, which throws an error.
  - `searchFindsHeadphoneCaseInsensitive`: `"hd 650"` finds "Sennheiser HD 650".
  - `searchPrefersPrefixMatch`.
- [ ] **Step 2: `swift test --filter ParametricEQParserTests`.** Expected: FAIL.
- [ ] **Step 3: Implement the parser, the catalog and the CLI.**
- [ ] **Step 4: Check the license (blocking for bundling).**
  - Clone `https://github.com/jaakkopasanen/AutoEq` at a commit pinned in `scripts/generate-autoeq.sh` and read its `LICENSE`.
  - Check that `results/` has no terms of its own.
  - **If it can be bundled:** run `scripts/generate-autoeq.sh` (clones into `build/`, runs `swift run autoeq-index … Sources/PerAppVolume/Resources/autoeq.json`) and write `THIRD_PARTY_NOTICES.md` with the license and the URL.
  - **If it cannot:** apply plan B from §8.6. No `autoeq.json`, and Task 11 implements "Import ParametricEQ.txt…" instead of the search. Record the decision in `THIRD_PARTY_NOTICES.md`.
- [ ] **Step 5: `swift test`.** Expected: PASS. If it was generated, `autoeq.json` must be smaller than 10 MB (`ls -lh`).
- [ ] **Step 6: Commit** `feat: AutoEQ parser, catalog and bundled index`.

---

### Task 7: Core Audio — reading the system (devices, processes, listeners)

**Files:**
- Create: `Sources/PAVAudio/AudioObject+Properties.swift`, `AudioSystemMonitor.swift`, `DeviceFilter.swift`, `Sources/pav-diag/main.swift`
- Test: `Tests/PAVAudioTests/DeviceFilterTests.swift`

**Interfaces:**
- Consumes: `AudioProcessInfo`, `AppGrouper`, `SystemProcessResolver` (Task 4), `OutputDevice`, `TransportKind`, `SystemSnapshot` (Task 3).
- Produces:
  - Generic helpers `AudioObjectID.read<T>(_ selector:, scope:, element:) throws -> T`, `readArray<T>`, `readString` and `readCFString`, which throw `AudioError(status: OSStatus, context: String)`.
  - `public final class AudioSystemMonitor: @unchecked Sendable`, with:
    - `init(queue: DispatchQueue)`
    - `func start(onChange: @escaping @Sendable (SystemSnapshot) -> Void)`
    - `func stop()`
    - `func currentSnapshot() throws -> SystemSnapshot`
  - `public enum DeviceFilter { static func isSelectableAsAppOutput(_ d: OutputDevice) -> Bool }`

**Properties to read:**
- Processes: `kAudioHardwarePropertyProcessObjectList`. For each process, `kAudioProcessPropertyPID`, `…BundleID`, `…IsRunningOutput` and `…Devices` in output scope (the UIDs via `kAudioDevicePropertyDeviceUID`).
- Devices: `kAudioHardwarePropertyDevices`, keeping those that have output streams (`kAudioDevicePropertyStreamConfiguration`, output). For each one, `kAudioDevicePropertyDeviceUID`, `kAudioObjectPropertyName`, `kAudioDevicePropertyTransportType` (map to `TransportKind`) and `kAudioDevicePropertyNominalSampleRate`.
- Default: `kAudioHardwarePropertyDefaultOutputDevice`.

**Listeners** (with `AudioObjectAddPropertyListenerBlock` on `queue`):
- On the system: process list, device list and default output.
- On each process: `IsRunningOutput` and `Devices`.
- On each device: `NominalSampleRate`.
- Changes are coalesced with a **100 ms** debounce and emit a `SystemSnapshot`.
- The snapshot excludes our own aggregates from `devices` (UID with prefix `io.github.perappvolume.`).

- [ ] **Step 1: Write the failing test.** `DeviceFilterTests`:
  - `airPlayIsNotSelectable`, `aggregateIsNotSelectable`, `ownAggregateIsNotSelectable` (UID with prefix).
  - `usbAndBluetoothAndBuiltInAreSelectable`.
- [ ] **Step 2: `swift test --filter DeviceFilterTests`.** Expected: FAIL.
- [ ] **Step 3: Implement** the helpers, `AudioSystemMonitor` and `DeviceFilter`.
  - Implement `pav-diag list`: prints devices (`uid`, `name`, `transport`, `rate`), default output and grouped apps (`id`, `name`, `playing`, `pids`, `devices`).
  - Implement `pav-diag watch`: prints a snapshot on every change.
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Manual verification.**
  - Play something in Spotify or Music and run `swift run pav-diag list`. Expected: the app appears with `playing=true` and with the correct output.
  - Open a video in Chrome. Expected: a single `com.google.Chrome` row.
  - With `swift run pav-diag watch`, connect or disconnect headphones. Expected: a new snapshot arrives in less than 1 s.
- [ ] **Step 6: Commit** `feat: Core Audio system monitor and pav-diag list/watch`.

---

### Task 8: Core Audio — taps, aggregates and I/O backend

**Files:**
- Create: `Sources/PAVAudio/AudioBackend.swift`, `AggregateDescription.swift`, `CoreAudioBackend.swift`
- Modify: `Sources/pav-diag/main.swift`, to add the `tap` subcommand.
- Test: `Tests/PAVAudioTests/AggregateDescriptionTests.swift`

**Interfaces:**
- Consumes: `ProcessingChain`, `ChainParameters` (Task 2), `TapSpec` (Task 3), `AudioError` (Task 7).
- Produces:
  - `public struct TapHandle: Hashable, Sendable { tapID: UInt32; uid: String }`
  - `public struct AggregateHandle: Hashable, Sendable { deviceID: UInt32; uid: String }`. The `AudioDeviceIOProcID` and the callback context are stored inside `CoreAudioBackend`, in a dictionary keyed by `deviceID`.
  - Protocol, used by Task 9 and with a fake implementation in its tests:

```swift
public protocol AudioBackend: AnyObject {
  func createTap(processObjectIDs: [UInt32], exclusive: Bool, deviceUID: String?, uid: String) throws -> TapHandle
  func updateTap(_ tap: TapHandle, processObjectIDs: [UInt32], exclusive: Bool) throws
  func destroyTap(_ tap: TapHandle)
  func createAggregate(uid: String, outputDeviceUID: String, tap: TapHandle) throws -> AggregateHandle
  func startIO(_ agg: AggregateHandle, chain: ProcessingChain) throws
  func stopIO(_ agg: AggregateHandle)
  func destroyAggregate(_ agg: AggregateHandle)
  func destroyStaleObjects(uidPrefix: String)
}
```

  - `public enum AggregateDescription { static func make(uid: String, outputDeviceUID: String, tapUID: String) -> [String: Any] }`. It is a pure function and is tested.

**Implementation details** (values from §8.3):
- `createTap`:
  - Build the `CATapDescription`:
    - **App tap** (`exclusive == false`, `deviceUID == nil`): `CATapDescription(stereoMixdownOfProcesses:)`.
    - **`rest` tap** (`exclusive == true`, `deviceUID = D`): `CATapDescription(excludingProcesses:andDeviceUID: D, withStream: 0)`.
    - The `rest` tap is **bound to device D**. A global exclusive tap would also capture and mute apps playing through other devices without EQ, and would send them to D.
  - Set `isPrivate = true`, `muteBehavior = .mutedWhenTapped`, `name = "PerAppVolume"` and `uuid` derived from `uid`.
  - Call `AudioHardwareCreateProcessTap`.
- `updateTap`: `AudioObjectSetPropertyData(tapID, kAudioTapPropertyDescription, …)` with the modified description. **Does not recreate.**
- `createAggregate` dictionary:
  - `kAudioAggregateDeviceUIDKey: uid`, `NameKey: "PerAppVolume"`, `IsPrivateKey: 1` and `MainSubDeviceKey: outputDeviceUID`.
  - `SubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID, kAudioSubDeviceDriftCompensationKey: 1]]`.
  - `TapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: 1]]` and `TapAutoStartKey: 1`.
  - Afterwards, set `kAudioDevicePropertyBufferFrameSize = 256` on the aggregate.
- `startIO`:
  - `AudioDeviceCreateIOProcID` with a C function (not a block) whose `inClientData` is an unretained pointer to a preallocated context (the chain and the buffer pointers).
  - The callback takes the tap's input buffer and calls `chain.process` into the device's output buffer. If the format is not Float32 interleaved stereo, it converts, or else it is rejected in `startIO` by throwing `AudioError`.
- `destroyStaleObjects`: destroy the taps from `kAudioHardwarePropertyTapList` and the aggregates whose UID starts with the prefix.

- [ ] **Step 1: Write the failing test.** `aggregateDescriptionHasPrivateDriftAndTap`: check all the keys and values from the list above on `AggregateDescription.make(...)`.
- [ ] **Step 2: `swift test --filter AggregateDescriptionTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `CoreAudioBackend`** and implement `pav-diag tap --app <bundleID> --volume <0…2> [--output <uid>]`, which creates tap + aggregate + I/O for that app until Ctrl-C.
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Manual verification.** The first use asks Terminal for audio permission: grant it.
  - With Spotify playing, `swift run pav-diag tap --app com.spotify.client --volume 0.3`. Expected: the volume drops clearly, without dropouts.
  - With `--volume 2.0`, it goes up and there is no hard distortion.
  - With `--output <uid of another device>`, it plays through the other device.
  - `kill -9` of the `pav-diag` process: Spotify goes back to playing normally instantly.
- [ ] **Step 6: Commit** `feat: Core Audio tap/aggregate backend and pav-diag tap`.

---

### Task 9: TapEngine — reconciliation, failures and cleanup

**Files:**
- Create: `Sources/PAVAudio/TapEngine.swift`
- Test: `Tests/PAVAudioTests/TapEngineTests.swift`, with a `FakeAudioBackend` that records calls and can fail on demand.

**Interfaces:**
- Consumes: `AudioBackend`, `TapHandle`, `AggregateHandle` (Task 8), `TapSpec`, `TapKind` (Task 3), `ProcessingChain`, `ChainParameters` (Task 2).
- Produces:
  - `public enum TapStatus: Sendable, Equatable { case active, failed(String) }`
  - `public final class TapEngine`, with:
    - `init(backend: AudioBackend, uidPrefix: String = "io.github.perappvolume.")`
    - `func reconcile(desired: [TapSpec], parameters: (TapKind) -> ChainParameters)`
    - `func updateParameters(for kind: TapKind, _ p: ChainParameters)`
    - `func status(for kind: TapKind) -> TapStatus?`
    - `func shutdown()`
    - `func cleanupStale()`, which calls `backend.destroyStaleObjects(uidPrefix:)`. The app invokes it at launch.

**`reconcile` algorithm** (§8.3), comparing live sessions by `TapKind`:
- Session not in `desired`: `stopIO`, `destroyAggregate`, `destroyTap`.
- Different `structuralKey`: destroy and create.
- Same `structuralKey` but different `processObjectIDs`: `updateTap`.
- New: `createTap`, `createAggregate`, `startIO`. In `createTap`, `deviceUID: nil` is passed for `.app` and `deviceUID: D` for `.rest(D)`.
- **Failure in any step after `createTap`:** undo what was created, **`destroyTap` first** (unmutes the app), and mark `failed(message)`.
  - A `TapKind` in `failed` is not retried until its `TapSpec` changes.

All methods are called from a serial queue owned by the caller (the app uses the monitor's `queue`).

- [ ] **Step 1: Write the failing tests.**
  - `createsTapAggregateAndStartsIOForNewSpec`, which checks the order of the calls.
  - `removesSessionNoLongerDesired`.
  - `processSetChangeUpdatesInsteadOfRecreating`: the calls are exactly `[.updateTap]`, with no `destroyTap` or `createTap`. **(Review Focus 3)**
  - `deviceChangeRecreates`.
  - `aggregateFailureDestroysTapImmediatelyAndMarksFailed`: the fake fails in `createAggregate`. The calls are `[.createTap, .destroyTap]`, the status is `.failed` and there is no live session. **(Review Focus 1)**
  - `startIOFailureUnwindsEverything`. **(Review Focus 1)**
  - `failedSpecIsNotRetriedUntilItChanges`: the same `desired` again produces no new calls; a `desired` with a different output does retry. **(Review Focus 1)**
  - `parameterUpdateDoesNotTouchBackend`: `updateParameters` produces no backend calls.
- [ ] **Step 2: `swift test --filter TapEngineTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `TapEngine`.** Each session has its own `ProcessingChain`, created with the channels and sample rate of the output device and `maxFrames: 4096`.
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: tap engine with reconcile, failure unwinding and stale cleanup`.

---

### Task 10: The app — state, menu bar and packaging

**Files:**
- Create: `Sources/PerAppVolume/PerAppVolumeApp.swift`, `AppState.swift`, `Views/MenuBarView.swift`, `Views/AppRowView.swift`, `Views/DeviceSectionView.swift`
- Create: `App/Info.plist`, `App/PerAppVolume.entitlements` (empty, no sandbox), `scripts/build-app.sh`
- Test: `Tests/PAVCoreTests/` does not apply. This task is verified with the build and the manual checklist.

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `@MainActor @Observable final class AppState`, with:
    - `var rows: [AppRow]`
    - `var defaultDevice: OutputDevice?`
    - `var selectableDevices: [OutputDevice]`
    - `var permissionExplained: Bool`
    - `func setVolume(_ v: Float, for id: AppID)`
    - `func setMuted(_ m: Bool, for id: AppID)`
    - `func setOutput(_ uid: String?, for id: AppID)`
    - `func resetVolume(for id: AppID)`
    - `func updateDeviceSettings(_ uid: String, _ change: (inout DeviceSettings) -> Void)`
    - `func forgetApp(_ id: AppID)`
  - `public struct AppRow: Identifiable { id: AppID; name: String; icon: NSImage?; volume: Float; muted: Bool; outputUID: String?; isPlaying: Bool; status: TapStatus? }`

**Flow in `AppState`:**
1. At launch: `SettingsStore.load()`, `TapEngine.cleanupStale()` and `monitor.start`.
2. On every snapshot or settings change, on the engine queue:
   1. `KeepAlive.next`
   2. `TapPlanner.plan`
   3. `engine.reconcile`
   4. Publish the rows on the main actor.
3. Moving a slider calls `engine.updateParameters` (it does not `reconcile`), unless `needsProcessing` changes.
4. `lastSeen` and `displayName` are saved for each app that plays.

**Permission onboarding:** before creating the **first** tap, if `permissionExplained == false`, a notice is shown in the popover. It explains why the "System Audio Recording" permission is needed and has two buttons: "Continue" (sets the flag and applies) and "Not now".

**UI** (sketch from §8.5):
- Rows of apps that are playing at the top. Apps that played in this session appear below, dimmed (`opacity 0.5`).
- Each row has:
  - icon and name
  - `Slider` 0…200 with its `"%d%%"` label; double-click returns it to 100
  - mute button
  - output menu: "Automatic (whatever the app uses)" plus the `selectableDevices`
  - ⚠️ icon with tooltip when its status is `.failed`
- Default device section: EQ toggle (shows `autoEQName` if there is one), balance indicator and mono toggle.
- Footer: "Settings…" and "Quit".

**`scripts/build-app.sh`:**
1. `swift build -c release --arch arm64 --arch x86_64 --product PerAppVolume`.
2. Assemble `build/PerAppVolume.app/Contents/{MacOS,Resources}` with `App/Info.plist`, copy the SwiftPM resource bundle and sign ad hoc: `codesign --force --options runtime --entitlements App/PerAppVolume.entitlements -s - build/PerAppVolume.app`.

`Info.plist`:
- `CFBundleIdentifier = io.github.perappvolume`
- `LSUIElement`, `LSMinimumSystemVersion` and `NSAudioCaptureUsageDescription` (texts from Global Constraints)

- [ ] **Step 1: Implement `AppState`** with real monitor, planner, engine and store, injected through `init` so they can be replaced later.
- [ ] **Step 2: Implement the views and `PerAppVolumeApp`.** `MenuBarExtra(.window)` with the `speaker.wave.2` icon and a `Settings` scene (placeholder until Task 11).
- [ ] **Step 3: Implement `scripts/build-app.sh`, `Info.plist` and the entitlements.**
- [ ] **Step 4: `scripts/build-app.sh && open build/PerAppVolume.app`.** Expected:
  - the icon appears in the menu bar and not in the Dock
  - with Spotify playing, its row shows at 100 %
  - `swift run pav-diag list` shows no aggregates of our own as long as nothing is touched (main anti-goal, §9)
- [ ] **Step 5: Manual verification.**
  - Lower Spotify to 40 %: the permission notice appears, then the macOS prompt, and then the volume drops.
  - Return to 100 % with a double-click: no dropout.
  - Quit and reopen the app: with Spotify playing, it goes back to 40 %.
  - Send Spotify to another device: it plays through that device.
- [ ] **Step 6: Commit** `feat: menu bar app, state wiring and app bundle script`.

---

### Task 11: Settings window

**Files:**
- Create: `Sources/PerAppVolume/Views/Settings/SettingsView.swift`, `DeviceSettingsView.swift`, `AppsSettingsView.swift`, `GeneralSettingsView.swift`
- Modify: `Sources/PerAppVolume/PerAppVolumeApp.swift`, so that the `Settings` scene uses `SettingsView`.

**Interfaces:**
- Consumes: `AppState` (Task 10), `AutoEQCatalog` / `ParametricEQParser` (Task 6), `DeviceSettings`.
- Produces: SwiftUI views, which nothing consumes.

**Contents:**
- **Devices**:
  - output device picker (`selectableDevices` + the default)
  - EQ toggle, preamp slider from −20 to +6 dB and editor for up to 10 bands (type, Hz 20–20000, dB −20…+20, Q 0.1–10, enabled)
  - AutoEQ search: applies `preampDB`, `bands` and `autoEQName`. If plan B was applied in Task 6, it is replaced by the "Import ParametricEQ.txt…" button with `NSOpenPanel` + `ParametricEQParser`
  - balance slider −1…1 with double-click to 0, and mono toggle
- **Apps**: list of remembered apps (name, saved volume, saved output, `lastSeen`) with the "Forget" button.
- **General**:
  - "Open at login" toggle, with `SMAppService.mainApp.register()` / `unregister()` and its state reflected in `launchAtLogin`
  - explanatory text about the permission
  - "Open Privacy Settings" button that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`

- [ ] **Step 1: Implement the views.**
- [ ] **Step 2: `scripts/build-app.sh && open build/PerAppVolume.app`.** Manual verification:
  - Search for "HD 650" (or import a file) and turn on the EQ: the sound changes in all apps on that device.
  - Turn off the EQ: the sound goes back.
  - Balance fully to the left: only the left channel plays.
  - Mono works.
  - "Forget" removes the app from the list.
  - The login item appears in System Settings → General → Login Items.
- [ ] **Step 3: Commit** `feat: settings window with device EQ, AutoEQ, apps and general tabs`.

---

### Task 12: README, CI and manual test checklist

**Files:**
- Create: `README.md`, `.github/workflows/ci.yml`, `docs/manual-test-checklist.md`

**Contents:**
- `README.md`:
  - what it is
  - requirements (macOS 14.4+)
  - how to build (`scripts/build-app.sh`)
  - audio permission
  - opening a non-notarized app (right-click → Open)
  - known limitations: no AirPlay as per-app output, stereo mixdown, a single device when an app uses several
  - AutoEQ credits
  - license pending decision, §11 of the spec
- `ci.yml`: on `macos-15`, `swift build` + `swift test` on every push and PR.
- `docs/manual-test-checklist.md`:
  - the list from §9 with checkboxes
  - apps: Spotify, Music, Chrome, Safari, Zoom/Meet, a game, Slack/Discord
  - Bluetooth and USB; default output change; `kill -9`
  - "with nothing touched there are no aggregates of our own" (verified with `pav-diag list`)
  - sample rate change in Audio MIDI Setup with EQ active
  - AirPlay default output: untouched apps play normally

- [ ] **Step 1: Write the three files.**
- [ ] **Step 2: `swift build && swift test`.** Expected: PASS. Validate the YAML: `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml")'`.
- [ ] **Step 3: Commit** `docs: README, CI workflow and manual test checklist`.
