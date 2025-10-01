import Foundation
import Crypto
#if os(macOS)
import Compression
#else
#warning("Compression not available outside macOS")
#endif

// TODO: Restructure this object
public struct DependencyMap: Sendable {
    var artifactMap: [String: [String: URL]]
}

/// Downloads a given dependency, and returns a local map of artifact names to their local URLs
func downloadDependency(
    _ name: String,
    _ dep: DevenvConfiguration.DevenvDep, 
    to url: URL
) async throws -> DependencyMap {
    // find the triple of this system
    let systemTriple = Triple.system

    // get dependency sources that match this system
    // arranged from most scoped to least scoped
    let depSources = dep.sources.filter { source in
        // if no platforms specified, include it
        guard !source.platforms.isEmpty else {
            return true
        }
        // check if any platform matches the current system
        for platform in source.platforms {
            if systemTriple.matches(platform) {
                return true
            }
        }
        return false
    }.sorted { firstSource, secondSource in
        // prefer more scoped triples
        let firstScope = firstSource.platforms.max { a, b in
            a.scope(systemTriple) < b.scope(systemTriple)
        }
        let secondScope = secondSource.platforms.max { a, b in
            a.scope(systemTriple) < b.scope(systemTriple)
        }
        return firstScope!.scope(systemTriple) > secondScope!.scope(systemTriple)
    }

    print(depSources.count)

    // if no sources match, throw error
    guard !depSources.isEmpty else {
        throw DError.DependencyError(
            name, 
            message: "No sources match the current system \(systemTriple)"
        )
    }

    var dependencyArtifactMap: [String: [String: URL]] = [:]



    // try each source until one succeeds
    for source in depSources {
        var artifactMap: [String: URL]
        let depDestination = url.appendingPathComponent(name)
        switch source.type {
            case .url(let uri, sha: let sha):
                do {
                    
                    let dest = try await downloadFromURL(
                        url: uri, 
                        to: depDestination, 
                        sha: sha,
                        name: name
                    )
                    // TODO: Support compression/decompresion

                    // check artifacts
                    artifactMap = try validateArtifacts(source.artifacts, base: depDestination)
                    break;
                } catch {
                    continue;
                }
            default:
                throw DError.DependencyError(
                    name, 
                    message: "Unsupported dependency source type for downloading: \(source.type)"
                )
        }

        if !artifactMap.isEmpty {
            dependencyArtifactMap[name] = artifactMap
            break;
        }
    }

    return DependencyMap(artifactMap: dependencyArtifactMap)
}

func validateArtifacts(
    _ artifacts: [String: String]?,
    base url: URL,
) throws -> [String: URL] {
    var output: [String: URL] = [:]
    if let artifacts = artifacts {
        for (name, path) in artifacts {
            let targetUrl = URL(string: path, relativeTo: url)

            // check if it exists
            if let supposedUrl = targetUrl, let _ = try? Data(contentsOf: supposedUrl) {
                output[name] = supposedUrl
            }
        }
    } else {
        // get all top level 
        do {
            for file in try FileManager.default.contentsOfDirectory(
                at: url, 
                includingPropertiesForKeys: [.isExecutableKey, .isRegularFileKey], 
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                output[file.deletingPathExtension().lastPathComponent] = file
            }
        } catch {
            throw DError.Custom(message: "Error reading contents of dir for dependency")
        }
    }

    return output
}


func downloadFromURL(
    url: String, 
    to directory: URL, 
    sha: String? = nil,
    name: String? = nil
) async throws -> URL {

    guard let uri = URL(string: url) else {
        throw DError.Custom(
            message: "Invalid URL \(url)"
        )
    }

    var tempUrl: URL
    let downloadDestination = directory.appendingPathComponent(name != nil ? "\(name!)\(uri.pathExtension)" : uri.lastPathComponent)

    // download the file
    // TODO: In future use URLSession with delegate for progress reporting
    if #available(macOS 12.0, *) {
        let (tempFileURL, _) = try await URLSession.shared.download(from: uri)
        tempUrl = tempFileURL
    } else {
        tempUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
        let downloadTask = URLSession.shared.downloadTask(with: uri) { 
            uriOrNil, responseOrNil, errOrNil in
            guard let destUri = uriOrNil, errOrNil == nil else {
                // handle error
                return
            }

            DispatchQueue.main.async {
                try! FileManager.default.moveItem(at: destUri, to: tempUrl)
            }
        }
        downloadTask.resume()
    }

    // if sha is provided, verify it
    // TODO: AMD Windows??
    if let sha = sha {
        if Triple.system.arch == .amd64 && Triple.system.os == .windows {
            print("WARN: SHA Verification may not be guaranteed for AMD Windows Systems: https://github.com/apple/swift-crypto/tree/main#:~:text=Swift%20Crypto%20is%20an%20open%2Dsource%20implementation%20of%20a%20substantial%20portion%20of%20the%20API%20of%20Apple%20CryptoKit%20suitable%20for%20use%20on%20Linux%20and%20ARM64%20Windows%20platforms.")
        }
        let fileData = try Data(contentsOf: tempUrl)
        let fileSHA256 = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
        guard fileSHA256 == sha else {
            throw DError.DependencyError(
                url, 
                message: "SHA256 mismatch: expected \(sha), got \(fileSHA256)"
            )
        }
    }


    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: tempUrl, to: downloadDestination)

    // if file is zip, decompress
    guard let handle = try? FileHandle(forReadingFrom: downloadDestination) else {
        throw DError.FileNotFound(downloadDestination.absoluteString, message: "Could not read from file")
    }

    defer { 
        try? handle.close() 
    }

    

    return downloadDestination
}

extension Triple {
    /// Check whether a given triple matches another triple
    public func matches(_ other: Triple) -> Bool {
        (other.arch == .all || self.arch == other.arch)
            && (other.vendor == .all || self.vendor == other.vendor)
            && (other.os == .all || self.os == other.os)
            && (other.abi == .all || self.abi == other.abi)
    }

    /// Get a scope of a given triple compared to this triple
    /// 
    /// This helps sort triples based on how closely scoped they are to another triple
    /// 
    /// Being scoped to another triple means that the triple has more specific values for each component
    /// rather than being `all` or `none`
    /// 
    /// For example, `x86_64-apple-macosx-gnu` is more scoped than `x86_64-apple-macosx-none`
    /// which is more scoped than `x86_64-apple-all-none`
    /// which is more scoped than `x86_64-all-all-none`
    /// which is more scoped than `all-all-all-all
    public func scope(_ comparedTo: Triple) -> TripleScope {
        TripleScope(
            arch: self.arch != .all && self.arch == comparedTo.arch,
            vendor: self.vendor != .all && self.vendor == comparedTo.vendor,
            os: self.os != .all && self.os == comparedTo.os,
            abi: self.abi != .all && self.abi == comparedTo.abi
        )
    }
}

public struct TripleScope: Comparable {
    let arch: Bool
    let vendor: Bool
    let os: Bool
    let abi: Bool

    public static func < (lhs: TripleScope, rhs: TripleScope) -> Bool {
        // arch > vendor > os > abi
        if lhs.arch != rhs.arch {
            return !lhs.arch && rhs.arch
        }
        if lhs.vendor != rhs.vendor {
            return !lhs.vendor && rhs.vendor
        }
        if lhs.os != rhs.os {
            return !lhs.os && rhs.os
        }
        if lhs.abi != rhs.abi {
            return !lhs.abi && rhs.abi
        }
        return false
    }
}