import Foundation

struct CastingSession {
  let device: any CastingDevice
  var position: TimeInterval
  var duration: TimeInterval
  var isPlaying: Bool
  var volume: Double      // 0.0 - 1.0
  var isMuted: Bool
  let startPosition: TimeInterval  // 投屏开始时的 mpv 位置，停止后可用于恢复
  var audioTrackId: Int?           // 当前音频轨道 ID，nil 表示默认
  var isSwitchingAudio: Bool = false  // 后台 remux + 重投中
}
