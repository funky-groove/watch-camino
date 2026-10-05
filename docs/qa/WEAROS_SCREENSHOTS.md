# Capturas Wear OS en el emulador (CI)

Capturas reales de la app Debug de Camino Seguro Watch en un emulador Wear OS, con datos de
**demostración**. Sirven para revisar diseño, textos, temas, idioma y tamaño de letra sin un reloj
físico. Equivalente Wear OS de `watchos/scripts/screenshots.sh`.

## Dónde y cuándo

- Workflow `.github/workflows/wearos.yml`, job **`screenshots`** (después de `build`, del que
  descarga el APK Debug). `ubuntu-latest` con KVM, `reactivecircus/android-emulator-runner@v2`,
  imagen `android-wear` API 33 (Wear OS 4) x86_64; si falla, se reintenta con API 30 (Wear OS 3).
- Perfiles: `wearos_small_round` (pasada completa) y `wearos_large_round` (sólo negro/perla, si
  la primera fue bien). Límite: 45 min.
- Artefacto **`wear-screenshots`**: PNG, `index.md` (tabla fichero/dispositivo/tema/pantalla/
  escenario/ruta/idioma), `contact_sheet.png` (si hay Pillow) y `logcat_<dispositivo>.txt`
  (etiquetas `CaminoDemo`, `NavController`, `AndroidRuntime`).
- Publicación opcional: lanzar el workflow a mano (*Run workflow*) con **`publish_screenshots`**
  marcado. Se sustituyen las capturas de `docs/screenshots/wearos/` y se hace push a la misma rama
  con `GITHUB_TOKEN` (ese push no vuelve a disparar workflows).
- En local, con un emulador Wear OS arrancado y `adb` en el PATH:
  `cd wearos && scripts/screenshots.sh out small-round full`.

## Cómo funciona

1. `wearos/scripts/screenshots.sh` instala el APK Debug (`adb install -r -g`), mantiene la
   pantalla encendida, desactiva animaciones y fija la ubicación del emulador cerca de Sarria.
2. Para cada captura: `am force-stop`, después
   `am start -W -n org.caminoseguro.watch/.ui.MainActivity --es demo.scenario … --es demo.route …
   --es demo.theme negro|perla --es demo.lang es|en --es demo.facehint show|hide`; espera (`SCREENSHOT_WAIT`, 5 s por defecto)
   y hace `adb exec-out screencap -p`. Si la app no está en primer plano (cierre inesperado) o el
   PNG no es válido, esa captura cuenta como fallo y se sigue con la siguiente. El script sólo
   falla si no hay **ninguna** captura.
3. Pantallas (en negro y perla): inicio, trayecto activo, pausado, perfil, lugares, ficha de lugar,
   SOS, ajustes, ayuda de esfera, aviso de primer uso y resumen. En el reloj pequeño, además,
   trayecto y SOS en inglés, y trayecto con `font_scale 1.3`.
4. Las rutas (`profile`, `places`, `place/p01`, `sos`, `settings`, `face_help`, `face_hint`,
   `summary`) son las de `Routes` en `ui/CaminoApp.kt`; si cambian, se ajustan con
   variables de entorno (`ROUTE_PROFILE`, `ROUTE_PLACES`, …) sin tocar el script. Una ruta que no
   existe deja la pantalla principal (lo dice el `logcat` de `NavController`).

### Lado de la app (sólo Debug: `wearos/app/src/debug/`)

- `DemoBootstrapProvider` (ContentProvider con `exported="false"`, declarado en el manifiesto de
  Debug; Release no lo tiene) registra `DemoHooks.apply` y un `ActivityLifecycleCallbacks`.
  Sin el extra `demo.scenario` no hace nada.
- `DemoScenarioInstaller`, antes de `MainActivity.onCreate` (y, por tanto, antes del ViewModel):
  - sustituye en el contenedor el `CaminoController` por uno **en memoria**
    (`InMemorySessionStore`, `InMemorySyncQueueStore`, `MockCaminoApi(0)`, reloj desplazable);
    los almacenes de fichero (tema, avisos…) se redirigen a `cacheDir/demo-scenario/` (se borra en
    cada lanzamiento). Si no puede sustituir el controlador, **no siembra nada**: el almacenamiento
    real del usuario nunca se escribe;
  - cambia el marcador de SOS por `FakeEmergencyDialer` (además, las capturas no pulsan nada);
  - deja el aviso «Accede desde tu esfera» (§I) descartado en memoria, salvo con
    `demo.facehint=show` (captura «aviso de primer uso»), para que no tape las demás pantallas;
  - siembra el escenario con fixes de las fixtures: Sarria → Barbadelo, 65 min, ≈ 4,2 km
    (4 165 m), 5 230 pasos, +87 m (altitud sintética); `paused` = lo mismo en pausa desde hace
    30 s; `finished` = Sarria – Portomarín completa (≈ 19,6 km, 5 h 30 min); `nearby` = Palas de
    Rei → Melide (≈ 12,6 km), a ≈ 200 m de la iglesia de Melide;
  - aplica idioma (sólo en el proceso) y la ruta: convierte `demo.route` en el deep link implícito
    de Navigation (`android-app://androidx.navigation/<ruta>`).
- Sin permisos nuevos y sin red.

## Qué NO verifica

- **Hardware real**: pantalla física (brillo al sol, OLED, recorte del bisel), rendimiento,
  batería, modo ambiente/always-on, corona/botones físicos y hápticos.
- **LTE / telefonía**: en el emulador no hay red móvil; los textos «Llamar al 112» / «Marcar 112»
  dependen de lo que el emulador declara, no de un reloj LTE real.
- **Marcador real**: el SOS de las capturas usa un marcador simulado y nunca se pulsa «Llamar».
  Que `ACTION_DIAL tel:112` abra el marcador del sistema se prueba a mano en un reloj
  (`docs/accessibility/SOS_PLATFORM_CAPABILITIES.md`).
- **Sensores**: GPS, contador de pasos, barómetro/altitud. Las cifras son DEMO inyectadas en el
  controlador; los sensores reales siguen enganchados al controlador original y no influyen. Si
  el emulador no tiene contador de pasos, la UI puede mostrar «pasos no disponibles» aunque haya
  pasos sembrados (es el estado real del dispositivo emulado).
- **Persistencia y restauración**: la demo vive en memoria; no prueba lectura/escritura de
  `filesDir/camino`, reinicios del proceso ni el servicio en primer plano.
- **Notificaciones de avisos POI, permisos en contexto y diálogos del sistema**: se conceden con
  `-g`/`pm grant`; no se ve el flujo de petición de permisos.
- **Interacción**: no hay toques ni desplazamientos; sólo el primer fotograma estable de cada
  pantalla (lo que queda por debajo del pliegue no aparece).
- **Accesibilidad completa**: TalkBack, orden de foco y tamaños de toque; sólo `font_scale 1.3`.
- **Esferas/complicaciones y tiles**: la «ayuda de esfera» es la pantalla de la app, no una
  esfera configurada.
