import Foundation

protocol CastingProviderDelegate: AnyObject {
  func provider(_ provider: any CastingProviderProtocol, didDiscover device: any CastingDevice)
  func provider(_ provider: any CastingProviderProtocol, didLose device: any CastingDevice)
  func provider(_ provider: any CastingProviderProtocol, didFailWithError error: CastingError)
}

protocol CastingProviderProtocol: AnyObject {
  var delegate: (any CastingProviderDelegate)? { get set }

  /// 幂等可重入：自动停止上次发现再重新开始
  func startDiscovery()
  func stopDiscovery()

  /// startAt: 从该时间点开始播放（0 表示从头）
  func cast(mediaURL: URL, to device: any CastingDevice, startAt: TimeInterval) async throws
  func play() async throws
  func pause() async throws
  func seek(to position: TimeInterval) async throws
  func setVolume(_ volume: Double) async throws
  func setMute(_ muted: Bool) async throws
  func stopCasting() async throws
  func getPositionInfo() async throws -> (position: TimeInterval, duration: TimeInterval, isPlaying: Bool)
}
