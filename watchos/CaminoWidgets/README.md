# CaminoWidgets — complicación / widget "Mi etapa"

Extensión WidgetKit (watchOS 10+) embebida en `CaminoWatch`
(`org.caminoseguro.watch.widgets`, `NSExtensionPointIdentifier = com.apple.widgetkit-extension`).
La define `watchos/project.yml`; el `Info.plist` lo genera XcodeGen y no se versiona.

## Familias

| Familia | Con etapa | Sin etapa | Toque abre |
|---|---|---|---|
| `accessoryCircular` | `Gauge` recorrido/plan, cifra en km en el centro, etiqueta "km" ("DEMO" en demostración) | figura caminando | etapa / estadísticas |
| `accessoryRectangular` (también Smart Stack) | nombre de etapa, "4,2 km de 22 km", tiempo con `Text(startedAt, style: .timer)` | "Sin etapa en curso" + "Última: … · 22 km" | etapa / estadísticas |
| `accessoryInline` | "4,2 km · 1:05:12" (tiempo vivo) | "Camino Seguro" | etapa / estadísticas |
| `accessoryCorner` | cifra en km + etiqueta curva "km de 22 km" | figura + "Sin etapa" | etapa / estadísticas |

Enlaces: `widgetURL(DeepLink.stage.url)` con etapa, `DeepLink.stats.url` sin ella.

Accesibilidad (STANDARDS_MATRIX H18, H19, Q16): sólo estilos de texto del sistema
(`.headline`, `.body`, `.footnote`, `.title3`; ninguno por debajo de 11 pt), `Text` nativo,
la información nunca depende del color (cifra + unidad siempre en texto; icono `location.slash`
con etiqueta "Sin GPS"). El color (token `positive`) sólo se aplica con
`widgetRenderingMode == .fullColor`; en modos acentuado y monocromo (`vibrant`) se usa
`widgetAccentable()` en la cifra principal. Etiquetas VoiceOver explícitas.
"DEMO" visible cuando la instantánea viene del modo demostración.

## Fuente de datos

`Shared/WidgetSnapshot.swift` (compilado en la app y en la extensión): JSON en el contenedor del
App Group `group.org.caminoseguro.watch` (`widget-snapshot.json`), escritura atómica.
Contiene nombre de etapa, inicio, metros recorridos/planificados, `hasFix`, `isDemo`,
`updatedAt` y la última etapa terminada. **Nunca coordenadas** ni identificadores de sesión o POI.

- La app escribe desde `CaminoWatch/WidgetBridge.swift`, llamado en cada `refresh()` del modelo:
  escribe sólo si cambia algo visible (distancia ±100 m, etapa, GPS, demo, última etapa).
- Pide `WidgetCenter.shared.reloadAllTimelines()` sólo: al empezar/terminar etapa (o cambio
  demo), y durante la etapa cada ≥15 min, o antes si la distancia cambió ≥0,5 km (con un suelo
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
