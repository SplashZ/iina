import Foundation

enum CastingState {
  case idle
  case discovering([any CastingDevice])
  case connecting(any CastingDevice)
  case casting(session: CastingSession)
  case error(CastingError)

  var isCasting: Bool {
    if case .casting = self { return true }
    return false
  }

  var session: CastingSession? {
    if case .casting(let s) = self { return s }
    return nil
  }

  var discoveredDevices: [any CastingDevice] {
    if case .discovering(let d) = self { return d }
    return []
  }
}
