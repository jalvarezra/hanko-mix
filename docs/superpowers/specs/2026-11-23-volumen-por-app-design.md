# Volumen por app para macOS — Diseño (v1)

*Fecha: 2026-11-23 · Estado: borrador para aprobación*
*Nombre del proyecto: por decidir (en el código se usa provisionalmente `PerAppVolume`).*

## 1. Intención y porqué

Una alternativa **gratuita y opensource** a las apps comerciales de volumen por app para macOS: una app de barra de menú que controla el audio de cada aplicación por separado. "Mejorada" significa, en esta versión, abierta, sin licencia de pago ni limitaciones artificiales, y fiable.

La función que el usuario más usa es **regular el volumen por app**. Esa es la pieza que tiene que funcionar perfecta. El resto de funciones de la v1 se construye alrededor.

## 3. Objetivos (v1)

1. **Volumen y mute por app** *(lo central)*.
   - Un slider por cada app que está sonando o ha sonado en esta sesión, de 0 % a 200 %.
   - Por encima del 100 % se aplica un limitador suave para evitar saturación digital.
   - Botón de mute por app.
2. **Salida por app**: enviar una app a un dispositivo de salida distinto del predeterminado.
3. **EQ por dispositivo de salida**.
   - EQ paramétrico por dispositivo, con buscador de presets AutoEQ por modelo de auriculares.
   - Se puede activar y desactivar.
4. **Balance y mono** por dispositivo de salida.
5. **Recordar ajustes por app**.
   - Volumen, mute y salida se guardan por *bundle ID* y se aplican solos cuando la app vuelve a sonar.
   - Los ajustes de EQ, balance y mono se guardan por *UID* de dispositivo.
6. **Opensource** desde el primer commit: repo público, instrucciones de compilación y licencia.

## 4. No-objetivos (para después de la v1)

- EQ por app.
- Atajos de teclado globales y control por MIDI.
- Control de Apple Music, AppleScript o URL scheme.
- Procesar el micrófono o la entrada de audio.
- Grabación, efectos o plugins AU de terceros.
- Soporte de macOS anterior a 14.4.
- **AirPlay y dispositivos multisalida como salida por app** (decisión del usuario). No aparecen en el menú de salida por app.
  - Motivo: como dispositivo principal de un aggregate añaden unos 2 s de latencia y su reloj no es fiable.
  - Si la salida por defecto del sistema es AirPlay, las apps sin tocar suenan normal, porque no se interceptan. Las que tienen ajustes propios siguen funcionando en modo "mejor esfuerzo", y se avisa de que puede haber retraso.
- Distribución por Mac App Store.

## 5. Anti-objetivos (fallaría aunque "funcione")

- **Alterar el audio en reposo.** Si el usuario no ha tocado nada, el sonido debe ser bit-idéntico y sin latencia añadida. Una app con volumen al 100 %, sin mute, en su salida por defecto y sin EQ, balance ni mono activos en ese dispositivo **no se intercepta**.
- **Dejar al usuario sin sonido.**
  - Si la app se cierra o se cuelga, todo debe volver a sonar normal. Los taps y aggregates privados mueren con el proceso.
  - Si falla la creación de un tap o un aggregate, esa app sigue sonando sin procesar y se muestra un aviso discreto. Nunca queda en silencio.
- **Cortes, clics o desincronización** audibles al mover un slider, al conectar o desconectar auriculares o al cambiar la salida por defecto.
- **Instalar drivers, kexts o pedir contraseña de administrador.**
- **Copiar código o recursos de otras apps.**

## 6. Restricciones

- macOS **14.4 o superior**. `CATapDescription` existe desde 14.2, pero el permiso de captura de audio (`NSAudioCaptureUsageDescription`) se asienta en 14.4. *Decisión mía*: subir el mínimo a 14.4 evita una ruta de permisos aparte. Si las pruebas lo exigen, el builder puede subirlo a 14.6. Hay que probar en 14.x, 15.x y 26.x.
- Apple Silicon y también Intel (binario universal). No hay dependencias que lo impidan.
- **Permiso de captura de audio del sistema**: requiere `NSAudioCaptureUsageDescription`. La primera vez que se crea un tap, macOS pide permiso al usuario. La app debe explicar antes por qué lo necesita y manejar el caso de permiso denegado.
- **Sandbox**: Una app con process taps puede funcionar en sandbox con `com.apple.security.device.audio-input`. La v1 puede ir con o sin sandbox; *decisión del builder*, preferiblemente con sandbox si no da problemas.
- **Firma y notarización**: sin una cuenta de Apple Developer, la app abre con aviso de Gatekeeper. *Decisión pendiente del usuario* (ver §11); no cambia el código.

## 7. Enfoques considerados

| Enfoque | Qué supone | Veredicto |
|---|---|---|
| **A. App nativa Swift, un solo proceso** | SwiftUI `MenuBarExtra`. La misma app crea los taps y aggregates y procesa el audio en el callback de Core Audio. | **Elegido por el usuario.** Es lo más simple y no puede dejarte sin sonido: al morir el proceso, macOS destruye los taps privados. |
| B. App + agente en segundo plano (XPC) | La interfaz y el motor de audio van en procesos separados. | Descartado para la v1: el doble de piezas para una ventaja (reiniciar la UI sin cortar el audio) que todavía no hace falta. Se puede separar más adelante. |
| C. Driver HAL virtual | Como Background Music o eqMac. | Descartado: exige instalar un driver con privilegios de administrador, suele romperse con las actualizaciones de macOS y choca con los anti-objetivos. |

## 8. Diseño (lo decidido)

### 8.1 Piezas

- **`AudioSystem`**: observa Core Audio.
  - Dispositivos de salida, salida por defecto y lista de procesos de audio (`kAudioHardwarePropertyProcessObjectList`).
  - De cada proceso lee PID, *bundle ID* y si está reproduciendo (`kAudioProcessPropertyIsRunningOutput`).
  - Publica cambios mediante listeners, nunca por sondeo.
- **`AppGrouper`**: agrupa procesos en "apps" tal como las ve el usuario.
  - Los procesos auxiliares (por ejemplo "Google Chrome Helper (Renderer)", WebKit/Safari, Electron) se asignan a su app principal mediante el proceso responsable o la jerarquía de bundles.
  - La UI muestra una fila por app, no por proceso.
- **`TapEngine`**: crea y destruye taps y aggregate devices privados, y gestiona los callbacks de audio.
- **`DSP`**: cadena de procesado en tiempo real.
  - Ganancia con rampa (sin clics), limitador suave para más del 100 %, EQ paramétrico con biquads (vDSP) y matriz de balance/mono.
  - El código del callback no reserva memoria ni toma locks. Los parámetros se pasan con estructuras atómicas o *lock-free*.
- **`SettingsStore`**: persistencia.
  - JSON en `~/Library/Application Support/<app>/`.
  - Por *bundle ID*: volumen, mute y UID de salida. Por UID de dispositivo: EQ, balance y mono.
- **`AutoEQCatalog`**: índice de presets paramétricos de AutoEQ, buscable por modelo.
- **UI**: `MenuBarExtra` en SwiftUI más una ventana de ajustes.

### 8.2 Cuándo se intercepta una app (regla central)

Una app **necesita procesado** si cumple cualquiera de estas condiciones:

- volumen ≠ 100 %
- está en mute
- tiene una salida asignada distinta de la salida por defecto
- su dispositivo de salida efectivo tiene EQ, balance o mono activos

Si no necesita procesado, no se crea ningún tap para ella.

**Transiciones sin cortes** *(decisión mía)*.
- Un tap se **crea** la primera vez que una app necesita procesado. Ese único momento puede producir un corte breve.
- El tap **no se destruye** al volver a los valores por defecto. Se mantiene vivo, en modo transparente (ganancia 1.0, sin DSP), hasta que la app deja de sonar. Solo entonces se libera.
- Así, mover un slider de 100 % → 99 % → 100 % nunca recrea nada.
- El test de "no ensuciar" (§9) se define así: *una app que no se ha tocado desde que empezó a sonar no tiene tap*.

**Procesos auxiliares que aparecen y desaparecen** (Chrome, Electron).
- No se recrea el tap. Se actualiza su lista de procesos en caliente escribiendo `kAudioTapPropertyDescription`.
- El aggregate device no cambia.

**Dispositivo de salida efectivo de una app** *(decisión mía)*.
- Si el usuario no ha asignado salida, el tap sale por el **dispositivo que la app está usando realmente**, leído de las propiedades del proceso en Core Audio. Si una app como Zoom eligió unos auriculares USB en sus propios ajustes, cambiarle el volumen no la desvía a la salida por defecto.
- En el menú de salida por app, la opción por defecto se llama "Automática (la que use la app)".
- Si un proceso usa varios dispositivos a la vez, se toma el primero y se registra el caso como limitación conocida.

### 8.3 Topología de taps

**Apps con ajustes propios** (volumen, mute o salida): un tap por app.
- `CATapDescription` con los objetos de proceso de esa app, privado y con `muteBehavior = mutedWhenTapped`.
- Ese tap va en un aggregate device privado cuyo *main/clock device* es el dispositivo de salida efectivo de la app, con drift compensation activada.
- El IOProc del aggregate lee el audio del tap, aplica ganancia y luego la cadena del dispositivo (EQ, balance, mono), y escribe en la salida.

**Dispositivos con EQ, balance o mono activos**: además, un tap de "resto" por dispositivo.
- Tap exclusivo (`exclusive = true`) que captura *todas las apps excepto* las que ya tienen tap propio. Solo se crea si ese dispositivo es la salida por defecto, o si alguna app va a él.
- Pasa por la cadena del dispositivo y sale por él.

**Reconstrucción**: los taps y aggregates se recrean solo cuando cambia su composición (procesos o dispositivo). Mover un slider solo cambia parámetros del DSP y nunca recrea nada.

**Limpieza al arrancar**: se eliminan aggregates y taps con el prefijo de UID de la app que hayan quedado de una ejecución anterior (por ejemplo, tras un crash).

### 8.4 Eventos del sistema

- **Una app empieza o deja de sonar**: aparece o desaparece de la lista, y se aplican sus ajustes guardados.
- **Una app se cierra**: se destruye su tap y se conservan sus ajustes.
- **Cambia la salida por defecto**: se recrean los aggregates afectados hacia el nuevo dispositivo.
- **Se desconecta un dispositivo asignado** (por ejemplo, auriculares Bluetooth): las apps asignadas pasan temporalmente a la salida por defecto. Cuando el dispositivo vuelve, regresan a él. La asignación guardada no se pierde.
- **Cambia la frecuencia de muestreo del dispositivo**: se recrea el aggregate y los coeficientes del EQ se recalculan.

### 8.4b Latencia *(decisión mía)*

- **Objetivo**: como máximo ~20 ms de latencia añadida en salidas integradas, USB o con cable mientras una app está procesada. Con eso, vídeo y videollamadas no se desincronizan de forma apreciable.
- Usar buffers de E/S pequeños y una cadena DSP ligera dentro del callback.
- En Bluetooth la latencia ya es grande por el propio dispositivo. El objetivo es no sumar más de esos ~20 ms.
- Si una implementación con AudioUnits no cumple el objetivo, se usan biquads propios con vDSP.

### 8.5 Interfaz (boceto)

```
┌─────────────────────────────────────┐
│ 🔊 Salida: AirPods Pro         ▾    │
│ ─────────────────────────────────── │
│ [Spotify]   ━━━━━━━━●━━━  80%  🔇 ▾ │
│ [Chrome]    ━━━━━━━━━━━●  100% 🔇 ▾ │
│ [Zoom]      ━━━━━━━━━━━━━●140% 🔇 ▾ │  ▾ = elegir salida de esa app
│ ─────────────────────────────────── │
│ AirPods Pro: EQ AutoEQ ✓  Bal ◦  Mono ☐ │
│ Ajustes…                     Salir  │
└─────────────────────────────────────┘
```

- La lista muestra las apps que están sonando arriba y, atenuadas, las que sonaron hace poco.
- Doble clic en un slider lo devuelve al 100 %.
- **Ventana de ajustes**:
  - pestaña por dispositivo: EQ paramétrico con buscador AutoEQ, balance y mono
  - lista de apps recordadas, con opción de olvidarlas
  - arrancar al iniciar sesión, con `SMAppService`
  - explicación del permiso de audio

### 8.6 AutoEQ

- Los presets paramétricos se generan **en tiempo de compilación** a partir del repo de AutoEQ (jaakkopasanen/AutoEq) como un JSON compacto empaquetado en la app.
- No se descarga nada en tiempo de ejecución.
- Se cita la licencia y la fuente en los créditos. *Verificar la licencia exacta de los datos antes de empaquetarlos.*
- Plan B si los datos no se pueden empaquetar *(decisión mía)*: la v1 sale sin el buscador AutoEQ, solo con EQ paramétrico manual, y se añade la importación de un fichero `ParametricEQ.txt` de AutoEQ que el usuario se descarga él mismo. Nada se descarga automáticamente.

## 9. Pruebas

- **Tests unitarios**:
  - DSP: ganancia con rampa, limitador, respuesta en frecuencia del EQ y matriz de balance/mono, comprobados contra valores esperados.
  - Regla de §8.2.
  - Agrupación de procesos.
  - Persistencia.
- **Test de "no ensuciar"**: con todo en reposo, comprobar que no existe ningún tap ni aggregate de la app.
- **Checklist manual** en macOS 14 / 15 / 26, en Apple Silicon y en Intel si es posible:
  - Spotify, Music, Chrome, Safari, Zoom/Meet, un juego y Electron (Slack/Discord)
  - conectar y desconectar auriculares Bluetooth y USB
  - cambiar la salida por defecto
  - matar la app con `kill -9` y comprobar que el audio vuelve a la normalidad

## 10. Lo que queda a criterio del builder

- Estructura del proyecto Xcode / Swift Package y organización de módulos.
- Si usar sandbox (ver §6).
- Implementación concreta del DSP: biquads propios con vDSP o AudioUnits de Apple, siempre que se cumplan "sin clics" y "sin reservas de memoria en el callback".
- Número de bandas del EQ manual (propuesta: hasta 10 bandas paramétricas, que es suficiente para AutoEQ).
- Formato exacto del JSON de ajustes, con un campo de versión para migraciones.
- Pipeline de CI (GitHub Actions: build y tests).

## 11. Pendiente del usuario (no bloquea el diseño)

- **Nombre** del proyecto.
- **Licencia**: propuesta **MIT**, por sencillez y para que cualquiera pueda reutilizarlo. GPL-3.0 si se quiere obligar a que las mejoras sigan abiertas.
- **Firma y notarización**: cuenta de Apple Developer (99 USD al año) o distribuir sin notarizar vía GitHub Releases + Homebrew cask.
