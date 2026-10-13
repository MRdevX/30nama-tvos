import Foundation

enum Fmt {
    private static let persianDigits = Array("۰۱۲۳۴۵۶۷۸۹")

    /// Replaces ASCII digits with Persian ones.
    static func persianDigits(_ s: String) -> String {
        String(s.map { c in
            guard let v = c.wholeNumberValue, c.isASCII else { return c }
            return persianDigits[v]
        })
    }

    /// Player clock: "2:03" or "1:02:03".
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = s / 3600, m = s % 3600 / 60, x = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
    }

    /// Runtime in minutes as "1h 35m" / "۱ ساعت و ۳۵ دقیقه".
    static func runtime(minutes: Int?, lang: Lang) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let h = minutes / 60, m = minutes % 60
        switch lang {
        case .en:
            return [h > 0 ? "\(h)h" : nil, m > 0 ? "\(m)m" : nil].compactMap { $0 }.joined(separator: " ")
        case .ar:
            return [h > 0 ? "\(h) س" : nil, m > 0 ? "\(m) د" : nil].compactMap { $0 }.joined(separator: " ")
        case .fa:
            let parts = [h > 0 ? "\(h) ساعت" : nil, m > 0 ? "\(m) دقیقه" : nil].compactMap { $0 }
            return persianDigits(parts.joined(separator: " و "))
        }
    }

    static func score(_ value: Double) -> String {
        String(format: value >= 10 ? "%.0f" : "%.1f", value)
    }

    /// 84827 -> "84,827" / "۸۴٬۸۲۷".
    static func count(_ value: Int, lang: Lang) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: lang == .fa ? "fa_IR" : "en_US")
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
