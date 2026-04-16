import Foundation
@testable import IINA

final class MockCastingProvider: CastingProviderProtocol {
  weak var delegate: (any CastingProviderDelegate)?

  // 调用记录
  var startDiscoveryCalled = false
  var stopDiscoveryCalled = false
  var castCalled = false
  var lastCastURL: URL?
  var lastCastDevice: (any CastingDevice)?
  var lastCastStartAt: TimeInterval = 0
  var playCalled = false
  var pauseCalled = false
  var lastSeekPosition: TimeInterval?
  var lastVolume: Double?
  var lastMuted: Bool?
  var stopCastingCalled = false
  var getPositionCallCount = 0

  // 行为控制
  var castShouldThrow: CastingError?
  var positionToReturn: (TimeInterval, TimeInterval, Bool) = (0, 0, true)
  var getPositionShouldThrow: CastingError?

  func startDiscovery() { startDiscoveryCalled = true }
  func stopDiscovery() { stopDiscoveryCalled = true }

  func cast(mediaURL: URL, to device: any CastingDevice, startAt: TimeInterval) async throws {
    castCalled = true
    lastCastURL = mediaURL
    lastCastDevice = device
    lastCastStartAt = startAt
    if let error = castShouldThrow { throw error }
  }

  func play() async throws { playCalled = true }
  func pause() async throws { pauseCalled = true }
  func seek(to position: TimeInterval) async throws { lastSeekPosition = position }
  func setVolume(_ volume: Double) async throws { lastVolume = volume }
  func setMute(_ muted: Bool) async throws { lastMuted = muted }
  func stopCasting() async throws { stopCastingCalled = true }

  func getPositionInfo() async throws -> (position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
    getPositionCallCount += 1
    if let error = getPositionShouldThrow { throw error }
    return positionToReturn
  }

  // 在测试中手动触发 delegate 回调
  func simulateDeviceDiscovered(_ device: any CastingDevice) {
    delegate?.provider(self, didDiscover: device)
  }

  func simulateDeviceLost(_ device: any CastingDevice) {
    delegate?.provider(self, didLose: device)
  }

  func simulateError(_ error: CastingError) {
    delegate?.provider(self, didFailWithError: error)
  }
}
