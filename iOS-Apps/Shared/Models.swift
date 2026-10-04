import Foundation

// The API contains nullable fields and MariaDB decimals encoded as strings.
// Preserve their wire representation instead of imposing the obsolete iOS models.
struct Row: Identifiable {
    let raw: [String: Any]
    var id: Int { integer("id") }
    init(_ raw: [String: Any] = [:]) { self.raw = raw }
    func text(_ key: String, fallback: String = "") -> String {
        guard let value = raw[key], !(value is NSNull) else { return fallback }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return fallback
    }
    func integer(_ key: String) -> Int { Int(text(key)) ?? 0 }
    func flag(_ key: String) -> Bool {
        if let value = raw[key] as? Bool { return value }
        return ["true", "1"].contains(text(key).lowercased())
    }
    func object(_ key: String) -> Row { Row(raw[key] as? [String: Any] ?? [:]) }
    func rows(_ key: String) -> [Row] { (raw[key] as? [[String: Any]] ?? []).map { Row($0) } }
    var name: String {
        let stored = text("name")
        return stored.isEmpty ? [text("first_name"), text("last_name")].joined(separator: " ").trimmingCharacters(in: .whitespaces) : stored
    }
    var shiftTitle: String { text("event_name", fallback: text("role", fallback: "Shift")) }
    var timing: String { "\(text("shift_date")) · \(text("start_time").prefix(5))–\(text("end_time").prefix(5))" }
}

enum AppKind {
    #if STAFF
    static let name = "SISS Staff"
    static let role = "staff"
    #elseif ADMIN
    static let name = "SISS Admin"
    static let role = "admin"
    #else
    static let name = "Siss-Supervisor"
    static let role = "supervisor"
    #endif
    static let supervisor = role == "supervisor"
    static let jobs = ["Supervisor", "SIA", "Steward", "Admin", "SIA Steward", "Manned Guard", "Door Supervisor", "CCTV Operator", "First Aid"]
}

enum UKTime {
    static let zone = TimeZone(identifier: "Europe/London")!
    static func formatter(_ format: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_GB")
        value.timeZone = zone
        value.dateFormat = format
        value.isLenient = false
        return value
    }
    static func day(_ date: Date = Date()) -> String { formatter("yyyy-MM-dd").string(from: date) }
    static func wall(_ date: Date) -> String { formatter("yyyy-MM-dd'T'HH:mm:ss").string(from: date) }
    static func parse(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        return formatter("yyyy-MM-dd'T'HH:mm:ss").date(from: value)
            ?? formatter("yyyy-MM-dd HH:mm:ss").date(from: value)
    }
    static func interval(_ shift: Row) -> (Date, Date)? {
        guard let start = parse("\(shift.text("shift_date"))T\(normalized(shift.text("start_time")))"),
              var end = parse("\(shift.text("end_date", fallback: shift.text("shift_date")))T\(normalized(shift.text("end_time")))") else { return nil }
        if end <= start {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return (start, end)
    }
    private static func normalized(_ time: String) -> String { time.count == 5 ? time + ":00" : time }
}

enum QRToken {
    static func extract(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 4096 else { return nil }
        func valid(_ token: String) -> Bool {
            token.count <= 2000 && token.range(of: "^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
        }
        if valid(value) { return value }
        let hosts = ["yourallsiss.co.uk", "www.yourallsiss.co.uk", "siss.duckdns.org", "allsiss.co.uk", "www.allsiss.co.uk"]
        guard let url = URLComponents(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              hosts.contains(url.host?.lowercased() ?? ""), url.user == nil, url.password == nil,
              ["/scan", "/scan/"].contains(url.path) else { return nil }
        let tokens = (url.queryItems ?? []).filter { $0.name == "token" }.compactMap(\.value)
        guard tokens.count == 1, valid(tokens[0]) else { return nil }
        return tokens[0]
    }
}
