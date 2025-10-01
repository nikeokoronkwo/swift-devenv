enum DError: Error {
  case FileNotFound(String, message: String)
  case Custom(message: String)
  case DependencyError(String, message: String)
}
