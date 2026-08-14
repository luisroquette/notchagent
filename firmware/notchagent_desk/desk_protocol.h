#pragma once

#include <Arduino.h>

namespace desk_protocol {

constexpr uint8_t kMagic[] = {0x4E, 0x41, 0x44, 0x4B};
constexpr uint8_t kProtocolMajor = 1;
constexpr size_t kHeaderSize = 14;
constexpr size_t kChecksumSize = 4;

enum FrameType : uint8_t {
  Hello = 1,
  HelloAcknowledgement = 2,
  Snapshot = 3,
  Heartbeat = 4,
  DeviceTelemetry = 5,
};

struct FrameView {
  FrameType type;
  uint32_t sequence;
  const uint8_t *payload;
  size_t payloadLength;
};

inline uint32_t read32(const uint8_t *p) {
  return static_cast<uint32_t>(p[0]) |
         (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

inline void append32(uint32_t value, uint8_t *out) {
  out[0] = value & 0xFF;
  out[1] = (value >> 8) & 0xFF;
  out[2] = (value >> 16) & 0xFF;
  out[3] = (value >> 24) & 0xFF;
}

inline uint32_t crc32(const uint8_t *data, size_t length) {
  uint32_t crc = 0xFFFFFFFF;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; ++bit) {
      crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

inline size_t cobsDecode(const uint8_t *input, size_t length, uint8_t *output, size_t capacity) {
  size_t readIndex = 0;
  size_t writeIndex = 0;
  while (readIndex < length) {
    const uint8_t code = input[readIndex++];
    if (code == 0 || readIndex + code - 1 > length) return 0;
    for (uint8_t i = 1; i < code; ++i) {
      if (writeIndex >= capacity) return 0;
      output[writeIndex++] = input[readIndex++];
    }
    if (code != 0xFF && readIndex < length) {
      if (writeIndex >= capacity) return 0;
      output[writeIndex++] = 0;
    }
  }
  return writeIndex;
}

inline size_t cobsEncode(const uint8_t *input, size_t length, uint8_t *output, size_t capacity) {
  if (capacity == 0) return 0;
  size_t readIndex = 0;
  size_t writeIndex = 1;
  size_t codeIndex = 0;
  uint8_t code = 1;
  while (readIndex < length) {
    if (input[readIndex] == 0) {
      output[codeIndex] = code;
      codeIndex = writeIndex++;
      code = 1;
      ++readIndex;
    } else {
      if (writeIndex >= capacity) return 0;
      output[writeIndex++] = input[readIndex++];
      ++code;
      if (code == 0xFF) {
        output[codeIndex] = code;
        codeIndex = writeIndex++;
        code = 1;
      }
    }
  }
  if (codeIndex >= capacity) return 0;
  output[codeIndex] = code;
  return writeIndex;
}

inline bool decodeFrame(uint8_t *packet, size_t packetLength, uint8_t *decoded,
                        size_t decodedCapacity, FrameView &frame) {
  const size_t length = cobsDecode(packet, packetLength, decoded, decodedCapacity);
  if (length < kHeaderSize + kChecksumSize) return false;
  if (memcmp(decoded, kMagic, sizeof(kMagic)) != 0 || decoded[4] != kProtocolMajor) return false;
  const size_t payloadLength = read32(decoded + 10);
  if (payloadLength > DESK_MAX_PAYLOAD || length != kHeaderSize + payloadLength + kChecksumSize) return false;
  const uint32_t expected = read32(decoded + length - kChecksumSize);
  if (crc32(decoded, length - kChecksumSize) != expected) return false;
  if (decoded[5] < Hello || decoded[5] > DeviceTelemetry) return false;
  frame.type = static_cast<FrameType>(decoded[5]);
  frame.sequence = read32(decoded + 6);
  frame.payload = decoded + kHeaderSize;
  frame.payloadLength = payloadLength;
  return true;
}

inline bool writeFrame(Stream &serial, FrameType type, uint32_t sequence,
                       const uint8_t *payload, size_t payloadLength,
                       uint8_t *work, size_t workCapacity,
                       uint8_t *encoded, size_t encodedCapacity) {
  const size_t rawLength = kHeaderSize + payloadLength + kChecksumSize;
  if (payloadLength > DESK_MAX_PAYLOAD || rawLength > workCapacity) return false;
  memcpy(work, kMagic, sizeof(kMagic));
  work[4] = kProtocolMajor;
  work[5] = type;
  append32(sequence, work + 6);
  append32(payloadLength, work + 10);
  if (payloadLength) memcpy(work + kHeaderSize, payload, payloadLength);
  append32(crc32(work, rawLength - kChecksumSize), work + rawLength - kChecksumSize);
  const size_t encodedLength = cobsEncode(work, rawLength, encoded, encodedCapacity - 1);
  if (!encodedLength) return false;
  encoded[encodedLength] = 0;
  return serial.write(encoded, encodedLength + 1) == encodedLength + 1;
}

}  // namespace desk_protocol
