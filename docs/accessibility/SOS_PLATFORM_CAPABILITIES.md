# SOS en Camino Seguro Watch: capacidades por plataforma (solo fuentes oficiales)

Fecha de investigación: 2026-10-05. Complementa `SOS_FEASIBILITY.md` (que ya cubre `WKApplication.openSystemURL` y la confirmación del sistema en watchOS; aquí no se repite).

Leyenda de evidencia:
- [V] Texto literal leído de la página oficial (HTML de developer.android.com o JSON de developer.apple.com).
- [P] Solo fragmento de resultado de búsqueda sobre la página oficial (la página en sí estaba bloqueada). Verificar a mano antes de afirmarlo en la UI.
- [I] Inferencia mía, no es texto oficial.
- [NV] No verificado / no documentado.

Estado: Documentado / No documentado / No disponible.

## 0. Acceso a dominios

| Dominio | Resultado |
|---|---|
| developer.android.com (HTML) | Accesible vía curl (no vía WebFetch, que devuelve solo navegación). Texto extraído del HTML. |
| developer.apple.com/tutorials/data/documentation/...json | Accesible. |
| android.googlesource.com, source.android.com | Bloqueado (proxy, CONNECT 403). No se pudo leer el código AOSP de `Intent`/telecom. |
| support.google.com, blog.google, www.samsung.com, support.apple.com | Bloqueado (EGRESS_BLOCKED). Solo fragmentos de búsqueda [P]. |
| raw.githubusercontent.com (espejo aosp-mirror) | Accesible, pero no es fuente oficial: no se usó. |

## 1. Android / Wear OS: citas clave

### 1.1 `Intent.ACTION_CALL` (https://developer.android.com/reference/android/content/Intent) [V]

> "Note: there will be restrictions on which applications can initiate a call; most applications should use the ACTION_DIAL."

> "Note: this Intent cannot be used to call emergency numbers. Applications can dial emergency numbers using ACTION_DIAL, however."

> "Note: If your app targets M or higher and declares as using the Manifest.permission.CALL_PHONE permission which is not granted, then attempting to use this action will result in a SecurityException."

Por tanto, `ACTION_CALL` con 112 no es una vía documentada; la vía documentada para emergencias es `ACTION_DIAL`.

### 1.2 `ACTION_DIAL` (misma URL) [V]

> "Activity Action: Dial a number as specified by the data. This shows a UI with the number being dialed, allowing the user to explicitly initiate the call."

Guía "Common intents" (https://developer.android.com/guide/components/intents-common) [V]: "To open the phone app and dial a phone number, use the ACTION_DIAL action ... When the phone app opens, it displays the phone number, and the user must tap the Call button to begin the phone call."

### 1.3 `ACTION_CALL_EMERGENCY` / `ACTION_CALL_PRIVILEGED`

- En la referencia pública de `Intent` (HTML completo descargado) no aparece ninguna de las dos constantes: [NV] como API pública. Su código fuente (AOSP) no se pudo leer (googlesource bloqueado). Que sean para apps del sistema es [I] a partir de lo siguiente.
- Lo único oficial relacionado es el permiso (https://developer.android.com/reference/android/Manifest.permission) [V]:
  > "CALL_PRIVILEGED: Allows an application to call any phone number, including emergency numbers, without going through the Dialer user interface for the user to confirm the call being placed. Not for use by third-party applications."
- `CALL_PHONE` [V]: "Allows an application to initiate a phone call without going through the Dialer user interface for the user to confirm the call." (Protection level: dangerous.)
- `TelecomManager.placeCall` (https://developer.android.com/reference/android/telecom/TelecomManager) [V]: "If method-caller is either the user selected default dialer app or preloaded system dialer app, then emergency calls will also be allowed."
- Guía de dialer por defecto (https://developer.android.com/develop/connectivity/telecom/dialer-app) [V]: "The preloaded dialer will ALWAYS be used when the user places an emergency call, even if your app fills the RoleManager.ROLE_DIALER role." y "If a non-preloaded dialer app uses Intent#ACTION_CALL to place an emergency call, it will be raised to the preloaded dialer app using Intent#ACTION_DIAL for confirmation".

### 1.4 Package visibility y `<queries>` (Android 11 / API 30+)

- https://developer.android.com/training/package-visibility/declaring [V]: "If your app targets Android 11 (API level 30) or higher, the system makes some apps visible to your app automatically, but it filters out other apps by default." Reglas de `<intent>` en `<queries>`: exactamente un `<action>`; no se permiten `path`, `pathPrefix`, `pathPattern`, `port` ni `mimeGroup` en `<data>`.
- https://developer.android.com/training/package-visibility/use-cases [V]: "When an app that targets Android 11 or higher uses an intent to start an activity in another app, the most straightforward approach is to invoke the intent and handle the ActivityNotFoundException exception if no app is available. If part of your app depends on knowing whether the call to startActivity() can succeed, such as showing a UI, add an element to the <queries> element of your app's manifest."
- Esa misma página dice, para URLs, que `startActivity()` no requiere visibilidad de paquetes.
- Ninguna página oficial leída trae un ejemplo `ACTION_DIAL` + `tel`. El `<queries>` de abajo es una aplicación de la regla general [I].

## 2. Wear OS: telefonía y continuación en el móvil

### 2.1 Feature flags (https://developer.android.com/reference/android/content/pm/PackageManager) [V]

- `FEATURE_TELEPHONY` ("android.hardware.telephony"): "The device has a telephony radio with data communication support."
- `FEATURE_TELEPHONY_CALLING` ("android.hardware.telephony.calling", API 33): "The device supports Telephony APIs for calling service. This feature should only be defined if FEATURE_TELEPHONY_RADIO_ACCESS, FEATURE_TELEPHONY_SUBSCRIPTION, and FEATURE_TELECOM have been defined."
- `FEATURE_TELEPHONY_RADIO_ACCESS` (API 33): "The device supports Telephony APIs for the radio access."
- `FEATURE_WATCH` ("android.hardware.type.watch"): "This is a device dedicated to showing UI on a watch."
- Pista para el minSdk 30: las constantes `*_CALLING` son API 33; en API 30-32 se puede pasar el string "android.hardware.telephony" a `hasSystemFeature`. Que el string `android.hardware.telephony.calling` exista en relojes con API <33 no está documentado [NV].

### 2.2 Relojes LTE vs Bluetooth

- https://developer.android.com/training/wearables/data/network-communication [V]: "When a watch has a Bluetooth connection to a phone, the watch's network traffic is generally proxied through the phone. When a phone is unavailable, Wi-Fi and cellular networks are used, depending on the watch hardware."
- No he encontrado documentación oficial de Android que diga explícitamente "un reloj sin LTE no tiene marcador" ni que describa qué app maneja `ACTION_DIAL` en un reloj [NV]. Tampoco que un reloj solo-Bluetooth tenga o no `FEATURE_TELEPHONY`: no documentado [NV].
- Fragmento [P] de resultados sobre developer.android.com: los dispositivos remotos (relojes) pueden gestionar llamadas vía `InCallService` con `MANAGE_ONGOING_CALLS` y `CompanionDeviceManager`. Eso es para apps dialer, no para apps normales.

### 2.3 `RemoteActivityHelper` (https://developer.android.com/reference/androidx/wear/remote/interactions/RemoteActivityHelper) [V]

- Artefacto `androidx.wear:wear-remote-interactions`, desde 1.0.0. Última estable según https://developer.android.com/jetpack/androidx/releases/wear: 1.2.0 (beta 1.3.0-beta01). La tabla se leyó con WebFetch (resumen del modelo, no HTML literal): [P-].
- Clase: "Support for opening android intents on other devices."
- `startRemoteActivity`:
  > "This API currently supports sending intents with action set to android.content.Intent.ACTION_VIEW, a data URI populated using android.content.Intent.setData, and with the category android.content.Intent.CATEGORY_BROWSABLE present."

  > "If the intent passed in sets a different action or does not contain the CATEGORY_BROWSABLE category or does not set a data URI, the call will be rejected and a kotlin.IllegalArgumentException thrown."

  > "If any additional attributes of the intent are set (for examples, extras, package, component), they will be stripped from the intent."
- Con `targetNodeId` null en un reloj: "the activity will start on the companion phone device."
- Resultado: "The ListenableFuture which resolves if starting activity was successful or throws Exception if any errors happens. If there's a problem with starting remote activity, RemoteIntentException will be thrown." La clase dice que el futuro "is completed after the intent has been sent or failed if there was an issue with sending the intent". Es decir, confirma el envío, no que el teléfono haya abierto el marcador ni que el usuario haya llamado.
- Disponibilidad: `getAvailabilityStatus()` (1.1.0): "Wear devices start to support determining the availability status from Wear Sdk WEAR_TIRAMISU_4. On older wear devices, it will always return STATUS_UNKNOWN." `STATUS_TEMPORARILY_UNAVAILABLE`: "There is a known paired device, but it is not currently connected or reachable".
- Consecuencia clave: `ACTION_DIAL` NO es un intent aceptado por `startRemoteActivity`. Un `Intent(ACTION_VIEW, Uri.parse("tel:112")).addCategory(CATEGORY_BROWSABLE)` cumple las reglas del API (ACTION_VIEW + BROWSABLE + data URI), pero que el teléfono lo resuelva con el marcador, o que el reloj/teléfono lo permita para un esquema `tel:`, no está documentado [NV]. Hay que probarlo en hardware.
- Con iPhone emparejado: la doc de standalone apps (https://developer.android.com/training/wearables/apps/standalone-apps) [V] menciona `PhoneTypeHelper.getPhoneDeviceType()` para saber si el teléfono es Android o iOS y que "not all phones—such as iPhones—support the Play Store". Qué hace `RemoteActivityHelper` con un iPhone: no documentado [NV].
- Nuevo (1.3.0-beta01, API 37): `startPhoneActivityWithUnlock` / `startRemoteActivityAttemptUnlock`. Fuera de alcance; no es estable.

## 3. SOS nativo y satélite (Wear OS)

Todo [P] (páginas bloqueadas). Varía por fabricante.

| Fabricante | Gesto | Fuente |
|---|---|---|
| Google Pixel Watch | "press the crown 5 times. Then touch and hold the screen for 3 seconds to call emergency services" (modo "touch & hold") o llamada automática tras cuenta atrás de 5 s | https://support.google.com/googlepixelwatch/answer/12663810 |
| Samsung Galaxy Watch | Pulsar la tecla Home (botón de encendido) 3 veces; envía mensajes SOS con ubicación a contactos y, si se configuran, llama a contactos de SOS. Algunos modelos Watch4: 3 o 4 pulsaciones | https://www.samsung.com/us/support/answer/ANS10002904/ |
| Otros relojes Wear OS | No documentado en esta investigación [NV] | n/d |

- No se encontró en la doc de developer.android.com (notas de versión de Wear OS ni guías) ninguna API pública para disparar ni interceptar Emergency SOS [NV]. Que "no hay API" es [I]: no hay documentación que la ofrezca.
- Satélite Wear OS [P]: "Satellite SOS is available only on Pixel Watch 4 LTE and Pixel Watch 5 LTE" (https://support.google.com/googlepixelwatch/answer/16407554). Países listados en el fragmento: EE. UU. (incl. Puerto Rico, Alaska, Hawái), Canadá, Australia y una lista de países europeos (incluye España, Francia, Alemania, Italia, Portugal, Reino Unido, entre otros). Modo: texto, no voz; un Emergency Support Provider (ESP) hace de intermediario con los servicios de emergencia (fragmento de https://blog.google/products-and-platforms/devices/pixel/pixel-watch-satellite-sos/). Incluido sin coste dos años tras el lanzamiento. Para la lista exacta de países hay que leer la página oficial.
- API pública de satélite para apps: no documentada [NV].

## 4. Apple: citas clave

### 4.1 Restricciones de `tel:` con números de emergencia [NV]

- No existe documentación oficial leída que restrinja o permita `tel:112`/`tel:911` explícitamente (ver `SOS_FEASIBILITY.md` §2).
- `WKApplication.openSystemURL(_:)` (watchOS 7.0+, no deprecado) [V] (JSON de developer.apple.com): "Use this method to initiate phone calls or send messages. The URL you open is sent to the appropriate system app for handling, at which point the user can choose whether to continue the operation." Parámetro: "A URL that supports the tel: or sms: scheme."
- `WKExtension.openSystemURL(_:)` [V]: deprecado en watchOS 9.2 ("renamed": WKApplication). Resuelve el [NV] pendiente de `SOS_FEASIBILITY.md`.
- SwiftUI `Link` / `OpenURLAction`: ambos watchOS 7.0+ [V]. Fragmento de OpenURLAction: "If you want to know whether the action succeeds, add a completion handler that takes a Boolean value ... That method calls your completion handler after it determines whether it can open the URL, but possibly before it finishes opening the URL." No dice nada específico de `tel:`.
- iOS `UIApplication.open(_:options:completionHandler:)` [V]: "UIKit supports many common schemes, including the http, https, tel, facetime, and mailto schemes." "If no app is capable of handling the specified scheme, the completion handler is called with the success parameter set to false."
- iOS `canOpenURL(_:)` [V]: devuelve false para esquemas no declarados en `LSApplicationQueriesSchemes`; figura deprecado en iOS 27 con el mensaje "Prefer attempting to open URLs and handling any failures". No aplica a watchOS (no está en el JSON de `WKInterfaceDevice`).

### 4.2 ¿Puede el reloj saber si tiene celular o puede llamar? (pregunta 9)

- `WKInterfaceDevice` (https://developer.apple.com/documentation/watchkit/wkinterfacedevice) [V]: la lista de miembros del JSON es: `current()`, `screenBounds`, `screenScale`, `name`, `model`, `localizedModel`, `wristLocation`, `crownOrientation`, `preferredContentSizeCategory`, `systemName`, `systemVersion`, `layoutDirection`, batería, `waterResistanceRating`, `isWaterLockEnabled`, `play(_:)`, `supportsAudioStreaming`, `identifierForVendor`. No hay propiedad de celular ni de capacidad de llamada.
- Core Telephony (https://developer.apple.com/documentation/coretelephony) [V]: plataformas iOS, iPadOS, Mac Catalyst, macOS. No watchOS.
- Conclusión: API pública para saber si el reloj tiene celular o puede llamar: no documentada [NV]. Búsqueda en foros de developer.apple.com sin resultado útil.

### 4.3 Emergency SOS nativo en Apple Watch [P]

- Mantener pulsado el botón lateral hasta el control "Emergency Call"; arrastrarlo o seguir manteniendo y tras cuenta atrás llama. Requiere "a satellite connection, cellular connection, or Wi-Fi calling with an internet connection from your Apple Watch or nearby iPhone". https://support.apple.com/en-us/108374 y https://support.apple.com/guide/watch/contact-emergency-services-apdfe3c02513/watchos
- API de terceros: ninguna (ver `SOS_FEASIBILITY.md` §5, hilo de foro con respuesta de DTS).

### 4.4 Emergency SOS por satélite en Apple Watch [P]

- Modelo: Apple Watch Ultra 3 o posterior ("You need an Apple Watch Ultra 3 or later"). Páginas: https://support.apple.com/en-us/125126, https://support.apple.com/en-us/123924, guía https://support.apple.com/guide/watch/use-satellite-features-apd9fc7da3b0/watchos
- Países (fragmento): Andorra, Australia, Austria, Bélgica, Canadá, Francia, Alemania, Islandia, Irlanda, Italia, Japón, Luxemburgo, México, Países Bajos, Nueva Zelanda, Noruega, Portugal, España, Suiza, Reino Unido y EE. UU. No ofrecida en relojes comprados en Armenia, Bielorrusia, China continental, Hong Kong, Macao, Kirguistán, Kazajistán y Rusia. Gratis dos años tras activar un Ultra 3.
- Mecanismo: "If your call won't connect, you can text emergency services via satellite" (Emergency Text via Satellite). Es por mensajes de texto, no voz. Requiere no tener cobertura celular ni Wi-Fi.
- Demo: Control Center, esfera, o Ajustes > SOS > "Try Demo"; "The Emergency SOS demo doesn't start a call to emergency services."
- API pública para apps: no documentada [NV] (ninguna página consultada la ofrece).

### 4.5 Ubicación en emergencias (pregunta 10)

- No se encontró guía oficial sobre mostrar coordenadas al usuario en una emergencia [NV]. No se consultó la HIG (se renderiza con JS; ya marcada [NV] en `SOS_FEASIBILITY.md`).

## 5. Tabla plataforma x capacidad

| Plataforma | Capacidad | Mecanismo / API público | Estado | Cita | URL | Qué debe hacer la app |
|---|---|---|---|---|---|---|
| Wear OS | Marcar 112 | `Intent(ACTION_DIAL, Uri.parse("tel:112"))` + `startActivity` | Documentado (ACTION_DIAL para emergencias) | "Applications can dial emergency numbers using ACTION_DIAL, however." | https://developer.android.com/reference/android/content/Intent | Usar ACTION_DIAL, nunca ACTION_CALL ni pedir CALL_PHONE. Etiqueta honesta: "Abrir marcador con 112". El usuario pulsa Llamar. |
| Wear OS | ACTION_CALL / CALL_PRIVILEGED / CALL_EMERGENCY | `ACTION_CALL` público; `CALL_PRIVILEGED` es permiso de sistema; `ACTION_CALL_EMERGENCY` sin doc pública | No disponible para terceros | "this Intent cannot be used to call emergency numbers"; "Not for use by third-party applications." | Intent y Manifest.permission (arriba) | No usarlos. No declarar CALL_PHONE. |
| Wear OS | Verificar manejador | `resolveActivity` / `queryIntentActivities`, o `startActivity` con captura de `ActivityNotFoundException` | Documentado; el `<queries>` para `tel` es [I] | "invoke the intent and handle the ActivityNotFoundException exception if no app is available" | https://developer.android.com/training/package-visibility/use-cases | Preferir try/catch de `ActivityNotFoundException`. Si se hace comprobación previa para mostrar/ocultar UI, añadir `<queries>` (abajo). |
| Wear OS | Saber si hay telefonía | `hasSystemFeature(FEATURE_TELEPHONY)` / `FEATURE_TELEPHONY_CALLING` (API 33) | Documentado (flags); semántica en relojes concretos no documentada | "The device has a telephony radio with data communication support." | https://developer.android.com/reference/android/content/pm/PackageManager | Combinar flag + comprobación del manejador. Tener telefonía no garantiza SIM activa ni cobertura. |
| Wear OS | Continuar en el móvil | `RemoteActivityHelper.startRemoteActivity` (solo ACTION_VIEW + BROWSABLE + data URI) | Documentado, pero NO admite ACTION_DIAL; `tel:` vía VIEW no documentado | "If the intent passed in sets a different action or does not contain the CATEGORY_BROWSABLE category ... rejected" | https://developer.android.com/reference/androidx/wear/remote/interactions/RemoteActivityHelper | No prometer "se abrió el marcador en el móvil". Si se ofrece, probar en hardware; el éxito del futuro solo indica que el intent se envió. Alternativa segura: instruir "Llama al 112 desde tu móvil". |
| Wear OS | SOS nativo | Gesto de sistema (Pixel: corona x5; Samsung: Home x3) | Documentado por fabricante [P]; sin API para terceros | "press the crown 5 times" (Pixel) | https://support.google.com/googlepixelwatch/answer/12663810 | Mencionar "consulta el SOS de tu reloj" sin fijar el gesto salvo que se detecte el fabricante (`Build.MANUFACTURER`) y se verifique. |
| Wear OS | Satélite | Pixel Watch 4/5 LTE; sin API pública | Documentado [P] (función del sistema); API: No documentado | "Satellite SOS is available only on Pixel Watch 4 LTE and Pixel Watch 5 LTE" | https://support.google.com/googlepixelwatch/answer/16407554 | No ofrecer ni simular satélite. Si se menciona, solo como función del sistema en modelos y regiones concretos. |
| watchOS | Marcar 112 | `WKApplication.openSystemURL(tel:)` o SwiftUI `Link` | Documentado (tel:); 112 específicamente: No documentado | "...at which point the user can choose whether to continue the operation." | https://developer.apple.com/documentation/watchkit/wkapplication/opensystemurl(_:) | Botón "Llamar al 112" con confirmación del sistema; no duplicar confirmación; ver `SOS_FEASIBILITY.md`. |
| watchOS | Verificar manejador | Ninguno específico en watchOS; `OpenURLAction` completion (acepta/rechaza) | Parcial. `canOpenURL` es de iOS | "...possibly before it finishes opening the URL." | https://developer.apple.com/documentation/swiftui/openurlaction | No confiar en el Bool como prueba de llamada establecida. Mostrar texto de fallback. |
| watchOS | Saber si hay celular / puede llamar | Ninguno | No documentado | `WKInterfaceDevice` no expone celular; Core Telephony no es watchOS | https://developer.apple.com/documentation/watchkit/wkinterfacedevice | No condicionar la UI a "tiene celular". Texto: "Si el reloj no tiene red, la llamada puede no completarse; usa el iPhone." |
| watchOS | Continuar en el iPhone | No hay equivalente público documentado en esta investigación | No documentado | n/d | n/d | No ofrecer botón "abrir en iPhone" para llamar. |
| watchOS | SOS nativo | Botón lateral (mantener) | Documentado [P]; sin API para terceros | "Press and hold your watch's side button ... until the Emergency Call slider appears" | https://support.apple.com/en-us/108374 | Indicar el gesto del sistema como vía principal. |
| watchOS | Satélite | Apple Watch Ultra 3+; mensaje de texto; demo disponible | Documentado [P]; API: No documentado | "you can text emergency services via satellite" | https://support.apple.com/en-us/125126 | No implementar. Mencionar como función del sistema solo en Ultra 3+. No llamar "demo" a nada nuestro: el demo oficial es de Ajustes. |

## 6. Recomendaciones de implementación

### 6.1 Wear OS: manifest

No declarar `CALL_PHONE`. Para comprobar de antemano el manejador de `tel:` con `queryIntentActivities`/`resolveActivity` en targetSdk 30+, declarar:

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.DIAL" />
        <data android:scheme="tel" />
    </intent>
</queries>
```

Esta entrada es [I]: aplica la regla de `<queries>` documentada (un `<action>`, `scheme` permitido) a `ACTION_DIAL` + `tel`; no hay ejemplo oficial para este caso. Se puede omitir si solo se usa `startActivity` con `try/catch ActivityNotFoundException` (la doc dice que `startActivity()` no requiere visibilidad para URLs; para `tel` no hay frase explícita [NV]).

### 6.2 Wear OS: código (patrón)

```kotlin
fun openDialer(context: Context): Boolean {
    val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:112"))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    return try { context.startActivity(intent); true }
    catch (e: ActivityNotFoundException) { false }
}
```

- Si devuelve `false`, mostrar el texto de fallback (6.4).
- Opcional: `context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)` solo para ajustar el texto, no para bloquear el botón.

### 6.3 watchOS

Ver `SOS_FEASIBILITY.md` (Link/`openSystemURL`). Añadido aquí: usar `WKApplication.openSystemURL` (no `WKExtension`, deprecado en watchOS 9.2).

### 6.4 Textos honestos (español)

- Botón: "Abrir marcador con 112" (Wear OS) / "Llamar al 112" (watchOS). Nunca "SOS" ni "Llamada automática".
- Aviso bajo el botón: "Esta app no llama sola: el reloj te pedirá confirmar. Si tu reloj no tiene conexión, la llamada puede no completarse. Usa tu móvil si lo tienes cerca."
- Fallback sin manejador: "Este reloj no puede abrir el marcador. Llama al 112 desde tu móvil o usa el SOS de tu reloj."
- Información de SOS nativo: "Tu reloj puede tener una función de emergencia propia. Consulta los ajustes de tu reloj. Esta app no la sustituye."
- Satélite: no prometer. Si se menciona: "Algunos relojes (Apple Watch Ultra 3, Pixel Watch 4/5 LTE) tienen SOS por satélite del sistema; solo en ciertos países y por texto."
- Aviso legal breve: "No sustituye a los servicios de emergencia."

## 7. No verificable sin hardware

- Qué app abre `ACTION_DIAL tel:112` en cada reloj Wear OS (Pixel Watch, Galaxy Watch, otros), y si el reloj Bluetooth-only tiene manejador alguno.
- Si el marcador del reloj muestra el 112 y permite llamar con LTE sin SIM activa, con el móvil cerca o solo con Wi-Fi.
- Si `RemoteActivityHelper` con `ACTION_VIEW tel:112` + BROWSABLE abre el marcador del móvil, con teléfono Android y con iPhone; qué ocurre con el móvil bloqueado.
- Valor real de `hasSystemFeature(FEATURE_TELEPHONY)` / `FEATURE_TELEPHONY_CALLING` en relojes solo-BT, y presencia del string `android.hardware.telephony.calling` en API 30-32.
- Comportamiento de `openSystemURL(tel:112)` en watchOS (número de confirmaciones, enrutado como llamada de emergencia real) con Watch celular, GPS-only con iPhone cerca, y sin iPhone.
- Gestos de SOS por modelo/versión (Pixel: 5 pulsaciones; Samsung: 3 o 4; otros fabricantes) y regiones del satélite: leer la página oficial en el momento del lanzamiento, ya que los [P] son fragmentos de búsqueda.
- Todo lo marcado [P] (páginas de support.google.com, samsung.com, support.apple.com, blog.google): bloqueadas aquí; verificar el texto literal manualmente.
