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

    /**
     * Phrases that mean a movement ALREADY HAPPENED.
     *
     * Tuned against 40 days of this user's captures, where the earlier list
     * let marketing through by matching bare nouns. "compra", "pago",
     * "tarjeta", "credito", "aprobada", "envio" and "cargo" all appear in
     * promotional copy — "Compra +$400K: recibe $10K", "compras desde
     * $120.000", "Envío gratis desde $80K", a job alert matching "cargo" —
     * and every one of those reached the review inbox carrying a money
     * amount.
     *
     * So the test is past-tense verbs and bank-specific phrases, not nouns.
     * An advertisement invites a purchase; a bank alert reports one.
     */
    private val actionWords = listOf(
        // Past tense: the movement is done.
        "compraste", "pagaste", "transferiste", "retiraste", "enviaste",
        // Possessive + preposition: a 3-D Secure prompt ("valida tu compra
        // en @AWAKE por valor de $520.000") is sometimes the only notice of
        // a purchase. "compras desde", "compras mayores a" and the rest of
        // the promotional copy never phrase it this way.
        "tu compra en", "su compra en",
        "recibiste", "realizaste", "compro", "pago por valor",
        // Bank phrasing around an approval.
        "compra por", "compra de", "compra aprobada", "pago aprobado",
        "pago exitoso", "transaccion aprobada", "transaccion exitosa",
        "retiro por", "avance por", "avance en efectivo",
        "cargo por", "cargo a tu", "cargo a su",
        // Money arriving.
        "te enviaron", "te consignaron", "te transfirieron", "te abonaron",
        "consignacion por", "abono por", "nomina por",
        // Card payments and reversals.
        "pago de tu tarjeta", "pago de tarjeta", "pago a tu tarjeta",
        "abono a tu tarjeta", "reverso", "devolucion por", "anulacion",
        // Rejections are still movements worth seeing.
        "rechazada", "declinada", "fondos insuficientes",
    )

    /**
     * Tap-to-pay wallets report a payment without a verb.
     *
     * Google Wallet's whole notification body is "COP27,500.00 with Tarjeta
     * Visa •1673" — an amount, a joining word, a card. No past-tense verb
     * exists to match, yet contactless is how this user pays in person, so
     * every one of those was being dropped here before Dart ever saw it.
     *
     * The card noun is required, which is what keeps this from re-opening the
     * gate: "con" alone would match "$50.000 con descuento" in any
     * advertisement.
     */
    private val walletShape = Regex(
        """(?:\$|cop|usd|us\$)\s*[\d.,]+\s+(?:with|con)\s+""" +
            """(?:tarjeta|card|visa|mastercard|master|amex|debito|credito)""",
        RegexOption.IGNORE_CASE,
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
        if (walletShape.containsMatchIn(normalized)) return true
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
