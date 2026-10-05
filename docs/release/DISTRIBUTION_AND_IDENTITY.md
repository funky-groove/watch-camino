# Camino Seguro Watch — Distribución e identidad

Estado: borrador de investigación, 2026-10-05. Todo identificador marcado **PROPUESTA** requiere confirmación del equipo antes de usarse.
Ninguna acción de este documento se ha ejecutado: no hay cuentas, App IDs, registros ni perfiles creados por este repositorio.

Convenciones: las citas literales van entre comillas con su URL. "NO VERIFICADO" marca lo que ninguna fuente oficial accesible confirma. "INFERENCIA" marca una conclusión propia derivada de citas.

## 0. Fuentes consultadas y dominios bloqueados

Accesibles: `developer.apple.com` (JSON de `tutorials/data/documentation/...`, páginas de `help/app-store-connect` y `help/account` por HTML, App Review Guidelines), `developer.android.com` (HTML), y los hilos del foro de Apple vía WebFetch.

Bloqueados o no accesibles desde el entorno (no se pudo citar de primera mano):

| Dominio / ruta | Resultado | Consecuencia |
|---|---|---|
| `www.rfc-editor.org`, `datatracker.ietf.org` | Bloqueados por el proxy de salida (EGRESS_BLOCKED / conexión rechazada) | RFC 8628 (Device Authorization Grant) y RFC 7636 (PKCE) sólo se citan a través de la guía oficial de Android que los menciona. No se ha leído el texto de los RFC. |
| `support.google.com/googleplay/android-developer/...` (answers 11926878, 9006925, 9842756) | Conexión fallida | Sin ayuda de Play Console: el carácter permanente del package name en Play, y la obligación de AAB se contrastan sólo con `developer.android.com`. |
| `developer.apple.com/help/account/provisioning-profiles/provisioning-profiles-overview` (y variantes) | 404 | Para perfiles se usa la página "Create an App Store Connect provisioning profile". |
| Apple JSON `watchos-apps/distributing-your-watchos-app`, `xcode/configuring-a-watchos-app` | 404 | No existen en esas rutas. |
| `developer.android.com/training/wearables/apps/distribute`, `.../auth-wear-sign-in-ux` | 404 | Se usa `training/wearables/packaging` y `training/wearables/apps/auth-wear`. |

Los hilos de foro (developer.apple.com/forums) son respuestas de personal de Apple ("Frameworks Engineer, Apple Staff", "DTS Engineer"), no documentación formal; se señalan como tales.

## 1. Apple: watch-only frente a independiente con app iOS

### 1.1 Qué dice Apple

Fuente principal: https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps

- "create an independent watchOS app that doesn't require a companion iOS app for iPhone. You can do this in two ways: Create a watch-only app that doesn't have a companion iOS app. Create a watchOS app that has a companion iOS app, but people can install and run independently of the companion."
- "Create a watch-only app for apps that only run on Apple Watch. If you have watchOS and iOS apps that are substantially similar, release them as companion apps."
- "If you create a watchOS app with a companion iOS app, the in-app purchases are universal."
- Sobre el stub de un watch-only: "The root target is a stub that acts as an iOS wrapper for your project. Xcode needs this stub to properly handle your watch-only app, and uses it to: Set the root bundle identifier. The system uses this bundle identifier for Universal Purchase and cross-device communication, such as Device Discovery. Package your app for distribution to the App Store." Y: "Xcode doesn't create an iOS executable for the stub. When someone installs your watch-only app, nothing installs on the paired iPhone."
- Independiente con companion: "The system downloads and installs the watchOS app directly to Apple Watch for both dependent and independent apps." Se convierte con la opción "Supports Running Without iOS App Installation".
- Independencia funcional: "Independent watchOS apps can't rely on the WatchConnectivity framework to transfer data or files from a companion iOS app", y "the independent watchOS app can't use Watch Connectivity as its main source of data".

Claves de Info.plist (https://developer.apple.com/documentation/bundleresources/information-property-list/):
- `WKWatchOnly`: "When you set the value of this key to YES, the app is only available on Apple Watch, with no related iOS app."
- `WKRunsIndependentlyOfCompanionApp`: "When you set the value of this key to YES, the app doesn't need its iOS companion app to operate properly. Users can choose to install the iOS app, the watchOS app, or both."
- `WKCompanionAppBundleIdentifier`: "The bundle ID of the watchOS app's companion iOS app."

App Store Connect:
- "Watch-only apps are considered part of the iOS platform in App Store Connect." (https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- "Watch-only apps can't be part of a universal purchase." (https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms). Esa frase está en el contexto de añadir plataformas (macOS, tvOS, visionOS) al registro.
- "iOS screenshots are also required for apps with an iOS component, but not for watch-only apps." (https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information)
- Bundle ID inmutable: "Bundle ID ... You can't change this property after you upload a build." y SKU: "You can't change the SKU after you add the app to your account." (https://developer.apple.com/help/app-store-connect/reference/app-information). También: "After you upload a build to App Store Connect, you can't change the bundle ID or delete the associated explicit App ID in your developer account." (https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier)

### 1.2 Requisito de prefijo del bundle id

https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier: "For watchOS apps that have a companion iOS app in the same project, the embedded WatchKit app and WatchKit extension targets must have the same bundle ID prefix as the iOS app. The WatchKit app must have the format [Bundle ID].watchkitapp, and the WatchKit extension must have the format [Bundle ID].watchkitextension."

Apple Staff (foro, aceptada) https://developer.apple.com/forums/thread/666417, sobre un watch-only: bundle ids `com.mycompanyname.Whale-Watch`, `...Whale-Watch.watchkitapp`, `...Whale-Watch.watchkitapp.watchkitextension`; "The 'watchkitapp' and 'watchkitextension' parts are non-negotiable, and all three targets must have the same root bundleID". Además, "Watch-only apps are submitted to the iOS App Store."

Observaciones para este repo:
- `watchos/project.yml` define un único target watchOS (`WKApplication: true`, `WKWatchOnly: true`) con id `org.caminoseguro.watch`, sin target stub iOS y sin sufijo `.watchkitapp`. La plantilla de Apple para watch-only crea un stub (ver cita anterior). Si el modelo de un solo target sin stub se acepta en App Store Connect: **NO VERIFICADO** con las fuentes accesibles. Hay que probarlo con un archivo real en un Mac antes de reservar nada irreversible, o adoptar la estructura de Apple (stub + app watch).
- Para extensiones (widgets) no se leyó una regla textual vigente; la convención es que el id de la extensión tenga como prefijo el de su app contenedora. NO VERIFICADO textualmente; validar al archivar.

### 1.3 ¿Se puede convertir un watch-only en companion de una app iOS sin cambiar identidad?

Apple Staff (https://developer.apple.com/forums/thread/672264): "When you create a watch-only app from a template, the project is specifically set up to make it watch only. You'll need to undo some of that plumbing to add an iOS companion app." Pasos: (1) "Make sure the bundle identifier of your new iOS target is the same as the one currently shown in the 'stub' target"; (2) añadir `WKCompanionAppBundleIdentifier` con el bundle id de la app iOS; (3) quitar `WKWatchOnly`; (4) añadir `WKRunsIndependentlyOfCompanionApp = YES`; (5) "Delete the 'stub' target."

INFERENCIA, soportada por las citas: el registro de App Store Connect (Apple ID, SKU, bundle id) se identifica por el bundle id raíz, que en un watch-only es el del stub, y las compilaciones se asocian por bundle id ("Each time you upload a build, the bundle ID and version number ... are used to associate the build with the app and version record", https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds). Por tanto, si el stub ya usa el id definitivo de la futura app iOS, la identidad se conserva. No hay documentación oficial que prometa explícitamente la conservación de reseñas o compras en esa conversión: **NO VERIFICADO**. Las compras in-app: "si tiene companion, son universales"; ninguna cita las migra entre registros.

Lo que sí es irreversible y está documentado: cambiar de registro. "Multiple app records ... you can't merge them ... Ratings and reviews are not transferred to the new product page." (add-platforms). Es el escenario a evitar: dos registros (uno `org.caminoseguro.watch`, otro `com.caminoseguro.app`).

### 1.4 Qué recomienda Apple

"Create a watch-only app for apps that only run on Apple Watch. If you have watchOS and iOS apps that are substantially similar, release them as companion apps." Para este producto, el futuro móvil (Capacitor) es una experiencia distinta (PWA envuelta), no "substancialmente similar"; ambos caminos son válidos según Apple. Apple añade: "To ensure the best experience for all Apple Watch users, create an independent watchOS app that doesn't require a companion iOS app" (satisfecho por ambos).

## 2. Apple: publicar el reloj primero sin duplicar productos

Opciones:

| Opción | Descripción | Pros | Contras | Irreversibilidad |
|---|---|---|---|---|
| A. Watch-only con id definitivo | Registro en App Store Connect con bundle id raíz `com.caminoseguro.app` (stub), reloj `com.caminoseguro.app.watchkitapp`. Más tarde se añade la app iOS al mismo id, siguiendo los pasos del Apple Staff (§1.3). | Una sola identidad; no exige iOS ahora; ajustado a "apps que sólo corren en Watch". | Hay que reestructurar el proyecto (quitar WKWatchOnly, borrar stub) al llegar iOS; reseñas/compras en la conversión no documentadas; "Watch-only apps can't be part of a universal purchase" (sólo afecta si se quisieran más plataformas, p. ej. macOS). La primera versión iOS exigirá capturas iOS. | Alta sobre el id (inmutable tras primera subida). La conversión en sí es reversible a nivel de proyecto. |
| B. iOS mínimo + reloj independiente | App iOS mínima (contenedor) con `com.caminoseguro.app` y reloj independiente `.watchkitapp` con `WKRunsIndependentlyOfCompanionApp = YES`. Luego la app Capacitor sustituye al binario mínimo en el mismo registro. | Estructura final desde el primer día; compras universales; sin conversión. | Publicar un binario iOS mínimo contra las guidelines de App Review (riesgo de rechazo por funcionalidad mínima; **NO VERIFICADO** aquí, hay que leer 4.2 antes), mantenimiento de un binario sin valor. Hay que construirlo (no existe). | Alta sobre el id; además publica una app iOS pública que no aporta nada. |
| C. Reservar id, publicar el reloj más adelante junto a la app | No subir nada hasta que haya app iOS. | Máxima limpieza. | Retrasa el reloj; mantiene bloqueos externos. | Mínima. |
| D. Mantener `org.caminoseguro.watch` (placeholder) | Publicar con el id actual. | Sin cambios. | Crea un registro separado; luego no se puede fusionar ("you can't merge them", reseñas no se transfieren); el id raíz sería el del reloj. | Máxima: duplicación de producto garantizada. |

Sobre la pregunta "¿se puede publicar la app watch en un registro cuyo binario iOS es mínimo?": sí es una estructura legítima (watchOS con companion y `WKRunsIndependentlyOfCompanionApp`; "Users can choose to install the iOS app, the watchOS app, or both."). Que App Review acepte un iOS mínimo: no hay base citada; evitar (opción B) salvo que haya funcionalidad real.

Sobre "¿publicar watch-only y luego añadir iOS al mismo registro?": respaldado por el Apple Staff (§1.3) para el proyecto, y por la lógica de asociación por bundle id para el registro, pero no por una página oficial de App Store Connect que lo describa de principio a fin. Por eso es concluyente sólo en cuanto al proyecto; el comportamiento del registro es INFERENCIA.

**Recomendación menos irreversible: opción A, condicionada a** (1) confirmar que el equipo controla el dominio inverso `com.caminoseguro` (Apple: "use your organization's domain name as the organization ID to ensure that the bundle ID is unique", https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), y (2) hacer un archivo de prueba y una validación ("Validate App") antes de la primera subida a TestFlight. Hasta tener esas dos confirmaciones, no se sube ninguna compilación (la subida es el punto sin retorno: "After you upload your first build to App Store Connect, you can't change the bundle ID"). Registrar el App ID explícito y crear el registro vacío en App Store Connect es el paso de menor compromiso; sigue sin ser trivial de revertir (el bundle id del registro no se cambia tras subir un build).

Identificadores PROPUESTA (no confirmados):

| Elemento | Valor |
|---|---|
| Bundle id raíz iOS (futuro) / stub | `com.caminoseguro.app` |
| App watchOS | `com.caminoseguro.app.watchkitapp` |
| Extensión de widgets | `com.caminoseguro.app.watchkitapp.widgets` |
| App Group | `group.com.caminoseguro.app` (Apple: "A container ID must begin with group. and then a custom string.") |
| URL scheme | `caminoseguro` (ya en el repo) |
| Android applicationId | `com.caminoseguro.app` (mismo para móvil y reloj, §5) |

## 3. Apple: firma

Citas de https://developer.apple.com/help/account/certificates/certificates-overview:
- "Development certificates belong to individuals." "Distribution certificates belong to the team and only one type of each distribution certificate ... is allowed per team. Only the Account Holder or Admin role can create distribution certificates."
- Apple Development: "Run an iOS, iPadOS, macOS, tvOS, visionOS, watchOS app on devices and use certain app services during development." Apple Distribution: "Distribute ... on designated devices for testing or submit it to App Store Connect."
- "Do not share Apple Certificates outside of your organization."

| Concepto | Qué es | Quién lo crea |
|---|---|---|
| Certificado Apple Development | Identidad personal para ejecutar en dispositivos | Cada desarrollador (Xcode) |
| Certificado Apple Distribution | Identidad del equipo para TestFlight/App Store | Account Holder o Admin |
| App ID explícito | "An App ID identifies your app in a provisioning profile." Las capacidades activadas "serve as an allow list". "Beginning with Xcode 11.4, a single App ID can be used to build iOS, macOS, tvOS, and watchOS apps." (https://developer.apple.com/help/account/manage-identifiers/register-an-app-id) | Account Holder o Admin |
| Perfil de aprovisionamiento | Une App ID + certificado (+ dispositivos). El de App Store "contains a single distribution certificate" y requiere "an app record registered with an explicit App ID" (https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile). Con firma automática: "Xcode manages distribution provisioning profiles for you." | Xcode (automático) o Admin |
| Capacidades | Para el target watchOS: "the capabilities available are app groups and background modes" (https://developer.apple.com/help/account/reference/supported-capabilities-watchos). Sign in with Apple, Keychain sharing, Push notifications, Associated domains y otras figuran en la tabla de watchOS. | Se añaden en Xcode a cada target; el App ID las habilita |
| App Group | "You need to register app groups for iOS, iPadOS, tvOS, visionOS, and watchOS apps." (https://developer.apple.com/documentation/xcode/configuring-app-groups). Registro: https://developer.apple.com/help/account/manage-identifiers/register-an-app-group | Account Holder o Admin, o desde Xcode |
| Ubicación en segundo plano | No es un permiso de App ID: va como `UIBackgroundModes: location` en Info.plist (ya en `project.yml`) más textos `NSLocation...UsageDescription`. El capability "Background modes" se añade en Xcode. Guideline 2.5.4: "Multitasking apps may only use background services for their intended purposes: VoIP, audio playback, location, task completion, local notifications, etc." y 5.1.5 exige que la ubicación sea "directly relevant to the features" (https://developer.apple.com/app-store/review/guidelines/). | Equipo (repo + Xcode) |
| Clave API de App Store Connect | "Calls to the API require JSON Web Tokens (JWT) for authorization; you obtain keys to create the tokens from your organization's App Store Connect account." Clave de equipo: "To generate team keys, you must have an Admin account". "The private key is available for download a single time". "Don't share your keys, store keys in a code repository, or include keys in client-side code." (https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) | Admin de App Store Connect. Sólo necesaria si se automatiza (fastlane/CI, Transporter por JWT) |

Datos que el equipo debe comunicar al repo, sin secretos: Team ID, el bundle id raíz confirmado, los App IDs registrados (nombres), el nombre del App Group, el SKU elegido (identificador, no secreto) y confirmación de qué capacidades quedaron habilitadas. Si se automatiza: Key ID e Issuer ID de la clave API (identificadores), nunca el `.p8`.

Reglas: nunca subir `.p12`, `.p8`, `.mobileprovision` ni keystores al repo; si se automatiza, usar secretos cifrados del CI (GitHub Actions secrets) y firma automática o `match`-style con almacenamiento cifrado fuera del repo. Con firma automática en Xcode no hace falta clave API para una primera subida manual.

## 4. Apple: autenticación en un reloj sin teclado

Fuente: https://developer.apple.com/documentation/watchos-apps/authenticating-users-on-apple-watch. "If your app requires an account, users must be able to create it and sign in on the watch." Opciones literales: "Create an app that doesn't require user accounts ... or use CloudKit"; "Authenticate users with Sign In with Apple"; "Create custom sign-in and sign-up forms" (con `TextField`/`SecureField`, tipo de contenido, autorrelleno y dominios asociados; "watchOS provides an autofill suggestion for oneTimeCode fields after receiving an SMS message").

| Opción | Cita / disponibilidad | Requisitos para el contrato |
|---|---|---|
| Sign in with Apple | `ASAuthorizationAppleIDProvider` watchOS 6.0+; `WKInterfaceAuthorizationAppleIDButton` ("Use the authorization button to initiate Sign in with Apple on Apple Watch") | Backend debe aceptar el identity token de Apple y validarlo; vincular con cuentas existentes de la PWA. Guideline 4.8: si hay login de terceros como login principal, hay que ofrecer una alternativa equivalente. |
| `ASWebAuthenticationSession` (OAuth en navegador del sistema) | watchOS 6.2+: "Use an ASWebAuthenticationSession instance to authenticate a user through a web service" | OAuth 2.0 Authorization Code + PKCE, redirect con esquema propio; cliente público sin secreto. |
| Formularios propios | Permitido por Apple con autorrelleno y Continuity Keyboard. Nota: Google exige lo contrario en Wear OS (WO-P6), por lo que no es multiplataforma. | Endpoint de usuario/contraseña, OTP por SMS/correo; limitación de tasa. |
| OAuth Device Authorization Grant (RFC 8628) | No es una API de Apple; Apple no lo documenta. Android sí lo cita como válido (§6). RFC no leído por bloqueo del dominio. | Backend debe exponer endpoint de autorización de dispositivo, código de usuario, URI de verificación, polling con `interval`, errores de RFC. Funciona igual en ambos relojes. |
| WatchConnectivity | "Use this framework to transfer data between your iOS app and the WatchKit extension of a paired watchOS app." Para apps independientes: no puede ser la fuente principal. | Sólo aplicable cuando exista app iOS; nunca como única vía. |
| Sin cuenta (modo invitado) | Citado arriba (primera opción) | El contrato debe indicar qué endpoints funcionan sin cuenta. |

No se elige: depende del backend.

## 5. Android / Wear OS: distribución

Citas de https://developer.android.com/training/wearables/packaging:
- "Wear OS APKs are separate from mobile APKs, and are uploaded and updated independently from within the Play Console."
- "Since a watch APK's version code must be unique across all form factors, we recommend that its version code scheme is independent of any other form factor in your Play Console."
- "If you have a phone APK in addition to a watch APK, you must use the Multi-APK delivery method to manage both."
- "<uses-feature android:name="android.hardware.type.watch" />"; "Don't set the required attribute to false for this element, because this results in a single APK across devices that run Android and Wear OS, which isn't a supported configuration."
- Standalone: "A standalone app is fully usable without a paired phone. All of its core functions, such as authentication, work locally on the watch." con `com.google.android.wearable.standalone`.
- Mismo package: "If you have an existing mobile app, verify that you have used the same package name for your Wear OS app. We recommend that you use the same Play Store listing as your mobile app, because this improves the discoverability of your Wear OS app by linking it to the reviews and ratings of your mobile app."
- Consola: "Test and release ... Advanced Settings, select the Form factors tab, and click Add form factor. Click Wear OS". Para publicar: "you must complete closed testing"; luego "opt in to Wear OS and agree to the review policy", y "Start rollout". Hay que mencionar "Wear OS" en la ficha y subir al menos una captura en un dispositivo Wear.

Calidad (https://developer.android.com/docs/quality-guidelines/wear-app-quality): "Failing to comply with all of the requirements might lead to rejection of your app submission from the Play Store."
- WO-G7: "If your Wear OS app has an accompanying phone app, you must use the same package name and app signing key for your Wear app and phone app."
- WO-P6: "Your app must not ask the user to input a username or password directly on the Wear OS device."
- WO-V4: ongoing activity: "When your app is performing a long-running operation ... you must use an OngoingActivity or Live Update notification." Relevante: la etapa en curso con servicio de ubicación en primer plano (`wearos/app/src/main/AndroidManifest.xml` declara `FOREGROUND_SERVICE_LOCATION`).
- WO-V13: fondo negro; WO-V14: fuente mínima 12sp/10sp; WO-V2: objetivos táctiles de 48x48dp.
- "As of September 15, 2026, all Wear OS apps must support 64-bit devices." Revisar que no haya librerías nativas sólo de 32 bits.
- WO-G8: si hay funciones de pago, credenciales de prueba en la consola.

Nivel de API objetivo (https://developer.android.com/google/play/requirements/target-sdk): "Starting August 31 2026: New apps and app updates must target Android 16 (API level 36) or higher to be submitted to Google Play; except for Wear OS and Android Automotive OS apps, which must target Android 15 (API level 35) or higher". Posible prórroga "to November 1, 2026". `wearos/gradle/libs.versions.toml` usa `targetSdk = "35"`: cumple el mínimo actual para Wear. (La página de calidad aún dice "API level 34 or higher"; prevalece la fecha más reciente de la página de requisitos de Play. Releer antes de publicar, porque las fechas cambian.)

Formato y firma:
- "From August 2021, new apps are required to publish with the Android App Bundle on Google Play." (https://developer.android.com/guide/app-bundle). "Play App Signing is required for new apps so that they can use AABs." (https://developer.android.com/guide/app-bundle/faq)
- "When releasing using Android App Bundles, you need to sign your app bundle with an upload key before uploading to the Play Console, and Play App Signing takes care of the rest." "Tip: ... make sure your app signing key and upload key are different." Si se perdiera la clave de subida se puede pedir un reinicio, "Because your app signing key is secured by Google". "If you want to use the same signing key across multiple stores, make sure to provide your own signing key when you configure Play App Signing". (https://developer.android.com/studio/publish/app-signing). La misma página avisa: "If you are building a Wear OS app, the process for signing the app can differ from the process described on this page."
- Identidad: "Once you publish your app, you should never change the application ID. If you change the application ID, Google Play Store treats the upload as a completely different app." (https://developer.android.com/build/configure-app-module)
- Multi-APK: "they share the same application listing on Google Play and must share the same package name and be signed with the same release key." (https://developer.android.com/google/play/publishing/multiple-apks)

Conclusión Android: el `applicationId` debe ser el definitivo de la app móvil **desde la primera subida**, porque WO-G7 exige mismo package y misma clave de firma, y cambiarlo crea otra app. Si el equipo reserva `com.caminoseguro.app` para Capacitor, el reloj debe usar ese mismo id (hoy `wearos/app/build.gradle.kts` tiene el placeholder `org.caminoseguro.watch`). Se puede publicar primero la AAB de Wear en una ficha creada con ese package y añadir después la AAB móvil (otra subida, otro código de versión). Que Play Console permita una ficha con sólo form factor Wear OS: la guía de empaquetado describe añadir el form factor Wear OS a una ficha; no prohíbe que sea el único. NO VERIFICADO el comportamiento exacto con support.google.com bloqueado.

## 6. Android / Wear OS: autenticación

Fuente: https://developer.android.com/training/wearables/apps/auth-wear
- "Credential Manager is the recommended API for authentication on Wear OS." Mecanismos: "Passkeys, Passwords, Federated Identities (such as Sign in with Google)". Limitaciones: "Credential Manager is available on Wear OS 3 and higher. Credentials cannot be created on Wear OS. Neither restore credentials nor hybrid sign-in flows are supported."
- Modo invitado: "Don't require authentication for all functionality."
- Alternativas: "There are two other acceptable authentication methods for Wear OS apps: OAuth 2.0 (either variant), and Mobile Auth Token Data Layer Sharing."
- Data Layer: "Your Wear OS app must offer at least one other authentication method, because this option works only on Android-paired watches when the corresponding mobile app is installed. Provide an alternate authentication method for users who don't have the corresponding mobile app or whose Wear OS device is paired with an iOS device."
- OAuth: "Authorization Code Grant with Proof Key for Code Exchange (PKCE), as defined in RFC 7636" con `RemoteAuthClient` (la autorización se presenta "in a web browser on the user's mobile phone"; la redirección es `https://wear.googleapis.com/3p_auth/<package>?code=...`); y "Device Authorization Grant (DAG), as defined in RFC 8628" con `RemoteActivityHelper` para abrir el URI de verificación en el móvil. "If you have an iOS app, use universal links to intercept this intent in your app".
- Data Layer sólo existe con móvil Android: "This API is only available on Wear OS watches and paired Android devices." (https://developer.android.com/training/wearables/data/overview)
- Con cuentas infantiles: "you cannot use Google Sign-in because it's not compatible with child accounts."

Nota: PKCE vía `RemoteAuthClient` y la redirección `wear.googleapis.com/3p_auth/<package>` dependen del package name; es otra razón para fijar el `applicationId` antes de registrar el cliente OAuth.

## 7. Requisitos del contrato de backend para autenticación del reloj

El contrato real está ausente (`contracts/README.md`). Para desbloquear, debe especificar como mínimo:

1. Si existe modo sin cuenta y qué endpoints permite (Apple y Google recomiendan invitado).
2. Método(s) de sign-in soportado(s) por el servidor, y su coherencia entre plataformas. Dado WO-P6 (Wear OS no pide usuario/contraseña), el flujo común realista es uno de estos, a decidir por el backend: Device Authorization Grant (RFC 8628), o PKCE con navegador del teléfono; más Credential Manager en Wear OS y Sign in with Apple/ASWebAuthenticationSession en watchOS como accesos nativos.
3. Si hay Device Authorization Grant: URL del endpoint de dispositivo, `client_id` público por plataforma, scopes, formato y caducidad del código de usuario, URI de verificación, intervalo mínimo de polling, y errores (`authorization_pending`, `slow_down`, `access_denied`, `expired_token`).
4. Si hay PKCE: endpoint de autorización y de token, redirect URIs permitidos (incluida la de Wear `https://wear.googleapis.com/3p_auth/<applicationId>`, y el esquema propio en watchOS), `S256` obligatorio, sin secreto de cliente.
5. Validación de tokens de Apple (identity token, vinculación con cuenta existente) y de Google (si se usa Sign in with Google vía Credential Manager). Guideline 4.8 si hay login de terceros principal.
6. Ciclo de vida del token en el reloj: duración de acceso, refresh token rotatorio, revocación, almacenamiento (Keychain / Android Keystore), cierre de sesión y borrado de cuenta (comprobar guideline 5.1.1 sobre eliminación de cuenta antes de enviar a revisión; no leída aquí).
7. Registro de identidades de cliente: App ID/Team ID de Apple, package name y huella SHA-256 del certificado de firma de Play (el de la clave de firma de la app, no la de subida) si el backend las verifica.
8. Idempotencia (`eventId`) y semántica de reintento, ya pedidas en `contracts/README.md`.
9. Qué ocurre si la cuenta ya existe en la PWA (enlazado de identidades).

## 8. Checklist de pasos externos

### Responsabilidad del equipo (no ocurre en el repo)

Apple
- [ ] Inscripción en el Apple Developer Program (organización) y Account Holder identificado; acuerdos de "Business" firmados ("You can't add an app to your account until the Account Holder signs the latest agreement").
- [ ] Confirmar dominio inverso y bundle id raíz definitivo (PROPUESTA `com.caminoseguro.app`).
- [ ] Registrar App ID explícito para raíz, app watch y extensión de widgets, con capacidades (App Groups; Background modes se añade en Xcode; Sign in with Apple y Keychain sharing sólo si el contrato las exige).
- [ ] Registrar App Group (PROPUESTA `group.com.caminoseguro.app`).
- [ ] Crear certificado Apple Distribution (Account Holder/Admin); cada dev su Apple Development.
- [ ] Crear registro en App Store Connect (plataforma iOS: watch-only cuenta como iOS), SKU, nombre, categoría, política de privacidad, clasificación por edad, capturas de Apple Watch.
- [ ] Probar archivo y validación con la estructura elegida (stub o no) antes de la primera subida a TestFlight.
- [ ] TestFlight interno primero; externo después (requiere revisión de beta).
- [ ] Opcional: clave API de App Store Connect (rol mínimo) para CI, guardada como secreto cifrado.
- [ ] Entregar al repo: Team ID, bundle ids registrados, nombre del App Group (sin secretos).

Google Play
- [ ] Cuenta de desarrollador de Google Play y verificación requerida en consola.
- [ ] Crear la app con `applicationId` definitivo (PROPUESTA `com.caminoseguro.app`); activar Play App Signing.
- [ ] Generar y custodiar la clave de subida (keystore fuera del repo); registrar su certificado.
- [ ] Ficha: añadir form factor Wear OS, mencionar "Wear OS", capturas Wear (1:1), política de privacidad, formulario de seguridad de datos, declaración de permisos de ubicación y servicio en primer plano.
- [ ] Pista interna, luego prueba cerrada (obligatoria antes de producción según la guía de empaquetado), informe previo al lanzamiento, aceptación de la política de revisión de Wear OS.
- [ ] Entregar al repo: applicationId confirmado y, si el backend lo pide, huella SHA-256 del certificado de firma de Play.

### Lo que está o debe estar en el repo

- [x] Proyecto watchOS (XcodeGen) y proyecto Wear OS con firma desactivada/placeholder; CI de compilación.
- [ ] Sustituir placeholders (`org.caminoseguro.*`, App Group, `applicationId`) por los confirmados, en un único cambio, tras la confirmación del equipo.
- [ ] Decidir y reflejar la estructura watch-only (stub o no) tras la prueba de archivo.
- [ ] Entitlements y capacidades propias del App ID del equipo (ver "qué no hacer").
- [ ] Revisar `targetSdk` (hoy 35, mínimo para Wear), compatibilidad 64-bit y requisitos WO-V*.
- [ ] Configuración de firma de release de Android leyendo claves desde variables de entorno o secretos del CI, nunca ficheros versionados.
- [ ] Textos de ficha (descripción con funcionalidad en reloj, privacidad coherente con el uso real de ubicación) preparados como documentos, no como secretos.

## 9. Qué NO hacer

- No subir `.p12`, `.p8`, `.mobileprovision`, `.jks`/`.keystore` ni contraseñas al repo; ni claves API de App Store Connect ("store keys in a code repository" está desaconsejado literalmente).
- No pedir ni crear un App ID/perfil "genérico" de watchOS ni usar un App ID comodín para publicar: el perfil de App Store exige "an explicit App ID".
- No reutilizar entitlements, App Groups, esquemas URL, bundle ids ni identificadores de otros equipos o apps (por ejemplo copiados de ejemplos de Apple/Google o de otra organización): cada App Group, App ID y huella debe ser del equipo propio.
- No subir ninguna compilación a App Store Connect ni a Play antes de confirmar el id definitivo: tras la primera subida el bundle id (Apple) y el application id (Google) son prácticamente inamovibles.
- No crear un segundo registro/ficha "para el reloj" con id distinto al de la futura app: no se pueden fusionar y se pierden reseñas.
- No inventar endpoints ni flujos de auth: siguen bloqueados hasta que exista el contrato.
- No pedir usuario y contraseña directamente en Wear OS (WO-P6).
- No describir la app como servicio de emergencias: la guideline 5.1.5 indica que las APIs de ubicación "shouldn't be used to provide emergency services" (revisar el texto de la ficha y la función SOS del repo con ese criterio antes de enviar).
- No dar por documentado lo marcado NO VERIFICADO.

## 10. ¿Publicar el reloj primero o con la app principal?

Dependencias:
1. **Contrato de backend ausente.** Hoy la versión Release usa `BlockedCaminoApi`: no hay sincronización real ni autenticación. Una publicación pública ahora sería una app demo con datos de fixtures "no sirven para orientarse en el Camino real" (spec §0), con riesgo de rechazo por funcionalidad insuficiente y de reseñas negativas imposibles de borrar (las reseñas pertenecen al registro).
2. **App iOS/Capacitor inexistente.** No hay binario que ponga en el registro; la opción B (iOS mínimo) añade riesgo de revisión sin valor.
3. **Irreversibilidad del identificador.** Lo que no se puede deshacer es el id (Apple: tras la primera subida; Google: `applicationId`; ambos crean otra app si cambian) y la existencia de dos registros (no se fusionan). Esto sí puede resolverse hoy, sin publicar nada.

Recomendación:
1. **No publicar el reloj públicamente todavía.** Esperar al menos a que el contrato permita autenticación y sincronización reales.
2. **Sí fijar ya la identidad**, en cuanto el equipo confirme dominio y propiedad: bundle id raíz `com.caminoseguro.app` y `applicationId = com.caminoseguro.app` (PROPUESTA), registrar App IDs y App Group, y crear el registro de App Store Connect sin subir binarios. Es lo único que evita la duplicación futura.
3. **Distribuir en pruebas mientras tanto**: TestFlight interno y pista interna de Play con el id definitivo, para validar firma, estructura watch-only (con o sin stub) y calidad Wear OS. Ojo: la primera subida a TestFlight ya fija el bundle id; hacerla sólo con el id confirmado.
4. Cuando el contrato exista, publicar el reloj como watch-only con el id definitivo (opción A) si la app Capacitor sigue lejos; si la app Capacitor está cerca, publicar ambas a la vez y evitar la conversión.
5. Reabrir este documento cuando el equipo responda a los puntos NO VERIFICADO (archivo sin stub, conservación de reseñas en la conversión, ficha de Play sólo Wear).
