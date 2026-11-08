package com.quentin.papai.aidant

import java.net.URI
import java.net.URLDecoder

/** Adresse d'appairage : `https://…[/k/<clé>]/p/<code>`, éventuellement dans `papai://pair?u=…`. */
data class PairLink(
    /** Tout ce qui précède `/p/<code>`, par exemple `https://hôte/k/<clé>`. */
    val base: String,
    /** null : le code sera tapé à la main. */
    val code: String?,
    val senior: String? = null,
) {
    val host: String get() = URI(base).authority
    val origin: String get() = PairingPolicy.origin(base)

    companion object {
        private val pattern = Regex("""^(https?://.+?)/p/(\d{6})/?(?:[?#].*)?$""")

        /** Accepte `papai://pair?u=<url encodée>` et l'ancien `https://…/p/<code>`. */
        fun parse(text: String): PairLink? = runCatching {
            var t = text.trim()
            var senior: String? = null
            if (t.startsWith("papai://", ignoreCase = true)) {
                val uri = URI(t)
                require(uri.host == "pair")
                val query = uri.rawQuery.orEmpty().split('&').associate {
                    val parts = it.split('=', limit = 2)
                    parts[0] to URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8")
                }
                t = query["u"]?.trim() ?: return null
                senior = cleanText(query["n"]).ifEmpty { null }
            }
            val m = pattern.find(t) ?: return null
            val base = m.groupValues[1].trimEnd('/')
            PairingPolicy.origin(base)
            PairLink(base, m.groupValues[2], senior)
        }.getOrNull()
    }
}

object PairingPolicy {
    const val refusal = "Ce lien n'est pas sûr. Demandez un nouveau QR code depuis l'ordinateur de la personne aidée (Réglages > Mon support)."
    const val officialHost = "papai-450417131702.europe-west1.run.app"

    fun isOfficial(base: String): Boolean = runCatching {
        val uri = URI(origin(base))
        uri.scheme == "https" && uri.host == officialHost && uri.port in listOf(-1, 443)
    }.getOrDefault(false)

    fun invitationError(text: String, debug: Boolean): String? {
        val link = PairLink.parse(text) ?: return refusal
        return error(link.base, debug)
    }

    fun presentation(link: PairLink) = PairingPresentation(
        server = if (isOfficial(link.base)) "Serveur PapAI officiel"
            else "Serveur inconnu : ne continuez que si la personne aidée vous a donné ce lien elle-même",
        domain = link.host,
    )

    fun origin(value: String): String {
        val uri = URI(value)
        require(uri.scheme.lowercase() in setOf("http", "https") && !uri.host.isNullOrEmpty() && uri.rawUserInfo == null)
        require(uri.port in -1..65535)
        require(uri.rawQuery == null && uri.rawFragment == null)
        return "${uri.scheme.lowercase()}://${uri.host.lowercase()}" + if (uri.port == -1) "" else ":${uri.port}"
    }

    fun error(base: String, debug: Boolean): String? = runCatching {
        val uri = URI(origin(base))
        if (uri.scheme == "https" || (debug && isLocal(uri.host))) null
        else refusal
    }.getOrElse { refusal }

    private fun isLocal(host: String): Boolean {
        if (host == "localhost" || host.endsWith(".local")) return true
        val parts = host.split('.')
        if (parts.size != 4 || parts.any { it.isEmpty() || it.any { c -> c !in '0'..'9' } || it.length > 3 || (it.length > 1 && it.startsWith('0')) }) return false
        val ip = parts.map { it.toInt() }
        if (ip.any { it !in 0..255 }) return false
        return ip == listOf(127, 0, 0, 1) || ip[0] == 10 ||
            (ip[0] == 172 && ip[1] in 16..31) || (ip[0] == 192 && ip[1] == 168)
    }

    fun needsConfirmation(hasWorkingLink: Boolean, confirmed: Boolean = false): Boolean = hasWorkingLink && !confirmed

    fun responseOrigin(link: PairLink, responseServer: String?): String = origin(link.base)
}

data class PairingPresentation(
    val title: String = "Relier ce téléphone",
    val description: String = "Vous serez prévenu dès qu’une demande d’aide arrive sur son ordinateur. Rien ne bouge sans votre accord.",
    val relationLabel: String = "Votre lien avec la personne aidée",
    val server: String,
    val domain: String,
)
