# CaminoWidgets — complicación / widget "Mi etapa"

Extensión WidgetKit (watchOS 10+) embebida en `CaminoWatch`
(`org.caminoseguro.watch.widgets`, `NSExtensionPointIdentifier = com.apple.widgetkit-extension`).
La define `watchos/project.yml`; el `Info.plist` lo genera XcodeGen y no se versiona.

## Familias (V1.1 §H)

| Familia | Con trayecto | Sin trayecto |
|---|---|---|
| `accessoryCircular` | `Gauge` recorrido/plan, cifra en las unidades del usuario; etiqueta unidad o símbolo de pausa | figura caminando (VoiceOver: «Iniciar trayecto») |
| `accessoryRectangular` (también Smart Stack) | nombre de etapa, "4,2 km de 22 km", «en marcha · 1:05:12» o «pausado» | «Iniciar trayecto» con icono + "Última: … · 22 km" |
| `accessoryInline` | "4,2 km · en marcha" / "… · pausado" | «Iniciar trayecto» con icono |
| `accessoryCorner` | cifra + etiqueta curva ("km de 22 km", "km · pausado") | figura + «Iniciar» |

Tocar abre siempre la pantalla Trayecto (`widgetURL(DeepLink.stage.url)`): **nunca** inicia un trayecto
ni una llamada. Unidades e idioma (separadores) vienen de la instantánea (`units`, `lang`); los textos,
del idioma del sistema. Si la instantánea de un trayecto tiene más de 15 min (`updatedAt`), se muestra
"hace X min" en lugar del estado/tiempo (entradas de timeline cada 5 min a partir de ese punto): no se
promete frescura. Las complicaciones no se capturan con `simctl`: se verifican con los `#Preview`
(activo, pausado en millas, sin GPS, datos antiguos, sin trayecto, sin datos).

Accesibilidad (STANDARDS_MATRIX H18, H19, Q16): sólo estilos de texto del sistema
(`.headline`, `.body`, `.footnote`, `.title3`; ninguno por debajo de 11 pt), `Text` nativo,
la información nunca depende del color (cifra + unidad siempre en texto; icono `location.slash`
con etiqueta "Sin GPS"). El color (token `positive`) sólo se aplica con
`widgetRenderingMode == .fullColor`; en modos acentuado y monocromo (`vibrant`) se usa
`widgetAccentable()` en la cifra principal. Etiquetas VoiceOver explícitas.
"DEMO" visible cuando la instantánea viene del modo demostración (en todas las familias, también en
pausa y sin GPS). Con trayecto pero sin ningún fix válido todavía, la esfera dice "Sin GPS" (icono
`location.slash`) y nunca "0 km".

## Fuente de datos

`Shared/WidgetSnapshot.swift` (compilado en la app y en la extensión): JSON en el contenedor del
App Group `group.org.caminoseguro.watch` (`widget-snapshot.json`), escritura atómica.
Contiene nombre de etapa, inicio, metros recorridos/planificados, `hasFix`, `isDemo`,
`updatedAt`, la última etapa terminada y (v2, V1.1) `isPaused`, `units` y `lang`. **Nunca coordenadas** ni identificadores de sesión o POI.

- La app escribe desde `CaminoWatch/WidgetBridge.swift`, llamado en cada `refresh()` del modelo:
  escribe sólo si cambia algo visible (distancia ±100 m, etapa, GPS, demo, última etapa).
- Pide `WidgetCenter.shared.reloadAllTimelines()` sólo: al empezar/terminar etapa (o cambio
  demo), al pausar/reanudar, al cambiar unidades o idioma, y durante la etapa cada ≥15 min, o antes si la distancia cambió ≥0,5 km (con un suelo
  de 5 min entre recargas).
- Timeline: una entrada; política `.after(+15 min)` con etapa, `.never` sin etapa.
- El tiempo de etapa avanza solo en la esfera (`Text(_, style: .timer)`), sin recargas.

## Límites (honestos)

- **No hay actualización continua garantizada.** WidgetKit reparte un presupuesto de recargas
  (típicamente 40–70 al día para un widget visto con frecuencia); la distancia puede ir con
  retraso respecto a la app. Fuente: [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).
- **El App Group requiere firma real** (perfil con `com.apple.security.application-groups`
  para ambos bundle ids). Con `CODE_SIGNING_ALLOWED=NO` el contenedor puede ser `nil`:
  la app no escribe y el widget muestra "Abre Camino Seguro". Fuente:
  [containerURL(forSecurityApplicationGroupIdentifier:)](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)).
- **Smart Stack no garantiza aparición**: el sistema decide qué widget muestra y cuándo;
  el usuario puede fijarlo. Usa la familia `accessoryRectangular`.
  Fuente: [Creating accessory widgets and watch complications](https://developer.apple.com/documentation/widgetkit/creating-accessory-widgets-and-watch-complications).
- Si la app termina sin finalizar la etapa, la instantánea sigue mostrando la etapa hasta que la
  app vuelva a abrirse (el cronómetro sigue contando desde `startedAt`).

## Referencias de API (comprobadas en developer.apple.com)

- [WidgetFamily](https://developer.apple.com/documentation/widgetkit/widgetfamily) (`accessoryCorner` watchOS 9+)
- [widgetRenderingMode](https://developer.apple.com/documentation/swiftui/environmentvalues/widgetrenderingmode),
  [widgetAccentable(_:)](https://developer.apple.com/documentation/swiftui/view/widgetaccentable(_:))
- [containerBackground(for:alignment:content:)](https://developer.apple.com/documentation/swiftui/view/containerbackground(for:alignment:content:)) (watchOS 10)
- [widgetURL(_:)](https://developer.apple.com/documentation/swiftui/view/widgeturl(_:)),
  [widgetLabel(_:)](https://developer.apple.com/documentation/swiftui/view/widgetlabel(_:)),
  [widgetCurvesContent(_:)](https://developer.apple.com/documentation/swiftui/view/widgetcurvescontent(_:)) (watchOS 10)
- [TimelineReloadPolicy.after(_:)](https://developer.apple.com/documentation/widgetkit/timelinereloadpolicy/after(_:)),
  [WidgetCenter.reloadAllTimelines()](https://developer.apple.com/documentation/widgetkit/widgetcenter/reloadalltimelines())
- [#Preview(_:as:widget:timeline:)](https://developer.apple.com/documentation/widgetkit/preview(_:as:widget:timeline:)) (watchOS 10)
- [HIG Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets) (texto ≥ 11 pt)
