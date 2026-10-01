import Foundation

struct AudioTrack: Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let isDefault: Bool
}

struct VideoInfo {
    let videoId: String
    let title: String
    let duration: Int
    let thumbnail: String
    let languages: [AudioTrack]

    var durationString: String {
        let m = duration / 60
        let s = duration % 60
        return String(format: "%d:%02d", m, s)
    }
}

enum DownloadError: LocalizedError {
    case pythonNotFound
    case scriptNotFound
    case fetchFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound: return "python3 not found in /opt/homebrew/bin or /usr/local/bin"
        case .scriptNotFound: return "ytlang.py not found"
        case .fetchFailed(let msg): return "Failed to fetch video info: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        }
    }
}

class YTLangBackend {
    let scriptPath: String
    let pythonPath: String

    private var env: [String: String] {
        var e = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = e["PATH"] {
            e["PATH"] = extra + ":" + existing
        } else {
            e["PATH"] = extra
        }
        return e
    }

    init() {
        let candidates = [
            Bundle.main.resourcePath.map { $0 + "/ytlang.py" },
            Bundle.main.bundlePath + "/../ytlang.py",
            NSHomeDirectory() + "/Projects/yt-lang-dl/ytlang.py",
        ].compactMap { $0 }

        self.scriptPath = candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? NSHomeDirectory() + "/Projects/yt-lang-dl/ytlang.py"

        let pythonCandidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        self.pythonPath = pythonCandidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "python3"
    }

    func fetchInfo(url: String) async throws -> VideoInfo {
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw DownloadError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, url, "--list-langs", "--json"]
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw DownloadError.fetchFailed(String(output.suffix(300)))
        }

        guard let jsonData = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw DownloadError.fetchFailed("Could not parse response")
        }

        let title = json["title"] as? String ?? "Unknown"
        let duration = json["duration"] as? Int ?? 0
        let thumbnail = json["thumbnail"] as? String ?? ""
        let videoId = json["video_id"] as? String ?? ""

        var languages: [AudioTrack] = []
        if let langs = json["languages"] as? [[String: Any]] {
            for lang in langs {
                let code = lang["code"] as? String ?? ""
                let name = lang["name"] as? String ?? code
                let isDefault = lang["is_default"] as? Bool ?? false
                languages.append(AudioTrack(id: code, code: code, name: name, isDefault: isDefault))
            }
        }

        return VideoInfo(videoId: videoId, title: title, duration: duration, thumbnail: thumbnail, languages: languages)
    }

    func download(
        url: String,
        language: String,
        quality: String,
        outputDir: String,
        title: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw DownloadError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, url, "--lang", language, "--quality", quality, "-o", outputDir, "--json-progress"]
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        var outputText = ""
        let handle = pipe.fileHandleForReading

        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            if let chunk = String(data: data, encoding: .utf8) {
                outputText += chunk
                for line in chunk.components(separatedBy: "\n") where !line.isEmpty {
                    if let jsonData = line.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        if let pct = obj["progress"] as? Double {
                            await MainActor.run { onProgress(pct) }
                        }
                    }
                }
            }
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errMsg = outputText.components(separatedBy: "\n")
                .compactMap { line -> String? in
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let err = obj["error"] as? String else { return nil }
                    return err
                }.last ?? String(outputText.suffix(200))
            throw DownloadError.downloadFailed(errMsg)
        }

        for line in outputText.components(separatedBy: "\n").reversed() {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let file = obj["file"] as? String {
                return file
            }
        }

        return outputDir
    }
}
