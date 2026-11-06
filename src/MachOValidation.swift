import Foundation
import MachO

enum MachOValidation {
  static func validate(
    _ data: Data, platform: UInt32, isExecutable: Bool
  ) throws -> CatalogVersionNumber {
    guard data.count >= 32, word(data, at: 0) == MH_MAGIC_64,
      word(data, at: 4) == UInt32(CPU_TYPE_ARM64),
      !isExecutable || word(data, at: 12) == MH_EXECUTE
    else { throw Failure.invalidBinary }
    let count = Int(word(data, at: 16))
    let end = 32 + Int(word(data, at: 20))
    guard end <= data.count, count <= (end - 32) / 8 else { throw Failure.invalidBinary }
    var offset = 32
    var minimum: CatalogVersionNumber?
    for _ in 0..<count {
      guard offset + 8 <= end else { throw Failure.invalidBinary }
      let command = word(data, at: offset)
      let size = Int(word(data, at: offset + 4))
      guard size >= 8, size.isMultiple(of: 8), offset + size <= end else {
        throw Failure.invalidBinary
      }
      if command == LC_BUILD_VERSION {
        guard size >= 24, minimum == nil, word(data, at: offset + 8) == platform else {
          throw Failure.invalidBinary
        }
        let value = word(data, at: offset + 12)
        minimum = CatalogVersionNumber("\(value >> 16).\((value >> 8) & 0xff).\(value & 0xff)")
      }
      offset += size
    }
    guard offset == end, let minimum else { throw Failure.invalidBinary }
    return minimum
  }

  static func isMachO(_ data: Data) -> Bool {
    data.count >= 4
      && [
        MH_MAGIC_64, MH_CIGAM_64, MH_MAGIC, MH_CIGAM,
        FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64,
      ].contains(word(data, at: 0))
  }

  private static func word(_ data: Data, at offset: Int) -> UInt32 {
    data.withUnsafeBytes {
      UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
  }

  enum Failure: Error { case invalidBinary }
}
