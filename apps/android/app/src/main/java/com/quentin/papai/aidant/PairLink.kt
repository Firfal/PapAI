package com.quentin.papai.aidant

import android.net.Uri

/** Adresse d'appairage : `https://…[/k/<clé>]/p/<code>`, éventuellement dans `papai://pair?u=…`. */
data class PairLink(
    /** Tout ce qui précède `/p/<code>`, par exemple `https://hôte/k/<clé>`. */
    val base: String,
    /** null : le code sera tapé à la main. */
    val code: String?,
) {
    val host: String get() = Uri.parse(base).host ?: base
    val origin: String
        get() {
            val u = Uri.parse(base)
            val s = u.scheme ?: return base
            val h = u.host ?: return base
            return "$s://$h" + if (u.port > 0) ":${u.port}" else ""
        }

    companion object {
        private val pattern = Regex("""^(https?://.+?)/p/(\d{6})/?(?:[?#].*)?$""")

        /** Accepte `papai://pair?u=<url encodée>` et l'ancien `https://…/p/<code>`. */
        fun parse(text: String): PairLink? {
            var t = text.trim()
            if (t.startsWith("papai://", ignoreCase = true)) {
                t = Uri.parse(t).getQueryParameter("u")?.trim() ?: return null
            }
            val m = pattern.find(t) ?: return null
            return PairLink(m.groupValues[1].trimEnd('/'), m.groupValues[2])
        }
    }
}
