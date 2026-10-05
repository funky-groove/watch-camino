import Foundation
import XCTest
@testable import CaminoCore

/// Acceso a los vectores de `shared/conformance/` y a `shared/fixtures/` directamente
/// desde el repositorio (no se copian): se sube desde este fichero hasta la raíz.
enum RepoFiles {
    struct NotFound: Error, CustomStringConvertible {
        let description: String
    }

    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let marker = dir.appendingPathComponent("shared").appendingPathComponent("conformance")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw NotFound(description: "No se encontró shared/conformance subiendo desde \(#filePath)")
    }

    static func data(_ relativePath: String) throws -> Data {
        var url = try repoRoot()
        for component in relativePath.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return try Data(contentsOf: url)
    }

    /// Lee un JSON de `shared/conformance/<name>` como diccionario.
    static func conformance(_ name: String) throws -> [String: Any] {
        let raw = try data("shared/conformance/\(name)")
        let object = try JSONSerialization.jsonObject(with: raw, options: [])
        guard let dict = object as? [String: Any] else {
            throw NotFound(description: "\(name) no es un objeto JSON")
        }
        return dict
    }
}

// MARK: - Lectura tolerante de valores JSON (NSNumber / NSNull)

func jsonDouble(_ value: Any?) -> Double? {
    if value is NSNull {
        return nil
    }
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    return nil
}

func jsonInt(_ value: Any?) -> Int? {
    guard let d = jsonDouble(value) else {
        return nil
    }
    return Int(d)
}

func jsonString(_ value: Any?) -> String? {
    if value is NSNull {
        return nil
    }
    return value as? String
}

func jsonArray(_ value: Any?) -> [Any] {
    return (value as? [Any]) ?? []
}

func jsonDict(_ value: Any?) -> [String: Any] {
    return (value as? [String: Any]) ?? [:]
}

func jsonStrings(_ value: Any?) -> [String] {
    return jsonArray(value).compactMap { $0 as? String }
}

func jsonPoint(_ value: Any?) -> GeoPoint {
    let d = jsonDict(value)
    return GeoPoint(lat: jsonDouble(d["lat"]) ?? .nan, lon: jsonDouble(d["lon"]) ?? .nan)
}

func epoch(_ seconds: Double) -> Date {
    return Date(timeIntervalSince1970: seconds)
}

func jsonPoi(_ value: Any?) -> Poi {
    let d = jsonDict(value)
    let category = PoiCategory(rawValue: jsonString(d["category"]) ?? "") ?? .landmark
    return Poi(
        id: jsonString(d["id"]) ?? "",
        stageId: jsonString(d["stageId"]) ?? "",
        name: jsonString(d["name"]) ?? "",
        category: category,
        location: jsonPoint(d["location"])
    )
}

/// `{lat, lon, acc, t}` → `LocationFix`.
func jsonFix(_ value: Any?) -> LocationFix {
    let d = jsonDict(value)
    return LocationFix(
        point: GeoPoint(lat: jsonDouble(d["lat"]) ?? .nan, lon: jsonDouble(d["lon"]) ?? .nan),
        accuracyMeters: jsonDouble(d["acc"]) ?? .nan,
        timestamp: epoch(jsonDouble(d["t"]) ?? 0)
    )
}

// MARK: - Dobles de test

/// `CaminoApi` que responde con un guion, en orden, y registra lo enviado.
final class ScriptedCaminoApi: CaminoApi {
    private var responses: [SendResult]
    private(set) var sent: [String] = []

    init(_ responses: [SendResult]) {
        self.responses = responses
    }

    var isDemo: Bool {
        return false
    }

    func send(_ event: SyncEvent) async -> SendResult {
        sent.append(event.eventId)
        if responses.isEmpty {
            XCTFail("El guion de respuestas se agotó en \(event.eventId)")
            return .blocked
        }
        return responses.removeFirst()
    }
}

func sendResult(fromCode code: String) -> SendResult {
    switch code {
    case "accepted": return .accepted
    case "retryable": return .retryable(reason: "test")
    case "permanent": return .permanent(reason: "test")
    case "unauthorized": return .unauthorized
    case "blocked": return .blocked
    default:
        XCTFail("Respuesta desconocida en el vector: \(code)")
        return .blocked
    }
}

func makeEvent(id: String, type: SyncEventType = .stageStarted, at seconds: Double = 0) -> SyncEvent {
    return SyncEvent(
        eventId: id,
        type: type,
        sessionId: "S-\(id)",
        occurredAt: epoch(seconds),
        payload: SyncPayload.started(stageId: "cf-sarria-portomarin", startedAt: epoch(seconds))
    )
}
