// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import Foundation

@main
struct Devenv: AsyncParsableCommand {
  static let configuration: CommandConfiguration = CommandConfiguration(
    abstract: "A better dev environment",
    version: "0.1.0",
    subcommands: [DevenvSetup.self, DevenvScript.self],
    defaultSubcommand: DevenvSetup.self,
  )

  @OptionGroup var globalOptions: DevenvOptions

  mutating func run() throws {
    print("Hello, world!")
  }
}

struct DevenvOptions: ParsableArguments {
  @Option(
    name: [.long, .short],
    help: "The configuration file to use for. Defaults to the 'devenv.toml' file in the CWD")
  var config: String = "devenv.toml"
}

extension Devenv {
  struct DevenvScript: ParsableCommand {
    static let configuration: CommandConfiguration = CommandConfiguration(
      commandName: "script",
      abstract: "Run scripts for the given environment"
    )

    /// Whether to run the scripts with the deps located in env
    @Flag(inversion: .prefixedNo) var withDeps: Bool = false

    @OptionGroup var options: DevenvOptions

    @Argument var script: String?

    // TODO: script graph
    mutating func run() throws {
      // parse configuration file
      let config = try getConfiguration(file: options.config)

      // read script
      if let definedScript = self.script {

      } else {
        // list out scripts
        print(listScripts(config))
        return
      }

      // if withDeps, then
      // - read deps
      // - install deps concurrently
      // - activate env

      // if withDeps, run script in env
      // else run in normal shell
    }
  }

  struct DevenvSetup: AsyncParsableCommand {
    static let configuration: CommandConfiguration = CommandConfiguration(
      commandName: "setup",
      abstract: "Set up development environment, install dependencies, and more!",
      aliases: ["deps"]
    )

    @OptionGroup var options: DevenvOptions

    mutating func run() async throws {
      // parse configuration file
      let config = try getConfiguration(file: options.config)

      // read dependencies

      // install dependencies concurrently
      print("Installing dependencies...")

      // create deps directory if it doesn't exist
      let depsPath = "./.devenv/deps"
      if !FileManager.default.fileExists(atPath: depsPath) {
        try FileManager.default.createDirectory(atPath: depsPath, withIntermediateDirectories: true)
      }
      // TODO: Progress bars for each dependency download
      await withThrowingTaskGroup { group in
        for configDep in config.deps {
          let name = configDep.key
          let dep = configDep.value
          
          group.addTask {
            print("Downloading \(name) using \(dep.sources.count)")
            return try await downloadDependency(
              name, dep, 
              to: URL(fileURLWithPath: depsPath)
            )
          }
        }
      }
    }
  }

  struct DevenvActivate: ParsableCommand {
    static let configuration: CommandConfiguration = CommandConfiguration(
      commandName: "activate",
      abstract: "Activates the development environment, and shells out if requested"
    )

    /// Whether to emit the activate/deactivate scripts as shell scripts
    @Flag var emitAsScripts = false

    /// Whether to begin/run shell afterwards
    @Flag var shell = false

    @OptionGroup var options: DevenvOptions

    mutating func run() throws {
      // parse configuration file

      // read dependencies

      // check if dependencies
    }
  }
}

func getConfiguration(file: String) throws -> DevenvConfiguration {
  guard
    let configurationContents = try? String(contentsOfFile: file, encoding: String.Encoding.utf8)
  else {
    throw DError.FileNotFound(file, message: "Could not find the file")
  }

  return try parseConfiguration(configurationContents)
}
