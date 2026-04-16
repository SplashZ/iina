import Foundation

enum CastingError: Error, LocalizedError {
  case noNetworkInterface
  case connectionFailed(String)
  case controlFailed(String)
  case deviceLost
  case unsupportedFormat(String)

  var errorDescription: String? {
    switch self {
    case .noNetworkInterface:
      return NSLocalizedString("casting.error.no_network", comment: "")
    case .connectionFailed(let msg):
      return String(format: NSLocalizedString("casting.error.connection_failed", comment: ""), msg)
    case .controlFailed(let msg):
      return String(format: NSLocalizedString("casting.error.control_failed", comment: ""), msg)
    case .deviceLost:
      return NSLocalizedString("casting.error.device_lost", comment: "")
    case .unsupportedFormat(let fmt):
      return String(format: NSLocalizedString("casting.error.unsupported_format", comment: ""), fmt)
    }
  }
}
