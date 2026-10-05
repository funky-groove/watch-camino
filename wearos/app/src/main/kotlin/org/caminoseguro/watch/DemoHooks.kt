package org.caminoseguro.watch

/**
 * Punto de entrada para escenarios de demostración y capturas. En `main` NO hace nada: [apply] es
 * null y ninguna build de Release lo rellena. Sólo el código de `src/debug` puede asignarlo (p. ej.
 * desde un inicializador de Debug) para preparar un escenario con el [AppContainer] ya creado
 * (preferencias, aviso de esfera, trayecto con datos simulados…).
 *
 * Contrato: `MainActivity.onCreate` lo invoca en el hilo principal, después de `container.boot()`
 * (que carga en segundo plano: espera `container.controller.ready` si lo necesitas) y antes de
 * `setContent`, una vez por cada creación de la actividad. Debe ser rápido y no lanzar: una excepción
 * se registra y se ignora (la app sigue).
 */
object DemoHooks {
    @Volatile
    var apply: ((AppContainer) -> Unit)? = null

    /**
     * Única URI de navegación que `MainActivity` acepta en su Intent (F-05): la que el instalador
     * de escenarios Debug pone para abrir una ruta (`android-app://androidx.navigation/<ruta>`).
     * Null en main/Release y en Debug sin escenario: entonces se descarta TODO `intent.data` y los
     * extras de deep link de Navigation, venga de donde venga.
     */
    @Volatile
    var allowedNavUri: String? = null
}
