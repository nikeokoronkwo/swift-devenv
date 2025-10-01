/// A description
@resultBuilder
struct StringBuilder {
  static func buildBlock(_ components: String...) -> String {
    components.joined(separator: "\n")
  }
}

func buildString(@StringBuilder builder: () -> String) -> String {
  builder()
}
