import Foundation

enum SiteCheck {
    private static func punycode(_ text: String) -> String {
        let scalars = text.precomposedStringWithCanonicalMapping.unicodeScalars.map { Int($0.value) }
        var output = scalars.filter { $0 < 128 }.map { String(UnicodeScalar($0)!) }.joined()
        var handled = output.count
        let basic = handled
        if basic > 0 { output += "-" }
        var n = 128, delta = 0, bias = 72
        func digit(_ value: Int) -> String {
            String(UnicodeScalar(value < 26 ? value + 97 : value - 26 + 48)!)
        }
        while handled < scalars.count {
            let next = scalars.filter { $0 >= n }.min()!
            delta += (next - n) * (handled + 1)
            n = next
            for scalar in scalars {
                if scalar < n { delta += 1 }
                if scalar == n {
                    var q = delta
                    var k = 36
                    while true {
                        let t = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias)
                        if q < t { break }
                        output += digit(t + (q - t) % (36 - t))
                        q = (q - t) / (36 - t)
                        k += 36
                    }
                    output += digit(q)
                    var d = handled == basic ? delta / 700 : delta / 2
                    d += d / (handled + 1)
                    var adaptation = 0
                    while d > 455 { d /= 35; adaptation += 36 }
                    bias = adaptation + 36 * d / (d + 38)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return "xn--" + output
    }

    private static func normalizedHost(_ value: String) -> String? {
        var value = value.lowercased()
        if value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty, !value.hasSuffix(".") else { return nil }
        let labels = value.components(separatedBy: ".").map {
            $0.unicodeScalars.allSatisfy { $0.isASCII } ? $0 : punycode($0)
        }
        let host = labels.joined(separator: ".")
        guard host.utf8.count <= 253,
              labels.allSatisfy({ $0.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$",
                                          options: .regularExpression) != nil }),
              labels.last!.range(of: "^(?:[0-9]+|0x[0-9a-f]+)$", options: .regularExpression) == nil
        else { return nil }
        return host
    }

    private static func forbidden(_ url: String) -> Bool {
        url.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0) ||
            CharacterSet.controlCharacters.contains($0) || $0 == "\\"
        }
    }

    static func hostOf(_ url: String) -> String? {
        guard !forbidden(url),
              let separator = url.range(of: "://"),
              url[..<separator.lowerBound].lowercased() == "https" else { return nil }
        let authority = String(url[separator.upperBound...].prefix { !"/?#".contains($0) })
        guard !authority.contains("@") else { return nil }
        let parts = authority.components(separatedBy: ":")
        guard parts.count == 1 || (parts.count == 2 && parts[1] == "443") else { return nil }
        return normalizedHost(parts[0])
    }

    static func classify(_ url: String, sites: [String], hosts: [String] = []) -> String {
        let neutral = ["about:blank", "chrome://newtab/", "edge://newtab/",
                       "chrome-error://chromewebdata/"]
        if !forbidden(url) && (neutral.contains(url) || url.hasPrefix("chrome-search://")) {
            return "neutre"
        }
        guard let host = hostOf(url) else { return "hors" }
        if sites.compactMap(normalizedHost).contains(where: { host == $0 || host.hasSuffix("." + $0) }) ||
            hosts.compactMap(normalizedHost).contains(host) { return "ok" }
        return "hors"
    }
}
