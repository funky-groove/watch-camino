# Viabilidad de un botón SOS (llamada al 112) en la app de Apple Watch

Fecha de investigación: 2026-10-05. Solo fuentes oficiales de Apple.
Leyenda: [V] verificado con texto literal de fuente oficial; [P] respaldado solo por fragmento/resumen de búsqueda (no se pudo abrir la página: el proxy bloquea support.apple.com); [I] inferido; [NV] no verificado.

## 1. API pública para iniciar una llamada en watchOS

- [V] `WKApplication.openSystemURL(_:)`, watchOS 7.0+, no deprecado.
  Fuente: https://developer.apple.com/documentation/watchkit/wkapplication/opensystemurl(_:) (vía JSON de documentación).
  - Discusión: "Use this method to initiate phone calls or send messages. The URL you open is sent to the appropriate system app for handling, at which point the user can choose whether to continue the operation."
  - Parámetro: "A URL that supports the `tel:` or `sms:` scheme."
  - Implica: la llamada NO es silenciosa; el usuario confirma en la app del sistema.
- [V] Foro oficial, ingeniero de Apple (Frameworks Engineer), sobre SwiftUI `Link` en watchOS: "On watchOS, Link can open Universal Links that launch apps on your watch. It also works with other URL schemes like tel: for starting a phone call." https://developer.apple.com/forums/thread/650324
- [V] Foro, app independiente: abre una pantalla de confirmación y luego llama; en watchOS 6.2.6 aparecían 2 pantallas de confirmación (bug reportado; el ingeniero de Apple solo pidió Feedback Assistant, sin resolución visible). https://developer.apple.com/forums/thread/651030
- [V] CallKit figura con watchOS 9.0+ ("Display the system-calling UI for your app's VoIP services..."). https://developer.apple.com/documentation/callkit. Es para VoIP propio, no sirve para llamar a un número de emergencia por la red telefónica. [I]
- [NV] Si `WKExtension.openSystemURL` está deprecado: la doc actual lista `WKApplication.openSystemURL` como no deprecado; no se verificó la página de `WKExtension`.

## 2. Restricciones para números de emergencia (112/911) vía `tel:`

- [NV] No se encontró documentación oficial que prohíba ni que permita explícitamente `tel:112` / `tel:911` vía URL scheme en iOS/watchOS. Se dice explícitamente: no hay documentación oficial sobre el caso.
- [V] Foro (pregunta de un desarrollador, sin respuesta de Apple en el hilo): pide saltarse la confirmación con `tel://911` y entender si hay API para disparar SOS; "No answers are provided in the forum thread". https://developer.apple.com/forums/thread/115379
- [I] Por la documentación de `openSystemURL`, la llamada pasa por la app del sistema con confirmación del usuario; el comportamiento exacto con 112 (¿se enruta como llamada de emergencia real?, ¿confirmación distinta?) no está documentado. Habría que probarlo en dispositivo real, y no se puede probar contra un 112 real sin molestar al servicio.

## 3. Modelos de Apple Watch y condiciones para llamar

- [P] (fragmentos de support.apple.com/en-us/108300, /guide/watch/make-calls-apdc38d7a95e): con Wi-Fi o celular puede hacer y recibir llamadas; conmuta entre iPhone cercano, Wi-Fi y celular. Con Wi-Fi calling del operador (activado en el iPhone: "Add Wi-Fi Calling For Other Devices") puede llamar aunque el iPhone no esté cerca, mientras haya una red Wi-Fi que el iPhone haya usado antes.
- [NV] La lista exacta de modelos con celular y la disponibilidad por operador/país no se pudo leer. Regla [I]: modelos GPS-only dependen del iPhone cercano o de Wi-Fi calling; solo los modelos con celular activado con plan llaman por red móvil.

## 4. Emergency SOS nativo del Apple Watch

- [P] https://support.apple.com/en-us/108374 y https://support.apple.com/guide/watch/contact-emergency-services-apdfe3c02513/watchos (solo fragmentos de búsqueda): mantener pulsado el botón lateral hasta que aparece el control deslizante "Emergency Call"; arrastrarlo llama, o seguir manteniendo y tras una cuenta atrás llama automáticamente (ajuste "Hold Side Button to Dial" desactivable). Requiere conexión satelital, celular o Wi-Fi calling, desde el Watch o el iPhone cercano.
- [NV] Detalles de compartir ubicación con contactos de emergencia, e internacional (marcación al número local), no leídos literalmente. Verificar antes de afirmarlos en la UI.

## 5. ¿Puede una app de terceros invocar el SOS del sistema?

- [V] No hay API. DTS Engineer (Apple Staff) ante "Is there an SDK for using the emergency services on IOS?": "I think a feature request is well worth the effort here." (no ofrece API; otros usuarios: "No, there isn't"). https://developer.apple.com/forums/thread/704411
- [V] Sobre interceptar el botón SOS en Watch, solo respuestas de usuarios (no de Apple): "I would be really surprised if you could divert the SOS call from system to your own app." https://developer.apple.com/forums/thread/114036
- [I] Conclusión: no existe API pública documentada para disparar ni interceptar Emergency SOS.

## 6. HIG: mantener pulsado / acciones críticas

- [NV] No se pudo extraer texto de la HIG (developer.apple.com/design se renderiza con JS y la herramienta devolvió solo el título). No se afirma nada sobre HIG. Pendiente de revisión manual.

## Conclusión

(a) ¿Se puede llamar al 112 desde la app de forma fiable y verificable? **No verificable / solo parcialmente.**
- Sí existe vía oficial para iniciar una llamada con `tel:` (`WKApplication.openSystemURL` o `Link`) [V], pero requiere confirmación del usuario [V], depende de conectividad (celular, Wi-Fi calling o iPhone cerca) [P], y el comportamiento específico con 112 no está documentado [NV]. Puede haber una doble confirmación [V, bug 2020 sin resolución visible].
- No es "fiable" en el sentido de garantía de vida: no se puede asegurar que la llamada se establezca, ni verificar desde la app que se conectó.

(b) Recomendación:
- No presentar un botón "SOS" que prometa llamar al 112 como función de seguridad. Si se incluye algo, que sea un botón claramente etiquetado "Llamar al 112" que abra `tel:112` y deje al usuario confirmar; sin prometer cobertura. Si se pone, no usar mantener 3 s como sustituto de la confirmación del sistema (es [I] redundante: la confirmación del sistema ya existe).
- Opción más honesta y preferible: no implementar SOS propio e indicar en la app el SOS nativo (mantener botón lateral, [P]) como vía de emergencia, con aviso de que la app no sustituye a los servicios de emergencia y de que la cobertura depende del modelo/plan.
- Antes de lanzar: probar `tel:112` en un Watch real (con celular y con iPhone cercano) sin realizar la llamada, y revisar a mano las páginas de support.apple.com y la HIG (marcadas [P]/[NV]).
