# Volumen por app v1 — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App de barra de menú para macOS, opensource. Controla volumen, mute y salida de cada app, y EQ, balance y mono de cada dispositivo de salida, usando Core Audio process taps sin drivers.

**Architecture:** Swift Package con cuatro tipos de pieza:

- **`PAVCore`**: lógica pura y testeable (DSP, reglas, planificador de taps, agrupación, ajustes, AutoEQ).
- **`PAVAudio`**: envoltorios de Core Audio (monitor del sistema, backend de taps y aggregates, motor que reconcilia el estado deseado con el real).
- **`PerAppVolume`**: la app SwiftUI `MenuBarExtra`.
- **Herramientas de línea de comandos**: `pav-diag` (diagnóstico manual) y `autoeq-index` (genera el índice AutoEQ).

Un script empaqueta el ejecutable como `.app`. El motor sigue un patrón "planificar y reconciliar": `TapPlanner` calcula qué taps deberían existir y `TapEngine` crea, actualiza o destruye lo necesario a través del protocolo `AudioBackend`, que tiene una implementación falsa para los tests.

**Tech Stack:** Swift 6.3 (Xcode 26.4), SwiftPM, SwiftUI, Core Audio (`CATapDescription`, `AudioHardwareCreateProcessTap`, `AudioHardwareCreateAggregateDevice`), Accelerate/vDSP, Swift Testing, [swift-atomics](https://github.com/apple/swift-atomics) 1.2+, ServiceManagement (`SMAppService`).

**Spec:** `docs/superpowers/specs/2026-11-23-volumen-por-app-design.md`. Léelo antes de cualquier tarea: las referencias `§x` de este plan son a ese documento.

## Global Constraints

- Plataforma mínima: `.macOS("14.4")` en `Package.swift` y `LSMinimumSystemVersion` = `14.4`. Binario universal (arm64 + x86_64) en el empaquetado.
- Nombre provisional del producto: `PerAppVolume`. Prefijo de UIDs propios: `io.github.perappvolume.` (taps: `…tap.`, aggregates: `…agg.`). Nombre visible de los aggregates: `PerAppVolume`.
- Volumen por app: rango `0.0…2.0` (0 %–200 %), 1.0 por defecto. El limitador suave garantiza que ninguna muestra supera ±1.0.
- Rampa de ganancia de **20 ms** en todo cambio de volumen o mute.
- Latencia añadida de como máximo **~20 ms** en salidas con cable, integradas o USB. Buffer de E/S del aggregate: **256 frames**.
- EQ: hasta **10 bandas** paramétricas (peaking, low shelf, high shelf) + preamp.
- Balance en `-1.0…1.0` (0 = centro).
- Taps: `isPrivate = true`, `muteBehavior = .mutedWhenTapped`. Aggregates: privados, con drift compensation en el subdevice y en el tap, y `TapAutoStart = 1`.
- Excluidos del menú de salida por app: transporte AirPlay, aggregates y multisalida, y cualquier dispositivo con UID que empiece por `io.github.perappvolume.`.
- Etiqueta de la opción de salida por defecto: **"Automática (la que use la app)"**.
- Ajustes en `~/Library/Application Support/PerAppVolume/settings.json`, con `"version": 1`.
- El callback de audio no reserva memoria, no toma locks, no usa Objective-C ni Swift con ARC sobre objetos de clase, y no hace I/O.
- No copiar código, textos, nombres ni recursos de otras apps.
- Sin sandbox en v1 (decisión del builder, §6). `Info.plist` lleva `LSUIElement = true` y `NSAudioCaptureUsageDescription` = "PerAppVolume necesita acceder al audio de cada app para poder cambiar su volumen y ecualizarlo. El audio nunca sale de tu Mac."
- Commits: mensajes en inglés y formato convencional (`feat:`, `test:`, `chore:`…). **Sin trailer `Co-Authored-By` ni ninguna atribución a Claude o Anthropic.**

## Review Focus

1. **Tap creado pero aggregate o IOProc falla.** El tap ya silencia la app (`mutedWhenTapped`), así que la app quedaría muda. Esperado: se destruye el tap de inmediato, la app suena sin procesar, su fila muestra ⚠️ y no se reintenta en bucle. → Test en Task 9.
2. **Dispositivo asignado que se desconecta mientras suena.** Esperado: la app pasa a la salida por defecto y vuelve sola al dispositivo cuando se reconecta, sin perder la asignación guardada. → Test en Task 3, a nivel de planner.
3. **Chrome o Electron arrancan y cierran helpers sin parar.** Esperado: una sola fila por app, y el tap se *actualiza* sin recrearse (`updateTap`, nunca `destroy` + `create`). → Tests en Task 4 (agrupación) y Task 9 (reconciliación).
4. **`settings.json` corrupto, vacío o de una versión más nueva.** Esperado: la app arranca con valores por defecto y no se cuelga.
   - Si está corrupto, se renombra a `settings.corrupt-<timestamp>.json`.
   - Si es de una versión más nueva, no se sobrescribe y se trabaja en memoria.
   - → Tests en Task 5.
5. **Valores extremos de ganancia.**
   - 200 % sobre una señal a fondo de escala nunca da muestras por encima de ±1.0.
   - 0 % da ceros exactos tras la rampa.
   - Un cambio brusco de slider no produce saltos entre muestras mayores que lo que permite la rampa.
   - → Tests en Task 1.

---

## Estructura de archivos

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

### Task 1: Esqueleto del paquete + ganancia con rampa + limitador

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `build/`, `*.xcuserstate`)
- Create: `Sources/PAVCore/DSP/GainRamp.swift`, `Sources/PAVCore/DSP/SoftLimiter.swift`
- Test: `Tests/PAVCoreTests/GainRampTests.swift`, `Tests/PAVCoreTests/SoftLimiterTests.swift`

**Interfaces:**
- Produces:
  - `public struct GainRamp { public init(sampleRate: Double, rampDuration: Double = 0.020, initial: Float = 1.0); public mutating func setTarget(_ gain: Float); public mutating func apply(to buffer: UnsafeMutablePointer<Float>, frames: Int, channels: Int); public var current: Float { get }; public var isSettled: Bool { get } }`. El buffer es interleaved.
  - `public struct SoftLimiter { public init(threshold: Float = 0.891); public func process(_ buffer: UnsafeMutablePointer<Float>, count: Int) }`. El umbral 0.891 equivale a −1 dBFS.

- [ ] **Step 1: Crear `Package.swift`**
  - `platforms: [.macOS("14.4")]`.
  - Targets `PAVCore` (dependencia `Atomics` de swift-atomics `from: "1.2.0"`), `PAVAudio` (depende de `PAVCore`) y ejecutables `PerAppVolume` (resources `.process("Resources")`), `pav-diag` y `autoeq-index`.
  - Test targets `PAVCoreTests` y `PAVAudioTests`.
  - Crear un fichero vacío en cada target para que compile.
- [ ] **Step 2: Escribir los tests que fallan**

```swift
@Test func rampReachesTargetAfter20ms() {
  var r = GainRamp(sampleRate: 48_000, initial: 1.0); r.setTarget(0.5)
  var buf = [Float](repeating: 1, count: 960 * 2)        // 20 ms estéreo
  buf.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 2) }
  #expect(abs(buf[buf.count - 1] - 0.5) < 1e-4); #expect(r.isSettled)
}
@Test func rampHasNoJumpsBiggerThanStep() {   // 1.0 → 0.0 en 960 frames
  var r = GainRamp(sampleRate: 48_000, initial: 1.0); r.setTarget(0)
  var buf = [Float](repeating: 1, count: 960)
  buf.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 1) }
  for i in 1..<buf.count { #expect(abs(buf[i] - buf[i-1]) <= 1.0/960 + 1e-6) }
}
@Test func zeroGainGivesExactZerosAfterRamp() { /* target 0, aplicar 2×960 frames, el 2.º bloque es todo 0.0 exacto */ }
@Test func limiterNeverExceedsFullScaleAt200Percent() {
  // seno 1 kHz amplitud 1.0 × 2.0 (ganancia aplicada antes) → process → max(|x|) <= 1.0
}
@Test func limiterIsTransparentBelowThreshold() { /* seno amplitud 0.5 → salida idéntica (error < 1e-6) */ }
```

- [ ] **Step 3: Ejecutar `swift test --filter GainRampTests` y `--filter SoftLimiterTests`.** Esperado: FAIL (los tipos no existen).
- [ ] **Step 4: Implementar.**
  - `GainRamp`: rampa lineal por frame, con paso `(target - current) / (rampDuration * sampleRate)`, calculado en `setTarget`.
  - `SoftLimiter`: por muestra, identidad si `|x| <= threshold`. Por encima, `sign(x) * (t + (1 - t) * tanh((|x| - t) / (1 - t)))`, que es continuo y está acotado por 1.0.
  - Ninguno de los dos reserva memoria en `apply`/`process`.
- [ ] **Step 5: Ejecutar `swift test`.** Esperado: PASS.
- [ ] **Step 6: Commit.** `git init` ya está hecho. `git add -A && git commit -m "feat: package skeleton, gain ramp and soft limiter"`.

---

### Task 2: EQ biquad, balance/mono, cadena de procesado y paso de parámetros sin locks

**Files:**
- Create: `Sources/PAVCore/DSP/Biquad.swift`, `EQChain.swift`, `BalanceMono.swift`, `ProcessingChain.swift`, `ParameterSlot.swift`
- Create: `Sources/PAVCore/Model/DeviceSettings.swift`, porque el EQ lo usa.
- Test: `Tests/PAVCoreTests/BiquadTests.swift`, `BalanceMonoTests.swift`, `ProcessingChainTests.swift`, `ParameterSlotTests.swift`

**Interfaces:**
- Consumes: `GainRamp`, `SoftLimiter` (Task 1).
- Produces:
  - `public enum FilterType: String, Codable, Sendable { case peaking, lowShelf, highShelf }`
  - `public struct EQBand: Codable, Sendable, Equatable { var type: FilterType; var frequency: Float; var gainDB: Float; var q: Float; var enabled: Bool = true }`
  - `public struct DeviceSettings: Codable, Sendable, Equatable`, con:
    - `var eqEnabled = false; var preampDB: Float = 0; var bands: [EQBand] = []`, máximo 10, se trunca al decodificar
    - `var autoEQName: String? = nil; var balance: Float = 0; var mono = false`
    - `var isActive: Bool { (eqEnabled && (!bands.isEmpty || preampDB != 0)) || balance != 0 || mono }`
  - `public struct BiquadCoefficients: Sendable, Equatable { b0,b1,b2,a1,a2: Double; static func make(_ band: EQBand, sampleRate: Double) -> BiquadCoefficients; func magnitudeDB(at hz: Double, sampleRate: Double) -> Double }`. Las fórmulas son las del *Audio EQ Cookbook* de RBJ.
  - `public struct ChainParameters: Sendable, Equatable { var gain: Float; var muted: Bool; var device: DeviceSettings; var sampleRate: Double }`
  - `public final class ProcessingChain: @unchecked Sendable { public init(channels: Int, maxFrames: Int, sampleRate: Double); public func update(_ p: ChainParameters); public func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frames: Int) }`
    - `update` se llama desde cualquier hilo que no sea de tiempo real.
    - `process` se llama solo desde el callback de audio. Trabaja con buffers interleaved de `channels` canales.
  - `public final class ParameterSlot<T>: @unchecked Sendable { init(_ initial: T); func publish(_ value: T); func consumeLatest() -> T }`
    - Triple buffer SPSC: el escritor nunca bloquea al lector.
    - El lector, en el hilo de tiempo real, solo hace operaciones atómicas sobre un `ManagedAtomic<UInt8>`, donde los bits indican el índice del buffer listo y el flag de "nuevo".
    - Los tres buffers están preasignados.

- [ ] **Step 1: Escribir los tests que fallan.**
  - `peakingBandHasGainAtCenter`: banda peaking a 1 kHz, +6 dB, Q 1, a 48 kHz. Se cumple `abs(magnitudeDB(at: 1000) - 6) < 0.05` y `abs(magnitudeDB(at: 50)) < 0.5`.
  - `lowShelfAndHighShelfReachGainAtExtremes`: low shelf a 105 Hz, −3 dB, da `magnitudeDB(at: 20) ≈ -3 ± 0.3`. El high shelf equivalente a 10 kHz da ≈ su ganancia a 20 kHz.
  - `coefficientsChangeWithSampleRate`: los coeficientes de la misma banda a 44.1 kHz y a 48 kHz son distintos.
  - `balanceFullLeftSilencesRight`: con `balance -1`, el canal derecho es todo 0 y el izquierdo no cambia.
  - `monoAveragesChannels`: entrada L=1, R=0 da L=R=0.5.
  - `chainAtUnityIsBitTransparent`: gain 1, sin mute, `DeviceSettings()` por defecto. La salida es idéntica a la entrada, con `==` exacto.
  - `chainMutedOutputsSilenceAfterRamp`.
  - `chain200PercentNeverClips`: seno a fondo de escala con `gain 2.0`, todas las `|x| <= 1.0`.
  - `parameterSlotDeliversLatestValue`: `publish(1)`, `publish(2)`, y luego `consumeLatest() == 2`. Si no hay publicaciones nuevas, devuelve el último valor.
- [ ] **Step 2: `swift test`.** Esperado: FAIL.
- [ ] **Step 3: Implementar.**
  - `ProcessingChain.process`:
    1. `consumeLatest()` de un `ParameterSlot<PreparedParams>`. `PreparedParams` lleva coeficientes ya calculados para 10 bandas (array fijo de tamaño 10) y el número de bandas activas.
    2. Si hay parámetros nuevos, ajustar el objetivo de `GainRamp` (`muted` → 0).
    3. Si `gain == 1 && !muted && !device.isActive && ramp.isSettled`, hacer `memcpy` y terminar. Este es el **bypass** del modo transparente de §8.2.
    4. Si no: copiar, aplicar rampa, preamp, biquads con estado por canal (Direct Form II transposed), balance/mono, y el limitador cuando `gain > 1` o cuando la suma de preamp + ganancia máxima de banda > 0.
  - El cálculo de coeficientes se hace en `update`, no en `process`.
- [ ] **Step 4: `swift test`.** Esperado: PASS.
- [ ] **Step 5: Commit** `feat: biquad EQ, balance/mono and lock-free processing chain`.

---

### Task 3: Modelos, regla de procesado y planificador de taps

**Files:**
- Create: `Sources/PAVCore/Model/AppID.swift`, `AppSettings.swift`, `SystemSnapshot.swift`, `Sources/PAVCore/Planning/ProcessingRule.swift`, `TapPlanner.swift`
- Test: `Tests/PAVCoreTests/ProcessingRuleTests.swift`, `TapPlannerTests.swift`

**Interfaces:**
- Consumes: `DeviceSettings` (Task 2).
- Produces:
  - `public struct AppID: Hashable, Codable, Sendable { public let rawValue: String }`. Es el bundle ID o, si no hay, la ruta del ejecutable.
  - `public struct AppSettings: Codable, Sendable, Equatable { var volume: Float = 1; var muted = false; var outputDeviceUID: String? = nil; var displayName: String; var lastSeen: Date? }`
  - `public enum TransportKind: String, Sendable { case builtIn, usb, bluetooth, airPlay, aggregate, virtual, hdmi, displayPort, thunderbolt, other }`
  - `public struct OutputDevice: Sendable, Hashable { uid: String; name: String; transport: TransportKind; sampleRate: Double; channels: Int }`
  - `public struct AppGroup: Sendable, Hashable { id: AppID; displayName: String; processObjectIDs: Set<UInt32>; isPlaying: Bool; outputDeviceUIDs: [String] }`
  - `public struct SystemSnapshot: Sendable, Equatable { apps: [AppGroup]; devices: [OutputDevice]; defaultOutputUID: String? }`
  - `public enum TapKind: Hashable, Sendable { case app(AppID), rest(deviceUID: String) }`
  - `public struct TapSpec: Hashable, Sendable`, con:
    - `kind: TapKind; processObjectIDs: Set<UInt32>; exclusive: Bool; outputDeviceUID: String; outputSampleRate: Double`
    - `var structuralKey: StructuralKey { get }`, donde `public struct StructuralKey: Hashable, Sendable { kind; exclusive; outputDeviceUID; outputSampleRate }`. Si cambia, hay que recrear el tap.
  - `public enum ProcessingRule`, con:
    - `static func automaticOutputUID(for app: AppGroup, snapshot: SystemSnapshot) -> String?`: primer UID de `app.outputDeviceUIDs` presente en `snapshot.devices`; si no, `snapshot.defaultOutputUID`.
    - `static func effectiveOutputUID(for app: AppGroup, settings: AppSettings?, snapshot: SystemSnapshot) -> String?`: la salida asignada si existe en `snapshot.devices`; si no, `defaultOutputUID` cuando hay asignación ausente (§8.4); si no hay asignación, `automaticOutputUID`.
    - `static func needsProcessing(app: AppGroup, settings: AppSettings?, deviceSettings: [String: DeviceSettings], snapshot: SystemSnapshot) -> Bool`: es la regla de §8.2.
  - `public enum TapPlanner { static func plan(snapshot: SystemSnapshot, appSettings: [AppID: AppSettings], deviceSettings: [String: DeviceSettings], keepAlive: Set<AppID>) -> [TapSpec] }`
  - `public enum KeepAlive { static func next(current: Set<AppID>, snapshot: SystemSnapshot, plannedApps: Set<AppID>) -> Set<AppID> }`: añade las apps planificadas que suenan y quita las que ya no suenan (§8.2, transiciones).

**Reglas que el planner debe cumplir** (copiadas de §8.2–8.4):
- **Tap por app** si `needsProcessing || keepAlive.contains(id)`, y la app `isPlaying` o ya estaba en `keepAlive`. Usa `exclusive = false`, `processObjectIDs` = los de la app, y `outputDeviceUID` = `effectiveOutputUID`.
- **Tap "rest"** por cada dispositivo `D` con `deviceSettings[D].isActive`, solo si `D == defaultOutputUID` o alguna app que suena sin tap propio tiene `automaticOutputUID == D`.
  - Usa `exclusive = true`, y `processObjectIDs` = la unión de los procesos de todas las apps con tap propio (los excluidos).
- Las apps con tap propio cuya salida efectiva es `D` aplican la cadena de `D` en su propio tap. No hay doble procesado.

- [ ] **Step 1: Escribir los tests que fallan** (un `SystemSnapshot` de fixture con "Built-in", "USB-DAC" y "AirPods").
  - `untouchedAppAtDefaultsGetsNoTap`: Spotify suena, con settings `nil`, y `plan` devuelve `[]`. Es el anti-objetivo principal.
  - `volumeChangeCreatesAppTap`: volume 0.8 da un `TapSpec(kind: .app(spotify), exclusive: false, outputDeviceUID: "builtin")`.
  - `resetToDefaultsKeepsTapWhilePlaying`: volume 1.0 y `keepAlive = [spotify]` mientras suena dan el tap todavía presente. Cuando `isPlaying = false`, `KeepAlive.next` lo quita y el siguiente `plan` da `[]`.
  - `appKeepsItsOwnDeviceWhenOnlyVolumeChanges`: Zoom con `outputDeviceUIDs = ["usb-dac"]`, default `builtin`, y volume 0.5 dan `outputDeviceUID == "usb-dac"`.
  - `assignedDeviceMissingFallsBackToDefault`: asignado `"airpods"` ausente del snapshot da `"builtin"`, y `settings.outputDeviceUID` sigue siendo `"airpods"`. **(Review Focus 2)**
  - `assignedDeviceReturnsWhenReconnected`: el mismo caso con `"airpods"` presente da `"airpods"`. **(Review Focus 2)**
  - `deviceEQCreatesExclusiveRestTapExcludingTappedApps`: EQ activo en builtin (default) más Spotify a 0.8 dan dos specs. Una es `.app(spotify)` y la otra `.rest("builtin")`, con `exclusive == true` y `processObjectIDs == spotify.processObjectIDs`.
  - `noRestTapForInactiveNonDefaultDevice`.
  - `sampleRateChangeChangesStructuralKey`.
- [ ] **Step 2: `swift test --filter TapPlannerTests`.** Esperado: FAIL.
- [ ] **Step 3: Implementar** los tipos y funciones de Interfaces. Son funciones puras sin efectos.
- [ ] **Step 4: `swift test`.** Esperado: PASS.
- [ ] **Step 5: Commit** `feat: processing rule and tap planner`.

---

### Task 4: Agrupación de procesos en apps

**Files:**
- Create: `Sources/PAVCore/Grouping/AppGrouper.swift`
- Test: `Tests/PAVCoreTests/AppGrouperTests.swift`

**Interfaces:**
- Consumes: `AppID`, `AppGroup` (Task 3).
- Produces:
  - `public struct AudioProcessInfo: Sendable, Hashable { objectID: UInt32; pid: Int32; bundleID: String?; executablePath: String?; isRunningOutput: Bool; outputDeviceUIDs: [String] }`
  - `public protocol ProcessResolving: Sendable { func responsiblePID(for pid: Int32) -> Int32?; func bundleInfo(forExecutablePath path: String) -> (bundleID: String, name: String)? }`. Los tests usan un fake.
  - `public enum AppGrouper { static func group(_ processes: [AudioProcessInfo], ownPID: Int32, resolver: ProcessResolving) -> [AppGroup] }`

**Orden de resolución de la app de un proceso:**
1. Proceso responsable (si difiere del propio): su bundle.
2. El `.app` **más externo** que contiene `executablePath`.
3. `bundleID` del proceso.
4. `executablePath`.

Se excluyen el propio PID y los procesos sin `bundleID` ni ruta. `displayName` sale de `bundleInfo`. `isPlaying` es el OR de los procesos y `outputDeviceUIDs` la unión ordenada y sin duplicados.

- [ ] **Step 1: Escribir los tests que fallan.**
  - `chromeHelpersCollapseIntoChrome`: dos procesos en `/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/…` más el principal dan un solo `AppGroup` con id `com.google.Chrome` y 3 objectIDs. **(Review Focus 3)**
  - `xpcServiceGroupsUnderResponsibleApp`: `com.apple.WebKit.GPU` con `responsiblePID` = PID de Safari da el grupo `com.apple.Safari`.
  - `ownProcessIsExcluded`.
  - `isPlayingIsTrueIfAnyProcessPlays`.
- [ ] **Step 2: `swift test --filter AppGrouperTests`.** Esperado: FAIL.
- [ ] **Step 3: Implementar `AppGrouper.group`** y un `SystemProcessResolver: ProcessResolving` real, que no se testea:
  - `responsiblePID`: resolver con `dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid")`. Si el símbolo no existe, devolver `nil`.
  - `bundleInfo`: usar `Bundle(url:)`.
- [ ] **Step 4: `swift test`.** Esperado: PASS.
- [ ] **Step 5: Commit** `feat: group audio processes into apps`.

---

### Task 5: Persistencia de ajustes

**Files:**
- Create: `Sources/PAVCore/Persistence/SettingsStore.swift`
- Test: `Tests/PAVCoreTests/SettingsStoreTests.swift` (usa un directorio temporal)

**Interfaces:**
- Consumes: `AppSettings`, `DeviceSettings`, `AppID`.
- Produces:
  - `public struct SettingsFile: Codable, Equatable { var version = 1; var apps: [String: AppSettings] = [:]; var devices: [String: DeviceSettings] = [:]; var launchAtLogin = false }`
  - `public final class SettingsStore`, con:
    - `init(directory: URL)`
    - `private(set) var file: SettingsFile`
    - `private(set) var isReadOnly: Bool`
    - `func load() -> LoadOutcome`, con `enum LoadOutcome { case fresh, loaded, recoveredFromCorrupt(backup: URL), newerVersion(Int) }`
    - `func mutate(_ change: (inout SettingsFile) -> Void)`
    - `func flush() throws`
  - `mutate` programa una escritura atómica con debounce de **500 ms** (`Data.write(options: .atomic)`). `flush` escribe ya.

- [ ] **Step 1: Escribir los tests que fallan.**
  - `missingFileLoadsDefaults` da `.fresh`.
  - `roundTripPreservesSettings`.
  - `corruptFileIsBackedUpAndDefaultsUsed`: escribir `"{nope"`. El resultado es `.recoveredFromCorrupt` y existe `settings.corrupt-*.json`. **(Review Focus 4)**
  - `emptyFileTreatedAsCorrupt`. **(Review Focus 4)**
  - `newerVersionIsNotOverwritten`: `{"version": 99}` da `.newerVersion(99)` e `isReadOnly`. Tras `mutate` + `flush`, el fichero en disco no cambia. **(Review Focus 4)**
  - `moreThanTenBandsAreTruncated`.
- [ ] **Step 2: `swift test --filter SettingsStoreTests`.** Esperado: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: `swift test`.** Esperado: PASS.
- [ ] **Step 5: Commit** `feat: versioned settings store with corrupt-file recovery`.

---

### Task 6: AutoEQ — parser, catálogo y datos empaquetados

**Files:**
- Create: `Sources/PAVCore/AutoEQ/ParametricEQParser.swift`, `AutoEQCatalog.swift`, `Sources/autoeq-index/main.swift`, `scripts/generate-autoeq.sh`
- Create (generado): `Sources/PerAppVolume/Resources/autoeq.json`, `THIRD_PARTY_NOTICES.md`
- Test: `Tests/PAVCoreTests/ParametricEQParserTests.swift`, `AutoEQCatalogTests.swift`

**Interfaces:**
- Consumes: `EQBand`, `FilterType`, `DeviceSettings`.
- Produces:
  - `public enum ParametricEQParser { static func parse(_ text: String) throws -> (preampDB: Float, bands: [EQBand]) }`
    - Formato de AutoEQ: `Preamp: -6.2 dB` y `Filter N: ON PK|LSC|HSC Fc <hz> Hz Gain <db> dB Q <q>`.
    - Ignora filtros `OFF` y como mucho admite 10 bandas.
  - `public struct AutoEQEntry: Codable, Sendable, Hashable { name: String; source: String; form: String; preampDB: Float; bands: [EQBand] }`
  - `public struct AutoEQCatalog { init(entries: [AutoEQEntry]); static func loadBundled(from url: URL) throws -> AutoEQCatalog; func search(_ query: String, limit: Int = 20) -> [AutoEQEntry] }`
    - La búsqueda no distingue mayúsculas ni acentos, por tokens. Los resultados con prefijo exacto van primero.
  - CLI `autoeq-index <ruta/AutoEq/results> <salida.json>`:
    - Recorre los `*ParametricEQ.txt` y deduce `source` y `form` de la ruta (`results/<source>/<form>/<name>/`).
    - Deduplica por `name` con prioridad de fuente `oratory1990 > crinacle > rtings > innerfidelity > resto`.

- [ ] **Step 1: Escribir los tests que fallan.**
  - `parsesPreampAndFilters`: fixture con 1 LSC, 8 PK y 1 HSC dan `preamp -6.2` y 10 bandas con los valores exactos de la fixture.
  - `ignoresOffFilters`.
  - `rejectsGarbage`, que lanza un error.
  - `searchFindsHeadphoneCaseInsensitive`: `"hd 650"` encuentra "Sennheiser HD 650".
  - `searchPrefersPrefixMatch`.
- [ ] **Step 2: `swift test --filter ParametricEQParserTests`.** Esperado: FAIL.
- [ ] **Step 3: Implementar el parser, el catálogo y la CLI.**
- [ ] **Step 4: Comprobar la licencia (bloqueante para el empaquetado).**
  - Clonar `https://github.com/jaakkopasanen/AutoEq` con un commit fijado en `scripts/generate-autoeq.sh` y leer su `LICENSE`.
  - Comprobar que `results/` no tiene términos propios.
  - **Si se puede empaquetar:** ejecutar `scripts/generate-autoeq.sh` (clona en `build/`, ejecuta `swift run autoeq-index … Sources/PerAppVolume/Resources/autoeq.json`) y escribir `THIRD_PARTY_NOTICES.md` con la licencia y la URL.
  - **Si no se puede:** aplicar el plan B de §8.6. Sin `autoeq.json`, y la Task 11 implementa "Importar ParametricEQ.txt…" en lugar del buscador. Anotar la decisión en `THIRD_PARTY_NOTICES.md`.
- [ ] **Step 5: `swift test`.** Esperado: PASS. Si se generó, `autoeq.json` debe pesar menos de 10 MB (`ls -lh`).
- [ ] **Step 6: Commit** `feat: AutoEQ parser, catalog and bundled index`.

---

### Task 7: Core Audio — lectura del sistema (dispositivos, procesos, listeners)

**Files:**
- Create: `Sources/PAVAudio/AudioObject+Properties.swift`, `AudioSystemMonitor.swift`, `DeviceFilter.swift`, `Sources/pav-diag/main.swift`
- Test: `Tests/PAVAudioTests/DeviceFilterTests.swift`

**Interfaces:**
- Consumes: `AudioProcessInfo`, `AppGrouper`, `SystemProcessResolver` (Task 4), `OutputDevice`, `TransportKind`, `SystemSnapshot` (Task 3).
- Produces:
  - Helpers genéricos `AudioObjectID.read<T>(_ selector:, scope:, element:) throws -> T`, `readArray<T>`, `readString` y `readCFString`, que lanzan `AudioError(status: OSStatus, context: String)`.
  - `public final class AudioSystemMonitor: @unchecked Sendable`, con:
    - `init(queue: DispatchQueue)`
    - `func start(onChange: @escaping @Sendable (SystemSnapshot) -> Void)`
    - `func stop()`
    - `func currentSnapshot() throws -> SystemSnapshot`
  - `public enum DeviceFilter { static func isSelectableAsAppOutput(_ d: OutputDevice) -> Bool }`

**Propiedades que hay que leer:**
- Procesos: `kAudioHardwarePropertyProcessObjectList`. De cada proceso, `kAudioProcessPropertyPID`, `…BundleID`, `…IsRunningOutput` y `…Devices` en scope output (los UIDs vía `kAudioDevicePropertyDeviceUID`).
- Dispositivos: `kAudioHardwarePropertyDevices`, quedándose con los que tienen streams de salida (`kAudioDevicePropertyStreamConfiguration`, output). De cada uno, `kAudioDevicePropertyDeviceUID`, `kAudioObjectPropertyName`, `kAudioDevicePropertyTransportType` (mapear a `TransportKind`) y `kAudioDevicePropertyNominalSampleRate`.
- Default: `kAudioHardwarePropertyDefaultOutputDevice`.

**Listeners** (con `AudioObjectAddPropertyListenerBlock` en `queue`):
- En el sistema: lista de procesos, lista de dispositivos y salida por defecto.
- En cada proceso: `IsRunningOutput` y `Devices`.
- En cada dispositivo: `NominalSampleRate`.
- Los cambios se agrupan con un debounce de **100 ms** y emiten un `SystemSnapshot`.
- El snapshot excluye de `devices` los aggregates propios (UID con prefijo `io.github.perappvolume.`).

- [ ] **Step 1: Escribir el test que falla.** `DeviceFilterTests`:
  - `airPlayIsNotSelectable`, `aggregateIsNotSelectable`, `ownAggregateIsNotSelectable` (UID con prefijo).
  - `usbAndBluetoothAndBuiltInAreSelectable`.
- [ ] **Step 2: `swift test --filter DeviceFilterTests`.** Esperado: FAIL.
- [ ] **Step 3: Implementar** los helpers, `AudioSystemMonitor` y `DeviceFilter`.
  - Implementar `pav-diag list`: imprime dispositivos (`uid`, `name`, `transport`, `rate`), salida por defecto y apps agrupadas (`id`, `name`, `playing`, `pids`, `devices`).
  - Implementar `pav-diag watch`: imprime un snapshot en cada cambio.
- [ ] **Step 4: `swift test`.** Esperado: PASS.
- [ ] **Step 5: Verificación manual.**
  - Reproducir algo en Spotify o Music y ejecutar `swift run pav-diag list`. Esperado: la app aparece con `playing=true` y con la salida correcta.
  - Abrir un vídeo en Chrome. Esperado: una sola fila `com.google.Chrome`.
  - Con `swift run pav-diag watch`, conectar o desconectar auriculares. Esperado: llega un snapshot nuevo en menos de 1 s.
- [ ] **Step 6: Commit** `feat: Core Audio system monitor and pav-diag list/watch`.

---

### Task 8: Core Audio — backend de taps, aggregates y E/S

**Files:**
- Create: `Sources/PAVAudio/AudioBackend.swift`, `AggregateDescription.swift`, `CoreAudioBackend.swift`
- Modify: `Sources/pav-diag/main.swift`, para añadir el subcomando `tap`.
- Test: `Tests/PAVAudioTests/AggregateDescriptionTests.swift`

**Interfaces:**
- Consumes: `ProcessingChain`, `ChainParameters` (Task 2), `TapSpec` (Task 3), `AudioError` (Task 7).
- Produces:
  - `public struct TapHandle: Hashable, Sendable { tapID: UInt32; uid: String }`
  - `public struct AggregateHandle: Hashable, Sendable { deviceID: UInt32; uid: String }`. El `AudioDeviceIOProcID` y el contexto del callback se guardan dentro de `CoreAudioBackend`, en un diccionario por `deviceID`.
  - Protocolo, usado por la Task 9 y con una implementación falsa en sus tests:

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

  - `public enum AggregateDescription { static func make(uid: String, outputDeviceUID: String, tapUID: String) -> [String: Any] }`. Es una función pura y se testea.

**Detalles de implementación** (valores de §8.3):
- `createTap`:
  - Construir el `CATapDescription`:
    - **Tap de app** (`exclusive == false`, `deviceUID == nil`): `CATapDescription(stereoMixdownOfProcesses:)`.
    - **Tap `rest`** (`exclusive == true`, `deviceUID = D`): `CATapDescription(excludingProcesses:andDeviceUID: D, withStream: 0)`.
    - El tap `rest` va **atado al dispositivo D**. Un tap global excluyente capturaría y silenciaría también apps que suenan por otros dispositivos sin EQ, y las mandaría a D.
  - Configurar `isPrivate = true`, `muteBehavior = .mutedWhenTapped`, `name = "PerAppVolume"` y `uuid` derivado de `uid`.
  - Llamar a `AudioHardwareCreateProcessTap`.
- `updateTap`: `AudioObjectSetPropertyData(tapID, kAudioTapPropertyDescription, …)` con la descripción modificada. **No recrea.**
- Diccionario de `createAggregate`:
  - `kAudioAggregateDeviceUIDKey: uid`, `NameKey: "PerAppVolume"`, `IsPrivateKey: 1` y `MainSubDeviceKey: outputDeviceUID`.
  - `SubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID, kAudioSubDeviceDriftCompensationKey: 1]]`.
  - `TapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: 1]]` y `TapAutoStartKey: 1`.
  - Después, fijar `kAudioDevicePropertyBufferFrameSize = 256` en el aggregate.
- `startIO`:
  - `AudioDeviceCreateIOProcID` con una función C (no un bloque) cuyo `inClientData` es un puntero no retenido a un contexto preasignado (la cadena y los punteros de buffer).
  - El callback toma el buffer de entrada del tap y llama a `chain.process` hacia el buffer de salida del dispositivo. Si el formato no es Float32 interleaved estéreo, convierte o bien se rechaza en `startIO` lanzando `AudioError`.
- `destroyStaleObjects`: destruir los taps de `kAudioHardwarePropertyTapList` y los aggregates cuyo UID empiece por el prefijo.

- [ ] **Step 1: Escribir el test que falla.** `aggregateDescriptionHasPrivateDriftAndTap`: comprobar todas las claves y valores de la lista de arriba sobre `AggregateDescription.make(...)`.
- [ ] **Step 2: `swift test --filter AggregateDescriptionTests`.** Esperado: FAIL.
- [ ] **Step 3: Implementar `CoreAudioBackend`** e implementar `pav-diag tap --app <bundleID> --volume <0…2> [--output <uid>]`, que crea tap + aggregate + E/S para esa app hasta Ctrl-C.
- [ ] **Step 4: `swift test`.** Esperado: PASS.
- [ ] **Step 5: Verificación manual.** El primer uso pide permiso de audio a Terminal: concederlo.
  - Con Spotify sonando, `swift run pav-diag tap --app com.spotify.client --volume 0.3`. Esperado: el volumen baja de forma clara, sin cortes.
  - Con `--volume 2.0`, sube y no hay distorsión dura.
  - Con `--output <uid de otro dispositivo>`, suena por el otro dispositivo.
  - `kill -9` del proceso `pav-diag`: Spotify vuelve a sonar normal al instante.
- [ ] **Step 6: Commit** `feat: Core Audio tap/aggregate backend and pav-diag tap`.

---

### Task 9: TapEngine — reconciliación, fallos y limpieza

**Files:**
- Create: `Sources/PAVAudio/TapEngine.swift`
- Test: `Tests/PAVAudioTests/TapEngineTests.swift`, con un `FakeAudioBackend` que registra las llamadas y puede fallar a demanda.

**Interfaces:**
- Consumes: `AudioBackend`, `TapHandle`, `AggregateHandle` (Task 8), `TapSpec`, `TapKind` (Task 3), `ProcessingChain`, `ChainParameters` (Task 2).
- Produces:
  - `public enum TapStatus: Sendable, Equatable { case active, failed(String) }`
  - `public final class TapEngine`, con:
    - `init(backend: AudioBackend, uidPrefix: String = "io.github.perappvolume.")`
    - `func reconcile(desired: [TapSpec], parameters: (TapKind) -> ChainParameters)`
    - `func updateParameters(for kind: TapKind, _ p: ChainParameters)`
    - `func status(for kind: TapKind) -> TapStatus?`
    - `func shutdown()`
    - `func cleanupStale()`, que llama a `backend.destroyStaleObjects(uidPrefix:)`. La app lo invoca al arrancar.

**Algoritmo de `reconcile`** (§8.3), comparando las sesiones vivas por `TapKind`:
- Sesión que no está en `desired`: `stopIO`, `destroyAggregate`, `destroyTap`.
- Distinto `structuralKey`: destruir y crear.
- Mismo `structuralKey` pero distintos `processObjectIDs`: `updateTap`.
- Nueva: `createTap`, `createAggregate`, `startIO`. En `createTap` se pasa `deviceUID: nil` para `.app` y `deviceUID: D` para `.rest(D)`.
- **Fallo en cualquier paso posterior a `createTap`:** deshacer lo creado, **`destroyTap` primero** (desmutea la app), y marcar `failed(mensaje)`.
  - Un `TapKind` en `failed` no se reintenta hasta que su `TapSpec` cambie.

Todos los métodos se llaman desde una cola serie propiedad del llamador (la app usa la `queue` del monitor).

- [ ] **Step 1: Escribir los tests que fallan.**
  - `createsTapAggregateAndStartsIOForNewSpec`, que comprueba el orden de las llamadas.
  - `removesSessionNoLongerDesired`.
  - `processSetChangeUpdatesInsteadOfRecreating`: las llamadas son exactamente `[.updateTap]`, sin `destroyTap` ni `createTap`. **(Review Focus 3)**
  - `deviceChangeRecreates`.
  - `aggregateFailureDestroysTapImmediatelyAndMarksFailed`: el fake falla en `createAggregate`. Las llamadas son `[.createTap, .destroyTap]`, el estado es `.failed` y no hay sesión viva. **(Review Focus 1)**
  - `startIOFailureUnwindsEverything`. **(Review Focus 1)**
  - `failedSpecIsNotRetriedUntilItChanges`: el mismo `desired` otra vez no produce llamadas nuevas; un `desired` con otra salida sí reintenta. **(Review Focus 1)**
  - `parameterUpdateDoesNotTouchBackend`: `updateParameters` no produce llamadas al backend.
- [ ] **Step 2: `swift test --filter TapEngineTests`.** Esperado: FAIL.
- [ ] **Step 3: Implementar `TapEngine`.** Cada sesión tiene su propio `ProcessingChain`, creado con los canales y la frecuencia del dispositivo de salida y `maxFrames: 4096`.
- [ ] **Step 4: `swift test`.** Esperado: PASS.
- [ ] **Step 5: Commit** `feat: tap engine with reconcile, failure unwinding and stale cleanup`.

---

### Task 10: La app — estado, barra de menú y empaquetado

**Files:**
- Create: `Sources/PerAppVolume/PerAppVolumeApp.swift`, `AppState.swift`, `Views/MenuBarView.swift`, `Views/AppRowView.swift`, `Views/DeviceSectionView.swift`
- Create: `App/Info.plist`, `App/PerAppVolume.entitlements` (vacío, sin sandbox), `scripts/build-app.sh`
- Test: `Tests/PAVCoreTests/` no aplica. Esta task se verifica con el build y con la checklist manual.

**Interfaces:**
- Consumes: todo lo anterior.
- Produces:
  - `@MainActor @Observable final class AppState`, con:
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

**Flujo en `AppState`:**
1. Al arrancar: `SettingsStore.load()`, `TapEngine.cleanupStale()` y `monitor.start`.
2. En cada snapshot o cambio de ajustes, en la cola del motor:
   1. `KeepAlive.next`
   2. `TapPlanner.plan`
   3. `engine.reconcile`
   4. Publicar las filas en el main actor.
3. Mover un slider llama a `engine.updateParameters` (no hace `reconcile`), salvo que cambie `needsProcessing`.
4. Se guarda `lastSeen` y `displayName` de cada app que suena.

**Onboarding del permiso:** antes de crear el **primer** tap, si `permissionExplained == false`, se muestra en el popover un aviso. Explica por qué se necesita el permiso de "Grabación de audio del sistema" y tiene dos botones: "Continuar" (marca el flag y aplica) y "Ahora no".

**UI** (boceto de §8.5):
- Filas de apps que suenan arriba. Las apps que sonaron en esta sesión aparecen debajo, atenuadas (`opacity 0.5`).
- Cada fila tiene:
  - icono y nombre
  - `Slider` 0…200 con su etiqueta `"%d%%"`; doble clic lo devuelve a 100
  - botón mute
  - menú de salida: "Automática (la que use la app)" más los `selectableDevices`
  - icono ⚠️ con tooltip cuando su estado es `.failed`
- Sección del dispositivo por defecto: toggle de EQ (muestra `autoEQName` si lo hay), indicador de balance y toggle de mono.
- Pie: "Ajustes…" y "Salir".

**`scripts/build-app.sh`:**
1. `swift build -c release --arch arm64 --arch x86_64 --product PerAppVolume`.
2. Ensamblar `build/PerAppVolume.app/Contents/{MacOS,Resources}` con `App/Info.plist`, copiar el bundle de recursos de SwiftPM y firmar ad hoc: `codesign --force --options runtime --entitlements App/PerAppVolume.entitlements -s - build/PerAppVolume.app`.

`Info.plist`:
- `CFBundleIdentifier = io.github.perappvolume`
- `LSUIElement`, `LSMinimumSystemVersion` y `NSAudioCaptureUsageDescription` (textos de Global Constraints)

- [ ] **Step 1: Implementar `AppState`** con monitor, planner, motor y store reales, inyectados por `init` para poder sustituirlos más adelante.
- [ ] **Step 2: Implementar las vistas y `PerAppVolumeApp`.** `MenuBarExtra(.window)` con icono `speaker.wave.2` y una escena `Settings` (placeholder hasta la Task 11).
- [ ] **Step 3: Implementar `scripts/build-app.sh`, `Info.plist` y los entitlements.**
- [ ] **Step 4: `scripts/build-app.sh && open build/PerAppVolume.app`.** Esperado:
  - aparece el icono en la barra de menú y no en el Dock
  - con Spotify sonando, sale su fila al 100 %
  - `swift run pav-diag list` no muestra aggregates propios mientras no se toque nada (anti-objetivo principal, §9)
- [ ] **Step 5: Verificación manual.**
  - Bajar Spotify al 40 %: sale el aviso de permiso, luego la petición de macOS y después baja el volumen.
  - Volver al 100 % con doble clic: no hay corte.
  - Salir y reabrir la app: con Spotify sonando, vuelve al 40 %.
  - Mandar Spotify a otro dispositivo: suena por ese dispositivo.
- [ ] **Step 6: Commit** `feat: menu bar app, state wiring and app bundle script`.

---

### Task 11: Ventana de ajustes

**Files:**
- Create: `Sources/PerAppVolume/Views/Settings/SettingsView.swift`, `DeviceSettingsView.swift`, `AppsSettingsView.swift`, `GeneralSettingsView.swift`
- Modify: `Sources/PerAppVolume/PerAppVolumeApp.swift`, para que la escena `Settings` use `SettingsView`.

**Interfaces:**
- Consumes: `AppState` (Task 10), `AutoEQCatalog` / `ParametricEQParser` (Task 6), `DeviceSettings`.
- Produces: vistas SwiftUI, que nada consume.

**Contenido:**
- **Dispositivos**:
  - selector de dispositivo de salida (`selectableDevices` + el default)
  - toggle EQ, slider de preamp de −20 a +6 dB y editor de hasta 10 bandas (tipo, Hz 20–20000, dB −20…+20, Q 0.1–10, activa)
  - buscador AutoEQ: aplica `preampDB`, `bands` y `autoEQName`. Si en la Task 6 se aplicó el plan B, en su lugar va el botón "Importar ParametricEQ.txt…" con `NSOpenPanel` + `ParametricEQParser`
  - slider de balance −1…1 con doble clic a 0, y toggle de mono
- **Apps**: lista de apps recordadas (nombre, volumen guardado, salida guardada, `lastSeen`) con el botón "Olvidar".
- **General**:
  - toggle "Abrir al iniciar sesión", con `SMAppService.mainApp.register()` / `unregister()` y su estado reflejado en `launchAtLogin`
  - texto explicativo del permiso
  - botón "Abrir ajustes de privacidad" que abre `x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`

- [ ] **Step 1: Implementar las vistas.**
- [ ] **Step 2: `scripts/build-app.sh && open build/PerAppVolume.app`.** Verificación manual:
  - Buscar "HD 650" (o importar un fichero) y activar el EQ: el sonido cambia en todas las apps de ese dispositivo.
  - Desactivar el EQ: el sonido vuelve.
  - Balance totalmente a la izquierda: solo suena el canal izquierdo.
  - Mono funciona.
  - "Olvidar" quita la app de la lista.
  - El login item aparece en Ajustes del Sistema → General → Ítems de inicio.
- [ ] **Step 3: Commit** `feat: settings window with device EQ, AutoEQ, apps and general tabs`.

---

### Task 12: README, CI y checklist de pruebas manuales

**Files:**
- Create: `README.md`, `.github/workflows/ci.yml`, `docs/manual-test-checklist.md`

**Contenido:**
- `README.md`:
  - qué es
  - requisitos (macOS 14.4+)
  - cómo compilar (`scripts/build-app.sh`)
  - permiso de audio
  - abrir una app sin notarizar (clic derecho → Abrir)
  - limitaciones conocidas: sin AirPlay como salida por app, mixdown estéreo, un solo dispositivo cuando una app usa varios
  - créditos de AutoEQ
  - licencia pendiente de decidir, §11 del spec
- `ci.yml`: en `macos-15`, `swift build` + `swift test` en cada push y PR.
- `docs/manual-test-checklist.md`:
  - la lista de §9 con casillas
  - apps: Spotify, Music, Chrome, Safari, Zoom/Meet, un juego, Slack/Discord
  - Bluetooth y USB; cambio de salida por defecto; `kill -9`
  - "sin tocar nada no hay aggregates propios" (verificado con `pav-diag list`)
  - cambio de frecuencia de muestreo en Configuración de Audio MIDI con EQ activo
  - salida por defecto AirPlay: las apps sin tocar suenan normal

- [ ] **Step 1: Escribir los tres ficheros.**
- [ ] **Step 2: `swift build && swift test`.** Esperado: PASS. Validar el YAML: `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml")'`.
- [ ] **Step 3: Commit** `docs: README, CI workflow and manual test checklist`.
