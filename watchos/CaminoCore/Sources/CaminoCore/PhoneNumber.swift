import Foundation

/// Validación del teléfono de un lugar (V1.1 §J): «Llamar» sólo aparece si es válido.
///
/// Válido:
/// - Internacional: `+` seguido de 8–15 dígitos.
/// - Español nacional: 9 dígitos que empiezan por 6, 7, 8 o 9.
///
/// Se toleran espacios, guiones, puntos y paréntesis como separadores visuales.
/// Los números cortos y de emergencia (112, 091, 062, 061, 016…) **no** son válidos aquí:
/// no son el teléfono de un lugar, y las llamadas de emergencia van por el flujo SOS.
public enum PhoneNumber {
    /// Número normalizado en formato E.164 (`+34612345678`), o `nil` si no es válido.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32 else {
            return nil
        }
        var hasPlus = false
        var digits = ""
        for (index, ch) in trimmed.enumerated() {
            if ch == "+" {
                guard index == 0 else {
                    return nil
                }
                hasPlus = true
            } else if ch.isASCII, ch.isNumber {
                digits.append(ch)
            } else if ch == " " || ch == "-" || ch == "." || ch == "(" || ch == ")" {
                continue
            } else {
                return nil
            }
        }
        if hasPlus {
            guard (8...15).contains(digits.count) else {
                return nil
            }
            return "+" + digits
        }
        guard isSpanishNational(digits) else {
            return nil
        }
        return "+34" + digits
    }

    /// `true` si `raw` es un teléfono de lugar válido (ver reglas arriba). `nil` → `false`.
    public static func isValid(_ raw: String?) -> Bool {
        guard let raw = raw else {
            return false
        }
        return normalized(raw) != nil
    }

    /// `tel:+34612345678` para un número válido; `nil` en otro caso.
    public static func telURL(_ raw: String) -> URL? {
        guard let number = normalized(raw) else {
            return nil
        }
        return URL(string: "tel:" + number)
    }

    private static func isSpanishNational(_ digits: String) -> Bool {
        guard digits.count == 9, let first = digits.first else {
            return false
        }
        return "6789".contains(first)
    }
}
