import XCTest

/// App Store 1.4.0 ret gerekçesi (Guideline 2.1(a)): aynı ekranda Türkçe ve
/// İngilizce birlikte duruyordu. Kaynak dil Türkçe; katalog anahtarı o metin,
/// İngilizce `Localizable.xcstrings` içinde. Sabit bir kullanıcı metni anahtar
/// değilse sistem dili ne olursa olsun olduğu gibi çizilir ve diller karışır.
final class LocalizationCoverageTests: XCTestCase {

    private let neutral: Set<String> = ["CPU", "RAM", "GPU", "Disk", "IP", "CSV", "JSON", "W", "PID", "Hz"]
    private let turkishInEnglish = CharacterSet(charactersIn: "çğıöşüÇĞİÖŞÜıİ")

    func testUserFacingCopyIsACatalogKeyWithEnglish() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = try loadCatalog(root.appending(path: "Resources/Localizable.xcstrings"))
        var problems: [String] = []

        for (key, english) in catalog.sorted(by: { $0.key < $1.key }) {
            if english.rangeOfCharacter(from: turkishInEnglish) != nil {
                problems.append("katalog İngilizce değer Türkçe harf içeriyor: \(key) => \(english)")
            }
        }

        let surface = [
            "Sources/StatusAppBar/Views",
            "Sources/StatusAppBar/Formatters.swift",
            "Sources/StatusAppBar/HealthScore.swift",
            "Sources/StatusAppBar/Monitors/SMCReader.swift",
        ]
        for rel in try swiftFiles(root: root, roots: surface) {
            let source = try String(contentsOf: root.appending(path: rel), encoding: .utf8)
            let code = stripComments(source)
            for hit in surfaceLiterals(in: code) {
                problems += validate(hit, file: rel, catalog: catalog, localizedCall: false)
            }
        }

        let sources = root.appending(path: "Sources")
        for rel in try swiftFiles(root: root, roots: [sources.path]) {
            let source = try String(contentsOf: root.appending(path: rel), encoding: .utf8)
            let code = stripComments(source)
            for hit in localizedCalls(in: code) {
                problems += validate(hit, file: rel, catalog: catalog, localizedCall: true)
            }
        }

        let components = try String(contentsOf: root.appending(path: "Sources/StatusAppBar/Views/Components.swift"), encoding: .utf8)
        if !components.contains("Text(localizedKey(label))") || !components.contains("Text(localizedKey(title))") {
            problems.append("MetricRow/InfoRow/SectionCard etiketi Text(String) ile çiziliyor; katalog anahtarı çözülmez")
        }
        let alerts = try String(contentsOf: root.appending(path: "Sources/StatusAppBar/Views/AlertSettingsSection.swift"), encoding: .utf8)
        if !alerts.contains("Text(localizedKey(label))") {
            problems.append("ThresholdRow etiketi katalogdan çözülmüyor")
        }
        let popover = try String(contentsOf: root.appending(path: "Sources/StatusAppBar/Views/PopoverView.swift"), encoding: .utf8)
        if !popover.contains("Text(localizedKey(temp.label))") {
            problems.append("Sensör adı katalogdan çözülmüyor")
        }

        XCTAssertTrue(problems.isEmpty, "\n" + problems.sorted().joined(separator: "\n"))
    }

    private struct Hit: Hashable {
        var literal: String
        var line: Int
    }

    private func validate(_ hit: Hit, file: String, catalog: [String: String], localizedCall: Bool) -> [String] {
        let where_ = "\(file):\(hit.line)"
        if hit.literal.contains("\\(") {
            if localizedCall {
                return ["\(where_) String(localized:) içindeki metin katalog anahtarı olamaz: \(hit.literal)"]
            }
            if hasNonNeutralLetters(stripInterpolations(hit.literal)) {
                return ["\(where_) sabit metin kataloğa bağlı değil: \(hit.literal)"]
            }
            return []
        }
        let key = unescape(hit.literal)
        if !key.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) {
            return []
        }
        if !localizedCall && isSymbolName(key) { return [] }
        if neutral.contains(key) { return [] }
        guard let english = catalog[key] else {
            return ["\(where_) katalogda yok: \(key)"]
        }
        if english.rangeOfCharacter(from: turkishInEnglish) != nil {
            return ["\(where_) İngilizce karşılık Türkçe harf içeriyor: \(key) => \(english)"]
        }
        return []
    }

    private func surfaceLiterals(in source: String) -> [Hit] {
        let patterns = [
            #"(?:Text|Button|Label|Toggle|TextField|SecureField|Picker)\(\s*"((?:\\.|[^"\\])*)""#,
            #"(?:title|label|value):\s*"((?:\\.|[^"\\])*)""#,
            #"return\s+\(\s*"((?:\\.|[^"\\])*)""#,
            #"return\s+"((?:\\.|[^"\\])*)""#,
            #"\?\s*"((?:\\.|[^"\\])*)""#,
            #"\("[A-Za-z0-9]{4}",\s*"((?:\\.|[^"\\])*)""#,
            #"append\(\s*"((?:\\.|[^"\\])*)""#,
        ]
        return matches(patterns, in: source)
    }

    private func localizedCalls(in source: String) -> [Hit] {
        matches([#"String\(localized:\s*"((?:\\.|[^"\\])*)""#], in: source)
    }

    private func matches(_ patterns: [String], in source: String) -> [Hit] {
        var hits: [Hit] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = source as NSString
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: source) else { continue }
                let line = source[..<range.lowerBound].reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
                hits.append(Hit(literal: String(source[range]), line: line))
            }
        }
        return hits
    }

    /// SF Symbol adları (`cpu`, `folder.fill`) kullanıcı metni değildir.
    /// Rakamlı kısa etiketler (`1s`) ve büyük harfli kelimeler (`Net`) öyle değildir.
    private func isSymbolName(_ key: String) -> Bool {
        let asciiSymbol = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        if key.contains("."), !key.contains(where: \.isWhitespace) {
            return key.unicodeScalars.allSatisfy { asciiSymbol.contains($0) }
        }
        let lower = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        return !key.isEmpty && key.unicodeScalars.allSatisfy { lower.contains($0) }
    }

    private func hasNonNeutralLetters(_ leftover: String) -> Bool {
        var text = leftover
        for token in neutral.sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: token, with: " ")
        }
        return text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private func stripInterpolations(_ literal: String) -> String {
        var result = ""
        var i = literal.startIndex
        while i < literal.endIndex {
            if literal[i] == "\\", literal.index(after: i) < literal.endIndex, literal[literal.index(after: i)] == "(" {
                var depth = 1
                var j = literal.index(i, offsetBy: 2)
                while j < literal.endIndex && depth > 0 {
                    if literal[j] == "(" { depth += 1 }
                    else if literal[j] == ")" { depth -= 1 }
                    if depth > 0 { j = literal.index(after: j) }
                }
                i = j < literal.endIndex ? literal.index(after: j) : j
            } else {
                result.append(literal[i])
                i = literal.index(after: i)
            }
        }
        return result
    }

    private func unescape(_ literal: String) -> String {
        var out = ""
        var i = literal.startIndex
        while i < literal.endIndex {
            if literal[i] == "\\", literal.index(after: i) < literal.endIndex {
                let next = literal[literal.index(after: i)]
                switch next {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default:
                    out.append("\\")
                    out.append(next)
                }
                i = literal.index(i, offsetBy: 2)
            } else {
                out.append(literal[i])
                i = literal.index(after: i)
            }
        }
        return out
    }

    private func loadCatalog(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = root?["strings"] as? [String: Any] ?? [:]
        var catalog: [String: String] = [:]
        for (key, raw) in strings {
            guard let entry = raw as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any],
                  let en = locs["en"] as? [String: Any],
                  let unit = en["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String
            else { continue }
            catalog[key] = value
        }
        return catalog
    }

    private func swiftFiles(root: URL, roots: [String]) throws -> [String] {
        var files: [String] = []
        for rel in roots {
            let url = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : root.appending(path: rel)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                files.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
                continue
            }
            let listed = try FileManager.default.subpathsOfDirectory(atPath: url.path)
            for name in listed where name.hasSuffix(".swift") {
                files.append(url.appending(path: name).path.replacingOccurrences(of: root.path + "/", with: ""))
            }
        }
        return files
    }

    private func stripComments(_ source: String) -> String {
        var out = ""
        var i = source.startIndex
        var inString = false
        var escaped = false
        while i < source.endIndex {
            let c = source[i]
            let next = source.index(after: i)
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i = next
                continue
            }
            if c == "\"", !escaped {
                inString = true
                out.append(c)
                i = next
                continue
            }
            if c == "/", next < source.endIndex, source[next] == "/" {
                while i < source.endIndex, source[i] != "\n" { i = source.index(after: i) }
                continue
            }
            if c == "/", next < source.endIndex, source[next] == "*" {
                i = source.index(next, offsetBy: 1, limitedBy: source.endIndex) ?? source.endIndex
                while i < source.endIndex {
                    let n = source.index(after: i)
                    if source[i] == "*", n < source.endIndex, source[n] == "/" {
                        i = source.index(after: n)
                        break
                    }
                    if source[i] == "\n" { out.append("\n") }
                    i = n
                }
                continue
            }
            out.append(c)
            i = next
        }
        return out
    }
}
