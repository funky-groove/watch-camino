import Foundation
import Security
import CaminoCore

/// `CredentialStore` en el Keychain (§11):
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` → nunca sale del dispositivo
/// ni va a copias de seguridad. En V1 nada escribe aquí: el flujo de vinculación
/// está BLOQUEADO por contrato (contracts/README.md).
final class KeychainCredentialStore: CredentialStore {
    struct KeychainError: Error {
        let status: OSStatus
    }

    private let service: String
    private let account: String

    init(service: String = "org.caminoseguro.watch.api", account: String = "device-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String) throws {
        try clear()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
