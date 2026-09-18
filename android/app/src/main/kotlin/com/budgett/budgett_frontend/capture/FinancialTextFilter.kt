package com.budgett.budgett_frontend.capture

import java.text.Normalizer

/**
 * Cheap gate that decides whether a message is worth writing to disk at all.
 *
 * This is a privacy measure as much as a performance one. The notification
 * listener sees every notification on the phone; without this filter, enabling
 * the feature would mean chat messages and emails landing in a queue that later
 * syncs to Supabase. A message only gets stored when it carries BOTH a money
 * amount and a banking action word.
 *
 * The real parsing happens in Dart (`ExpenseMessageParser`), which is
 * deliberately stricter. This side only has to be cheap and generous.
 */
object FinancialTextFilter {

    /** `$45.900`, `COP 1.234`, `USD 10.50`, `$ 12,50`. */
    private val amountPattern =
        Regex("""(?:\$|cop|usd|us\$)\s*\d""", RegexOption.IGNORE_CASE)

    private val actionWords = listOf(
        "compra", "compraste", "pagaste", "pago", "pagado",
        "retiro", "retiraste", "avance",
        "transferencia", "transferiste", "enviaste", "envio",
        "recibiste", "consignacion", "abono", "consignaron", "transfirieron",
        "cargo", "debito", "credito", "tarjeta",
        "aprobada", "aprobado", "rechazada", "declinada",
        "movimiento", "transaccion", "reverso", "devolucion",
    )

    /** Strips accents and lowercases, so "débito" matches "debito". */
    private fun normalize(input: String): String =
        Normalizer.normalize(input, Normalizer.Form.NFD)
            .replace(Regex("\\p{Mn}+"), "")
            .lowercase()

    fun looksFinancial(text: String): Boolean {
        if (text.isBlank()) return false
        if (!amountPattern.containsMatchIn(text)) return false
        val normalized = normalize(text)
        return actionWords.any { normalized.contains(it) }
    }

    /**
     * Whether a message from [sourceKey] should be captured.
     *
     * - Off entirely, or the source is blocked → no.
     * - An explicit allow-list exists → only those sources, and their messages
     *   skip the heuristic (the user vouched for the source).
     * - No allow-list (discovery mode) → any source, but only messages that
     *   look financial.
     */
    fun shouldCapture(
        text: String,
        sourceKey: String,
        enabled: Boolean,
        blocked: Set<String>,
        allowed: Set<String>,
    ): Boolean {
        if (!enabled) return false
        if (text.isBlank()) return false
        if (blocked.contains(sourceKey)) return false
        if (allowed.isNotEmpty()) return allowed.contains(sourceKey)
        return looksFinancial(text)
    }
}
