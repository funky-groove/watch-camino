import Foundation
import CaminoCore

/// Composición de dependencias de la app.
///
/// - Debug  (`#if DEBUG`): `MockCaminoApi` → la UI muestra la marca DEMO.
/// - Release: `BlockedCaminoApi` → imposible enviar datos a un servidor inventado (§11).
@MainActor
enum AppEnvironment {
    struct Dependencies {
        let controller: CaminoController
        let credentials: any CredentialStore
    }

    static func make() -> Dependencies {
        let catalog = loadStageCatalog()
        let pois = loadPoiSource()
        let api = makeApi()

        let sessionStore: any SessionStore
        let syncStore: any SyncQueueStore
        do {
            let directory = try StorageLocation.directory()
            sessionStore = FileSessionStore(directory: directory)
            syncStore = FileSyncQueueStore(directory: directory)
        } catch {
            // Sin disco no hay persistencia, pero la app sigue funcionando en memoria.
            Log.storage.error("Almacenamiento no disponible: \(Log.describe(error), privacy: .public)")
            sessionStore = InMemorySessionStore()
            syncStore = InMemorySyncQueueStore()
        }

        let controller = CaminoController(
            catalog: catalog,
            poiSource: pois,
            sessionStore: sessionStore,
            syncStore: syncStore,
            api: api,
            clock: SystemClock(),
            ids: SystemIdGenerator()
        )
        for error in controller.startupErrors {
            Log.storage.error("Estado persistido ilegible, se arranca en limpio: \(Log.describe(error), privacy: .public)")
        }
        return Dependencies(
            controller: controller,
            credentials: KeychainCredentialStore()
        )
    }

    static func makeApi() -> any CaminoApi {
        #if DEBUG
        return MockCaminoApi(latencySeconds: 0.6)
        #else
        return BlockedCaminoApi()
        #endif
    }

    private static func loadStageCatalog() -> FixtureStageCatalog {
        guard let url = Bundle.main.url(forResource: "stages", withExtension: "json") else {
            Log.app.fault("Falta stages.json en el bundle")
            return FixtureStageCatalog(stages: [])
        }
        do {
            return try FixtureStageCatalog(data: Data(contentsOf: url))
        } catch {
            Log.app.fault("stages.json ilegible: \(Log.describe(error), privacy: .public)")
            return FixtureStageCatalog(stages: [])
        }
    }

    private static func loadPoiSource() -> FixturePoiSource {
        guard let url = Bundle.main.url(forResource: "pois", withExtension: "json") else {
            Log.app.fault("Falta pois.json en el bundle")
            return FixturePoiSource(pois: [])
        }
        do {
            return try FixturePoiSource(data: Data(contentsOf: url))
        } catch {
            Log.app.fault("pois.json ilegible: \(Log.describe(error), privacy: .public)")
            return FixturePoiSource(pois: [])
        }
    }
}
