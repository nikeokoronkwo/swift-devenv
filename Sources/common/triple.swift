/// Library for handling target triples.
/// 
/// Triple represents a target triple, which is a string that describes a platform
/// in the format <architecture>-<vendor>-<os>-<abi>.
/// For example, "x86_64-apple-darwin" represents a 64-bit Intel architecture
/// on Apple hardware running macOS.

public struct Triple: Equatable, ExpressibleByStringLiteral, CustomStringConvertible, Codable {
  public let arch: Architecture
  public let vendor: Vendor
  public let os: OS
  public let abi: ABI

  public init(stringLiteral value: StringLiteralType) {
    self = try! Triple.parse(value)
  }

  public init(architecture: Architecture, vendor: Vendor, os: OS, abi: ABI) {
    self.arch = architecture
    self.vendor = vendor
    self.os = os
    self.abi = abi
  }

  public static func == (lhs: Triple, rhs: Triple) -> Bool {
    return lhs.arch == rhs.arch && lhs.vendor == rhs.vendor && lhs.os == rhs.os
      && lhs.abi == rhs.abi
  }

  public static func parse(_ triple: String) throws -> Triple {
    guard !triple.isEmpty else {
      throw ParseError.empty
    }
    let parts = triple.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: true)
    if parts.count == 4 {
      // equal split
      return Triple(
        architecture: Architecture(rawValue: String(parts[0])) ?? .other(String(parts[0])),
        vendor: Vendor(rawValue: String(parts[1])) ?? .other(String(parts[1])),
        os: OS(rawValue: String(parts[2])) ?? .other(String(parts[2])),
        abi: ABI(rawValue: String(parts[3])) ?? .other(String(parts[3]))
      )
    } else if parts.count == 3 {
      // no abi
      return Triple(
        architecture: Architecture(rawValue: String(parts[0])) ?? .other(String(parts[0])),
        vendor: Vendor(rawValue: String(parts[1])) ?? .other(String(parts[1])),
        os: OS(rawValue: String(parts[2])) ?? .other(String(parts[2])),
        abi: .all
      )
    } else if parts.count == 1 {
      // applies for all architectures of oses
      return Triple(
        architecture: .all,
        vendor: .all,
        os: OS(rawValue: String(parts[0])) ?? .other(String(parts[0])),
        abi: .all
      )
    } else {
      throw ParseError.malformed
    }
  }

  public var description: String {
    "\(arch.rawValue)-\(vendor.rawValue)-\(os.rawValue)-\(abi.rawValue)"
  }
}

extension Triple {
  static var system: Triple {
    let os: OS
    let arch: Architecture
    var vendor: Vendor = .all

    #if os(macOS)
      os = .darwin
      vendor = .apple
    #elseif os(Linux)
      os = .linux
    #elseif os(Windows)
      os = .windows
    #else
      os = .other("unknown")
    #endif

    #if arch(x86_64) || arch(amd64)
      arch = .x86_64
    #elseif arch(i386)
      arch = .i386
    #elseif arch(arm64)
      arch = .arm
    #elseif arch(arm)
      arch = .armv7
    #else
      arch = .other("unknown")
    #endif

    return Triple(
      architecture: arch,
      vendor: vendor,
      os: os,
      abi: .all
    )
  }
}

extension Triple {
  // TODO: Expand to support subarchitecture, endianness
  public enum Architecture: RawRepresentable, Equatable, Codable {
    public typealias RawValue = String

    case amd64  // same as x86_64
    case arm  // same as arm64, aarch64
    case armv7
    case aarch64
    case i386
    case riscv32
    case riscv64
    case x86
    case x86_64
    case other(String)
    case all

    public init?(rawValue: String) {
      switch rawValue.lowercased() {
      case "amd64": self = .amd64
      case "arm", "arm64": self = .arm
      case "armv7": self = .armv7
      case "aarch64": self = .aarch64
      case "i386": self = .i386
      case "riscv32": self = .riscv32
      case "riscv64": self = .riscv64
      case "x86": self = .x86
      case "x86_64": self = .x86_64
      case "*": self = .all
      default: self = .other(rawValue)
      }
    }

    public var rawValue: String {
      switch self {
      case .amd64: return "amd64"
      case .arm: return "arm"
      case .armv7: return "armv7"
      case .aarch64: return "aarch64"
      case .i386: return "i386"
      case .riscv32: return "riscv32"
      case .riscv64: return "riscv64"
      case .x86: return "x86"
      case .x86_64: return "x86_64"
      case .all: return "*"
      case .other(let value): return value
      }
    }
  }

  public enum Vendor: RawRepresentable, Equatable, Codable {
    case apple
    case pc
    case nvidia
    case ibm
    case unknown
    case all
    case other(String)

    public init?(rawValue: String) {
      switch rawValue.lowercased() {
      case "apple": self = .apple
      case "pc": self = .pc
      case "nvidia": self = .nvidia
      case "ibm": self = .ibm
      case "unknown": self = .unknown
      case "*": self = .all
      default: self = .other(rawValue)
      }
    }

    public var rawValue: String {
      switch self {
      case .apple: return "apple"
      case .pc: return "pc"
      case .nvidia: return "nvidia"
      case .ibm: return "ibm"
      case .unknown: return "unknown"
      case .all: return "*"
      case .other(let value): return value
      }
    }
    public typealias RawValue = String
  }

  public enum OS: RawRepresentable, Equatable, Codable {
    case linux
    case darwin
    case windows
    case freebsd
    case netbsd
    case openbsd
    case android
    case none
    case all
    case other(String)

    public init?(rawValue: String) {
      switch rawValue.lowercased() {
      case "linux": self = .linux
      case "darwin", "macos", "macosx": self = .darwin
      case "windows": self = .windows
      case "*": self = .all
      case "freebsd": self = .freebsd
      case "netbsd": self = .netbsd
      case "openbsd": self = .openbsd
      case "android": self = .android
      case "none": self = .none
      default: self = .other(rawValue)
      }
    }

    public var rawValue: String {
      switch self {
      case .linux: return "linux"
      case .darwin: return "darwin"
      case .windows: return "windows"
      case .freebsd: return "freebsd"
      case .netbsd: return "netbsd"
      case .openbsd: return "openbsd"
      case .android: return "android"
      case .none: return "none"
      case .all: return "*"
      case .other(let value): return value
      }
    }
    public typealias RawValue = String
  }

  // TODO: Expan dot support all of: libc, abi, variant, version, objfileformat
  public enum ABI: RawRepresentable, Equatable, Codable {
    case gnu
    case gnueabihf
    case musl
    case eabi
    case msvc
    case android
    case all
    case other(String)

    public init?(rawValue: String) {
      switch rawValue.lowercased() {
      case "gnu": self = .gnu
      case "gnueabihf": self = .gnueabihf
      case "musl": self = .musl
      case "eabi": self = .eabi
      case "msvc": self = .msvc
      case "android": self = .android
      case "*": self = .all
      default: self = .other(rawValue)
      }
    }

    public var rawValue: String {
      switch self {
      case .gnu: return "gnu"
      case .gnueabihf: return "gnueabihf"
      case .musl: return "musl"
      case .eabi: return "eabi"
      case .msvc: return "msvc"
      case .android: return "android"
      case .all: return "*"
      case .other(let value): return value
      }
    }
    public typealias RawValue = String
  }
}

extension Triple: Sendable {}
extension Triple.Architecture: Sendable {}
extension Triple.Vendor: Sendable {}
extension Triple.OS: Sendable {}
extension Triple.ABI: Sendable {}