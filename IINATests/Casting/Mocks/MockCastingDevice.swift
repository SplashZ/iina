import Foundation
@testable import IINA

final class MockCastingDevice: CastingDevice {
  let id: String
  let name: String
  let type: String

  init(id: String = "mock-device-1", name: String = "Mock TV", type: String = "DLNA") {
    self.id = id
    self.name = name
    self.type = type
  }
}
