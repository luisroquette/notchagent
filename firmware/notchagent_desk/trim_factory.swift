import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: trim_factory IMAGE\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: url, options: .mappedIfSafe)
guard let lastUsed = data.lastIndex(where: { $0 != 0xff }) else {
    FileHandle.standardError.write(Data("factory image is empty\n".utf8))
    exit(2)
}
let blockSize = 4_096
let trimmedSize = min(data.count, ((lastUsed + 1 + blockSize - 1) / blockSize) * blockSize)
guard trimmedSize >= 0x20000 else {
    FileHandle.standardError.write(Data("factory image is unexpectedly small\n".utf8))
    exit(2)
}
try data.prefix(trimmedSize).write(to: url, options: .atomic)
print("Trimmed factory image to \(trimmedSize) bytes")
