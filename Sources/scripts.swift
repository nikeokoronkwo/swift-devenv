func listScripts(_ config: DevenvConfiguration) -> String {
  guard let scripts = config.scripts else {
    return "No scripts available"
  }

  var scriptStr = ""
  for (key, value) in scripts.data {
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
