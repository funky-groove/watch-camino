import Foundation

// Adaptadores de fixtures — shared/fixtures/*.json.
// DATOS DE DEMOSTRACIÓN con coordenadas aproximadas: no sirven para orientarse.

/// `StageCatalog` a partir de `shared/fixtures/stages.json`.
public final class FixtureStageCatalog: StageCatalog {
    public let stages: [Stage]
    /// Valor de `_notice` del fichero (aviso de datos de demostración).
    public let notice: String?

    private struct File: Decodable {
        let notice: String?
        let stages: [Stage]

        enum CodingKeys: String, CodingKey {
            case notice = "_notice"
            case stages
        }
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        self.stages = file.stages
        self.notice = file.notice
    }

    public init(stages: [Stage], notice: String? = nil) {
        self.stages = stages
        self.notice = notice
    }

    public func allStages() -> [Stage] {
        return stages
    }
}

/// `PoiSource` a partir de `shared/fixtures/pois.json`.
public final class FixturePoiSource: PoiSource {
    public let pois: [Poi]
    public let notice: String?

    private struct File: Decodable {
        let notice: String?
        let pois: [Poi]

        enum CodingKeys: String, CodingKey {
            case notice = "_notice"
            case pois
        }
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        self.pois = file.pois
        self.notice = file.notice
    }

    public init(pois: [Poi], notice: String? = nil) {
        self.pois = pois
        self.notice = notice
    }

    public func pois(forStage stageId: String) -> [Poi] {
        return pois.filter { $0.stageId == stageId }
    }
}
