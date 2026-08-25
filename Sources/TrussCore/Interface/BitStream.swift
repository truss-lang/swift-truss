import Foundation

public enum TrussPackageFormat {
    public static let magic: [UInt8] = Array("TRSP".utf8)
    public static let version: UInt32 = 1
}

public enum TrussPackageCodecError: Error, Equatable {
    case badMagic
    case badVersion
    case truncated
    case typeIndexOutOfRange(Int)
    case tocLookupFailed(String)
}

public final class BitWriter {
    private(set) var bytes: [UInt8] = []
    public init() {}
    public func u8(_ v: UInt8) { bytes.append(v) }
    public func u32(_ v: UInt32) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF))
        bytes.append(UInt8((v >> 16) & 0xFF))
        bytes.append(UInt8((v >> 24) & 0xFF))
    }

    public func u64(_ v: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8((v >> UInt64(shift)) & 0xFF))
        }
    }

    public func bool(_ v: Bool) { u8(v ? 1 : 0) }
    public func string(_ s: String) {
        let data = Array(s.utf8)
        u32(UInt32(data.count))
        bytes.append(contentsOf: data)
    }

    public func stringOpt(_ s: String?) {
        if let s { bool(true); string(s) } else { bool(false) }
    }

    public func appendBytes(_ data: [UInt8]) { bytes.append(contentsOf: data) }
    public func byteCount() -> Int { bytes.count }
}

public final class BitReader {
    private let bytes: [UInt8]
    private var index: Int
    public init(_ bytes: [UInt8], start: Int = 0) {
        self.bytes = bytes
        index = start
    }

    public var position: Int { index }
    public func seek(_ p: Int) { index = p }
    public func hasMore() -> Bool { index < bytes.count }
    public func u8() throws -> UInt8 {
        guard index < bytes.count else { throw TrussPackageCodecError.truncated }
        defer { index += 1 }
        return bytes[index]
    }

    public func u32() throws -> UInt32 {
        var v: UInt32 = 0
        for i in 0 ..< 4 {
            try v |= UInt32(u8()) << UInt32(i * 8)
        }
        return v
    }

    public func u64() throws -> UInt64 {
        var v: UInt64 = 0
        for i in 0 ..< 8 {
            try v |= UInt64(u8()) << UInt64(i * 8)
        }
        return v
    }

    public func bool() throws -> Bool { try u8() != 0 }
    public func string() throws -> String {
        let len = try Int(u32())
        guard index + len <= bytes.count else { throw TrussPackageCodecError.truncated }
        let data = Array(bytes[index ..< (index + len)])
        index += len
        return String(decoding: data, as: UTF8.self)
    }

    public func stringOpt() throws -> String? {
        if try bool() { try string() } else { nil }
    }
}
