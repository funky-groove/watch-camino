package org.caminoseguro.watch.core

/**
 * Teléfono de un lugar — V1.1 §J. Válido si, quitando espacios, guiones, puntos y paréntesis, es
 * E.164 (`+` y 8–15 dígitos) o un número español de 9 dígitos que empieza por 6, 7, 8 o 9.
 * Los números cortos o de emergencia (112, 062…) no son válidos: «Llamar» no se ofrece.
 */
object PhoneNumber {
    private val E164 = Regex("""^\+\d{8,15}$""")
    private val SPANISH = Regex("""^[6-9]\d{8}$""")
    private val SEPARATORS = Regex("""[\s\-.()]""")

    fun isValid(raw: String?): Boolean = normalized(raw) != null

    /** Forma canónica (`+34…` para los números españoles de 9 dígitos) o null si no es válido. */
    fun normalized(raw: String?): String? {
        if (raw == null) return null
        val s = raw.replace(SEPARATORS, "")
        return when {
            E164.matches(s) -> s
            SPANISH.matches(s) -> "+34$s"
            else -> null
        }
    }

    /** `tel:+34…` o null si no es válido. */
    fun telUri(raw: String?): String? = normalized(raw)?.let { "tel:$it" }
}
