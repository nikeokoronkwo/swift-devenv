import TOMLKit


// TODO: Support YAML
func parseConfiguration(_ contents: String) throws -> DevenvConfiguration {
  return try TOMLDecoder().decode(DevenvConfiguration.self, from: contents)
}

/// The basic structure of a devenv configuration object.
///
/// The configuration is gotten from a `devenv.toml` file looking like the following:
/// ```toml
/// [scripts]
/// pg = "psql -U$DB_USERNAME -p$DB_PASSWORD"
///
/// [scripts.migrate]
/// children = {
///     foo = "bar"
/// }
/// ```
///
/// This contains mostly information about defined scripts, and dependencies of the given
/// project.
public struct DevenvConfiguration: Codable {
  public let scripts: DevenvScripts?
  public let deps: [String: DevenvDep]
}

enum DevenvConfigError: Error {
  case notFound(String)
}
extension DevenvConfiguration {
  public struct DevenvScripts: Codable {
    let data: [String: DevenvScript]

    public func encode(to encoder: any Encoder) throws {
      var value = encoder.singleValueContainer()

      try value.encode(data)
    }

    public init(from decoder: any Decoder) throws {
      let value = try decoder.singleValueContainer()

      self.data = try value.decode([String: DevenvScript].self)
    }

    subscript(value: String) -> [DevenvConfiguration.DevenvScript] {
      get {
        assert(!value.isEmpty, "subscript index cannot be empty")
        // split names
        let parts = value.split(separator: ".")

        guard let firstPart = parts.first else {
          fatalError("Malformed script index \(value)")
        }

        let script = self.data[String(firstPart)]

        assert(script != nil, "Could not find script for desired index \(value)")

        if parts.count == 1 {
          return [script!]
        } else {
          switch script! {
          case .structured(let obj):
            do {
              return try obj[parts.suffix(from: 1).joined(separator: ".")]
            } catch {
              fatalError("Error indexing \(firstPart): \(error)")
            }
          case .basic:
            // throw error
            fatalError("Cannot multi-index on a string script")

          }
        }
      }
    }
  }
}
extension DevenvConfiguration {
  /// A structure for a dependency for a given project
  ///
  /// This can be used to defined tools that can be used for a given project
  public struct DevenvDep: Sendable {
    /// The source of the given dependency
    let sources: [DevenvDepSource]

    /// Hooks to run before/after install
    let hooks: DevenvDepHooks?

    /// Whether to verify the dependency after installation
    let verify: Bool?
  }
}

extension DevenvConfiguration.DevenvDep: Codable {
    public init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.hooks = try value.decodeIfPresent(DevenvDepHooks.self, forKey: .hooks)
        self.verify = try value.decodeIfPresent(Bool.self, forKey: .verify)
        let rawSources = try value.decode([DevenvRawDepSource].self, forKey: .sources)
        var convertedSources: [DevenvDepSource] = []
        for rawSource in rawSources {
            convertedSources.append(try rawSource.convert())
        }
        self.sources = convertedSources
    }
}



enum ParseError: Error {
  case malformed
  case empty
}
extension DevenvConfiguration.DevenvDep {
  struct DevenvDepSource: Codable, Sendable {
    /// The type of dependency this is
    let type: DevenvDepType

    /// The artifacts generated as a result.
    ///
    /// By default, this becomes the top-level executables
    /// that can be found in the output of fetching/building the application
    let artifacts: [String: String]?

    /// A list of platform triples that the given dependency works for
    let platforms: [Triple]

    func convert() -> DevenvRawDepSource {
        var depTypeStr: String
        var name: String?
        var url: String?
        var rev: String?
        var version: String?
        var sha: String?
        switch type {
        case .brew(let n, let v):
            depTypeStr = "brew"
            name = n
            version = v
        case .apt(let n, let v):
            depTypeStr = "apt"
            name = n
            version = v 
        case .winget(let n, let v):
            depTypeStr = "winget"
            name = n
            version = v
        case .choco(let n, let v):
            depTypeStr = "choco"
            name = n
            version = v
        case .git(let u, let r):
            depTypeStr = "git"
            url = u
            rev = r
        case .url(let u, let s):
            depTypeStr = "url"
            url = u
            sha = s
        @unknown default:
            fatalError("Unknown case!")
            break
        }

        return DevenvRawDepSource(
            type: depTypeStr,
            url: url,
            sha: sha,
            artifacts: artifacts,
            name: name,
            rev: rev,
            version: version,
            platforms: platforms.map { $0.description }
        )
    }
  }

  struct DevenvRawDepSource: Codable {
    let type: String

    let url: String?

    let sha: String?

    let artifacts: [String: String]?

    let name: String?

    let rev: String?

    let version: String?

    let platforms: [String]?

    func convert() throws -> DevenvDepSource {
      var depType: DevenvDepType
      switch type.lowercased() {
        case "brew":
            depType = .brew(name!, version: version)
        case "apt":
            depType = .apt(name!, version: version)
        case "winget":
            depType = .winget(name!, version: version)
        case "choco":
            depType = .choco(name!, version: version)
        case "git":
            depType = .git(url!, rev: rev)
        case "url":
            depType = .url(url!, sha: sha)
        default:
            throw DevenvConfigError.notFound("Could not find dependency type \(type)")
      }

      var triples: [Triple] = []
      if let platforms = self.platforms {
          for plat in platforms {
              do {
                  let triple = try Triple.parse(plat)
                  triples.append(triple)
              } catch {
                  print("Warning: Could not parse platform triple \(plat): \(error)")
              }
          }
      } else {
        triples = [
            "*-*-*-*",
        ]
      }

      return DevenvDepSource(
        type: depType,
        artifacts: artifacts,
        platforms: triples
      )
    }
  }

  enum DevenvDepType: Codable {
    case brew(String, version: String? = nil)
    case apt(String, version: String? = nil)
    case winget(String, version: String? = nil)
    case choco(String, version: String? = nil)
    case git(String, rev: String? = "main")
    case url(String, sha: String? = nil)
  }

  struct DevenvDepHooks: Codable {
    var beforeInstall: String?

    var afterInstall: String?
  }
}

extension DevenvConfiguration {
  enum DevenvScript {
    case basic(String)
    case structured(DevenvScriptRep)
  }

  protocol DevenvScriptRep: Codable, CustomStringConvertible {
    subscript(value: String) -> [DevenvScript] { get throws }
  }

  public struct DevenvSingleScript: DevenvScriptRep {
    subscript(value: String) -> [DevenvConfiguration.DevenvScript] {
      get throws {
        // single scripts have no index
        throw DevenvConfigError.notFound("Cannot index single script: Tried to index \(value)")
      }
    }

    /// The script to run
    var script: String
  }

  public struct DevenvMultiScript: DevenvScriptRep {

    /// Any children this script may have
    var children: [String: DevenvScript]

    subscript(value: String) -> [DevenvConfiguration.DevenvScript] {
      get throws {
        assert(!value.isEmpty, "subscript index cannot be empty")
        // split names
        let parts = value.split(separator: ".")

        guard let firstPart = parts.first else {
          fatalError("Malformed script index \(value)")
        }

        let script = children[String(firstPart)]

        assert(script != nil, "Could not find script for desired index \(value)")

        if parts.count == 1 {
          return [script!]
        } else {
          switch script! {
          case .structured(let obj):
            do {
              return try obj[parts.suffix(from: 1).joined(separator: ".")]
            } catch {
              fatalError("Error indexing \(firstPart): \(error)")
            }
          case .basic:
            // throw error
            fatalError("Cannot multi-index on a string script")
          }
        }
      }
    }
  }

}
extension DevenvConfiguration.DevenvScript: CustomStringConvertible {
  var description: String {
    switch self {
    case .basic(let value):
      return value
    case .structured(let scriptRep):
      return scriptRep.description
    @unknown default:
      fatalError("Unknown case!")
      break
    }
  }
}
extension DevenvConfiguration.DevenvScript: Codable {
  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()

    if let stringValue = try? value.decode(String.self) {
      self = .basic(stringValue)
    } else if let objectValue = try? value.decode(DevenvConfiguration.DevenvMultiScript.self) {
      print(value.codingPath, "DevenvMultiScript")
      self = .structured(objectValue)
    } else if let objectValue = try? value.decode(DevenvConfiguration.DevenvSingleScript.self) {
      print(value.codingPath, "DevenvSingleScript")
      self = .structured(objectValue)
    } else {
      throw DecodingError.dataCorruptedError(in: value, debugDescription: "Could not decode value")
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .basic(let stringValue):
      try container.encode(stringValue)
    case .structured(let structuredValue):
      try container.encode(structuredValue)
    }
  }
}
extension DevenvConfiguration.DevenvSingleScript: CustomStringConvertible {
  public var description: String {
    script
  }

}
extension DevenvConfiguration.DevenvMultiScript: CustomStringConvertible {
  public var description: String {
    var scriptStr = ""
    for (key, value) in self.children {
      var v = ""
      for substr in value.description.split(separator: "\n") {
        v += "  \(substr)\n"
      }
      scriptStr += buildString {
        "\(key):"
        "\(v)"
      }
    }

    return scriptStr
  }
}
