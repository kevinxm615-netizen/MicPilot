import Foundation

enum DeviceAbbreviation {
    static func make(from deviceName: String?) -> String {
        guard let deviceName else { return "--" }
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "--" }

        let lowercaseName = name.lowercased()
        if lowercaseName.contains("wireless microphone") { return "WM" }
        if lowercaseName.contains("macbook") { return "MBP" }
        if lowercaseName.contains("iphone") { return "iPhone" }
        if lowercaseName.contains("blackhole") { return "BH" }
        if lowercaseName.contains("ishot") { return "iShot" }

        let ignoredWords: Set<String> = ["microphone", "mic", "input", "audio", "device"]
        let words = name
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !ignoredWords.contains($0.lowercased()) }

        if words.count >= 2 {
            return words.prefix(4).compactMap(\.first).map(String.init).joined().uppercased()
        }
        if let word = words.first {
            return String(word.prefix(5))
        }
        return "Mic"
    }
}
