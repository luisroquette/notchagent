import CryptoKit
import Foundation

struct Manifest: Codable {
    var schemaVersion = 2
    var firmwareVersion: String
    var chip = "esp32s3"
    var imageFile = "NotchAgentDesk-factory.bin"
    var imageAddress: UInt32 = 0
    var imageSHA256: String
    var sourceSHA256: String
    var flasherFile = "esptool"
    var flasherSHA256: String
}

guard CommandLine.arguments.count == 6 else {
    FileHandle.standardError.write(Data("usage: package_manifest VERSION IMAGE FLASHER SOURCE_SHA256 OUTPUT\n".utf8))
    exit(2)
}

func sha256(_ path: String) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe))
    return digest.map { String(format: "%02x", $0) }.joined()
}

let manifest = try Manifest(
    firmwareVersion: CommandLine.arguments[1],
    imageSHA256: sha256(CommandLine.arguments[2]),
    sourceSHA256: CommandLine.arguments[4],
    flasherSHA256: sha256(CommandLine.arguments[3])
)
let lowercaseHexCharacters = Set("0123456789abcdef")
guard manifest.sourceSHA256.count == 64,
      manifest.sourceSHA256.allSatisfy(lowercaseHexCharacters.contains) else {
    FileHandle.standardError.write(Data("invalid source SHA-256\n".utf8))
    exit(2)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(manifest).write(to: URL(fileURLWithPath: CommandLine.arguments[5]), options: .atomic)
