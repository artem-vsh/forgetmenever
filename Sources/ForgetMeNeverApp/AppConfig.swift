import Foundation
import Carbon

struct AppConfig: Decodable {
    struct HotKeyConfig: Decodable {
        enum Modifier: String, Decodable {
            case command
            case option
            case control
            case shift
        }

        let keyCode: UInt32
        let modifierFlags: [Modifier]

        private enum CodingKeys: String, CodingKey {
            case keyCode = "key_code"
            case modifierFlags = "modifier_flags"
        }

        var carbonModifiers: UInt32 {
            modifierFlags.reduce(0) { partialResult, modifier in
                partialResult | modifier.carbonFlag
            }
        }

        var displayName: String {
            let modifierNames = modifierFlags.map { $0.displayName }.joined(separator: " + ")
            let keyName = KeyCodeLookup.displayName(for: keyCode)
            if modifierNames.isEmpty {
                return keyName
            }
            return "\(modifierNames) + \(keyName)"
        }
    }

    private let backendURL: URL
    let apiKey: String?
    let hotkey: HotKeyConfig

    private enum CodingKeys: String, CodingKey {
        case backendURL = "backend_url"
        case modelURL = "model_url" // legacy name
        case modelVoiceName = "model_voice_name" // ignored legacy field
        case apiKey = "api_key"
        case hotkey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let backendURL = try? container.decode(URL.self, forKey: .backendURL) {
            self.backendURL = backendURL
        } else if let legacyURL = try? container.decode(URL.self, forKey: .modelURL) {
            self.backendURL = legacyURL
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.backendURL,
                .init(codingPath: decoder.codingPath, debugDescription: "backend_url is required")
            )
        }
        _ = try? container.decodeIfPresent(String.self, forKey: .modelVoiceName) // legacy, ignored
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        self.hotkey = try container.decode(HotKeyConfig.self, forKey: .hotkey)
    }

    static func load(fileManager: FileManager = .default) throws -> AppConfig {
        let candidates = candidateConfigURLs(fileManager: fileManager)
        var lastError: Error?
        for url in candidates {
            print("[ForgetMeNever] Checking config at \(url.path)")
            if fileManager.fileExists(atPath: url.path) {
                do {
                    let config = try decodeConfig(at: url)
                    print("[ForgetMeNever] Using config at \(url.path)")
                    return config
                } catch {
                    print("[ForgetMeNever] Failed to parse config at \(url.path): \(error.localizedDescription)")
                    lastError = error
                }
            } else {
                print("[ForgetMeNever] Config not found at \(url.path)")
            }
        }
        if let lastError {
            throw lastError
        }
        throw AppConfigError.missingResource
    }

    private static func candidateConfigURLs(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        if let overridePath = ProcessInfo.processInfo.environment["FMN_CONFIG_PATH"], !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (overridePath as NSString).expandingTildeInPath
            urls.append(URL(fileURLWithPath: expanded))
        }
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let supportDirectory = appSupport.appendingPathComponent("ForgetMeNever", isDirectory: true)
            let supportURL = supportDirectory.appendingPathComponent("AppConfig.json", isDirectory: false)
            urls.append(supportURL)
        }
        if let bundled = Bundle.module.url(forResource: "AppConfig", withExtension: "json") {
            urls.append(bundled)
        }
        return urls
    }

    private static func decodeConfig(at url: URL) throws -> AppConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AppConfigError.readFailure(underlying: error)
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(AppConfig.self, from: data)
        } catch let decodingError as DecodingError {
            print("[ForgetMeNever] Decoding error: \(decodingError)")
            throw AppConfigError.decodeFailure(underlying: decodingError)
        } catch {
            throw AppConfigError.decodeFailure(underlying: error)
        }
    }

    private var environmentBackendURLOverride: URL? {
        guard let value = ProcessInfo.processInfo.environment["FMN_BACKEND_URL"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let expanded = (value as NSString).expandingTildeInPath
        if let url = URL(string: expanded), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: expanded)
    }

    private var effectiveBackendURL: URL {
        environmentBackendURLOverride ?? backendURL
    }

    private var backendBaseEndpoint: URL {
        let base = effectiveBackendURL
        let lowered = base.path.lowercased()
        if lowered.hasSuffix("/transcript") || lowered.hasSuffix("/transcriptions") {
            return base.deletingLastPathComponent()
        }
        return base
    }

    var transcriptEndpoint: URL {
        let base = effectiveBackendURL
        let normalizedPath = base.path.lowercased()
        if normalizedPath.hasSuffix("/transcript") || normalizedPath.hasSuffix("/transcriptions") {
            return base
        }
        return base.appendingPathComponent("transcript")
    }

    var processEndpoint: URL {
        backendBaseEndpoint.appendingPathComponent("process")
    }

    var todoListEndpoint: URL {
        backendBaseEndpoint.appendingPathComponent("todos")
    }
}

enum AppConfigError: Error {
    case missingResource
    case readFailure(underlying: Error)
    case decodeFailure(underlying: Error)
}

extension AppConfigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "AppConfig.json resource is missing from the bundle."
        case let .readFailure(underlying):
            return "Unable to read AppConfig.json: \(underlying.localizedDescription)"
        case let .decodeFailure(underlying):
            return "Unable to decode AppConfig.json: \(underlying.localizedDescription)"
        }
    }
}

private enum KeyCodeLookup {
    static func displayName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49:
            return "Space"
        case 53:
            return "Esc"
        case 36:
            return "Return"
        case 48:
            return "Tab"
        default:
            if let string = UCKeyTranslateToString(keyCode: keyCode) {
                return string.uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private static func UCKeyTranslateToString(keyCode: UInt32) -> String? {
        guard let layoutData = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(layoutData, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(ptr, to: CFData.self) as Data
        return data.withUnsafeBytes { pointer -> String? in
            guard let baseAddress = pointer.baseAddress else {
                return nil
            }
            let keyboardLayout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            var keysDown: UInt32 = 0
            var chars: [UniChar] = Array(repeating: 0, count: 4)
            var realLength: Int = 0
            let modifierKeyState = UInt32(activeFlagBit)

            let error = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &keysDown,
                chars.count,
                &realLength,
                &chars
            )
            guard error == noErr, realLength > 0 else {
                return nil
            }
            return String(utf16CodeUnits: chars, count: realLength)
        }
    }
}

private extension AppConfig.HotKeyConfig.Modifier {
    var carbonFlag: UInt32 {
        switch self {
        case .command:
            return UInt32(cmdKey)
        case .option:
            return UInt32(optionKey)
        case .control:
            return UInt32(controlKey)
        case .shift:
            return UInt32(shiftKey)
        }
    }

    var displayName: String {
        switch self {
        case .command:
            return "⌘"
        case .option:
            return "⌥"
        case .control:
            return "⌃"
        case .shift:
            return "⇧"
        }
    }
}
