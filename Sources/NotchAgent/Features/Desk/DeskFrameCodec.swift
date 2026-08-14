import Foundation

struct DeskFrame: Sendable, Equatable {
    var type: NotchAgentDeskProtocol.FrameType
    var sequence: UInt32
    var payload: Data
}

enum DeskFrameCodecError: Error, Equatable {
    case invalidCOBS
    case invalidHeader
    case incompatibleProtocol
    case payloadTooLarge
    case invalidLength
    case invalidChecksum
}

enum DeskFrameCodec {
    private static let magic: [UInt8] = [0x4E, 0x41, 0x44, 0x4B] // NADK
    private static let headerSize = 14

    static func encode(_ frame: DeskFrame) throws -> Data {
        guard frame.payload.count <= NotchAgentDeskProtocol.maximumPayloadBytes else {
            throw DeskFrameCodecError.payloadTooLarge
        }
        var bytes = magic
        bytes.append(NotchAgentDeskProtocol.protocolMajor)
        bytes.append(frame.type.rawValue)
        appendLittleEndian(frame.sequence, to: &bytes)
        appendLittleEndian(UInt32(frame.payload.count), to: &bytes)
        bytes.append(contentsOf: frame.payload)
        appendLittleEndian(CRC32.checksum(bytes), to: &bytes)
        var encoded = cobsEncode(bytes)
        encoded.append(0)
        return Data(encoded)
    }

    static func decodePacket(_ packet: Data) throws -> DeskFrame {
        let bytes = try cobsDecode(Array(packet))
        guard bytes.count >= headerSize + 4, Array(bytes.prefix(4)) == magic else {
            throw DeskFrameCodecError.invalidHeader
        }
        guard bytes[4] == NotchAgentDeskProtocol.protocolMajor else {
            throw DeskFrameCodecError.incompatibleProtocol
        }
        guard let type = NotchAgentDeskProtocol.FrameType(rawValue: bytes[5]) else {
            throw DeskFrameCodecError.invalidHeader
        }
        let sequence = readLittleEndian(bytes, at: 6)
        let payloadLength = Int(readLittleEndian(bytes, at: 10))
        guard payloadLength <= NotchAgentDeskProtocol.maximumPayloadBytes else {
            throw DeskFrameCodecError.payloadTooLarge
        }
        let expected = headerSize + payloadLength + 4
        guard bytes.count == expected else { throw DeskFrameCodecError.invalidLength }
        let checksum = readLittleEndian(bytes, at: expected - 4)
        guard checksum == CRC32.checksum(Array(bytes.dropLast(4))) else {
            throw DeskFrameCodecError.invalidChecksum
        }
        return DeskFrame(type: type, sequence: sequence, payload: Data(bytes[headerSize..<(headerSize + payloadLength)]))
    }

    static func cobsEncode(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = [0]
        var codeIndex = 0
        var code: UInt8 = 1
        for byte in input {
            if byte == 0 {
                output[codeIndex] = code
                codeIndex = output.count
                output.append(0)
                code = 1
            } else {
                output.append(byte)
                code &+= 1
                if code == 0xFF {
                    output[codeIndex] = code
                    codeIndex = output.count
                    output.append(0)
                    code = 1
                }
            }
        }
        output[codeIndex] = code
        return output
    }

    static func cobsDecode(_ input: [UInt8]) throws -> [UInt8] {
        guard !input.isEmpty else { throw DeskFrameCodecError.invalidCOBS }
        var output: [UInt8] = []
        var index = 0
        while index < input.count {
            let code = Int(input[index])
            guard code != 0, index + code <= input.count + 1 else {
                throw DeskFrameCodecError.invalidCOBS
            }
            index += 1
            let end = index + code - 1
            guard end <= input.count else { throw DeskFrameCodecError.invalidCOBS }
            output.append(contentsOf: input[index..<end])
            index = end
            if code != 0xFF, index < input.count { output.append(0) }
        }
        return output
    }

    private static func appendLittleEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private static func readLittleEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}

struct DeskFrameStreamDecoder: Sendable {
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) -> [Result<DeskFrame, DeskFrameCodecError>] {
        buffer.append(contentsOf: data)
        if buffer.count > (NotchAgentDeskProtocol.maximumPayloadBytes + 64) * 2 {
            buffer.removeAll(keepingCapacity: true)
            return [.failure(.payloadTooLarge)]
        }
        var results: [Result<DeskFrame, DeskFrameCodecError>] = []
        while let delimiter = buffer.firstIndex(of: 0) {
            let packet = Data(buffer[..<delimiter])
            buffer.removeFirst(delimiter + 1)
            guard !packet.isEmpty else { continue }
            do { results.append(.success(try DeskFrameCodec.decodePacket(packet))) }
            catch let error as DeskFrameCodecError { results.append(.failure(error)) }
            catch { results.append(.failure(.invalidHeader)) }
        }
        return results
    }
}

private enum CRC32 {
    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
