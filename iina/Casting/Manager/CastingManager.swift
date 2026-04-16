import Foundation
import AppKit

@MainActor
final class CastingManager: CastingProviderDelegate {
  static let shared = CastingManager()

  private(set) var state: CastingState = .idle {
    didSet { NotificationCenter.default.post(name: .castingStateDidChange, object: self) }
  }

  private(set) var isScanning: Bool = false {
    didSet { NotificationCenter.default.post(name: .castingStateDidChange, object: self) }
  }
  private var scanningTimer: Timer?

  var isCasting: Bool { state.isCasting }

  func isCasting(for playerCore: PlayerCore) -> Bool {
    return isCasting && activePlayerCore === playerCore
  }

  private let provider: any CastingProviderProtocol
  private let logger = Logger.makeSubsystem("casting.manager")

  private let server = LocalMediaHTTPServer()
  private var registeredPath: String?
  private var positionTimer: Timer?
  private var consecutiveTimeouts = 0
  private weak var activePlayerCore: PlayerCore?
  private var currentMediaURL: URL?
  private var currentTempFileURL: URL?
  private var aidChangedObserver: NSObjectProtocol?
  /// Tracks the in-flight background remux so it can be cancelled on stop / new track change.
  private var remuxTask: Task<Void, Never>?
  /// Tracks the in-flight re-cast so it can be superseded when a newer track switch arrives.
  private var reCastTask: Task<Void, Never>?

  init(provider: any CastingProviderProtocol = DLNACastingProvider()) {
    self.provider = provider
    self.provider.delegate = self
    try? server.start()
  }

  // MARK: - Discovery

  func startDiscovery() {
    provider.startDiscovery()
    let existing = state.discoveredDevices
    state = .discovering(existing)
    scanningTimer?.invalidate()
    isScanning = true
    scanningTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.isScanning = false
        self?.scanningTimer = nil
      }
    }
  }

  /// 供投屏抽屉使用：非投屏状态才启动扫描
  func beginDiscoveryForPicker() {
    guard !isCasting else { return }
    startDiscovery()
  }

  func beginCasting(to device: any CastingDevice, playerCore: PlayerCore) {
    scanningTimer?.invalidate(); scanningTimer = nil; isScanning = false
    activePlayerCore = playerCore
    let startAt = playerCore.info.videoPosition?.second ?? 0
    state = .connecting(device)

    Task { [weak self] in
      guard let self else { return }
      do {
        let mediaURL: URL
        if let fileURL = playerCore.info.currentURL, fileURL.isFileURL {
          if let old = self.registeredPath { self.server.unregister(path: old) }
          // Register the raw file; remux only happens if the user switches audio tracks during casting.
          let path = self.server.register(fileURL: fileURL)
          self.registeredPath = path
          guard let url = self.server.mediaURL(for: path) else {
            throw CastingError.noNetworkInterface
          }
          mediaURL = url
        } else if let url = playerCore.info.currentURL {
          mediaURL = url
        } else {
          throw CastingError.connectionFailed(NSLocalizedString("casting.error.no_media_url", comment: ""))
        }

        Logger.log("CastingManager: mediaURL=\(mediaURL) startAt=\(startAt)", level: .debug, subsystem: logger)
        self.currentMediaURL = mediaURL
        playerCore.pause()
        try await self.provider.cast(mediaURL: mediaURL, to: device, startAt: startAt)

        let session = CastingSession(device: device, position: startAt, duration: 0,
                                     isPlaying: true, volume: 0.5, isMuted: false,
                                     startPosition: startAt,
                                     audioTrackId: playerCore.info.aid)
        self.state = .casting(session: session)
        self.startPolling()
      } catch let e as CastingError {
        self.cleanupServer()
        self.activePlayerCore?.resume()
        self.activePlayerCore = nil
        self.state = .error(e)
        self.showErrorAlert(e)
      } catch {
        self.cleanupServer()
        self.activePlayerCore?.resume()
        self.activePlayerCore = nil
        self.state = .error(.connectionFailed(error.localizedDescription))
      }
    }
  }

  @objc func stopCastingAction() {
    Task { @MainActor in await self.stopCasting() }
  }

  func stopCasting() async {
    remuxTask?.cancel(); remuxTask = nil
    reCastTask?.cancel(); reCastTask = nil
    stopPolling()
    try? await provider.stopCasting()
    cleanupServer()
    cleanupTempFile()
    activePlayerCore = nil
    currentMediaURL = nil
    state = .idle
  }

  // MARK: - Polling

  private func startPolling() {
    startPositionTimer()
    guard aidChangedObserver == nil else { return }
    aidChangedObserver = NotificationCenter.default.addObserver(
      forName: .iinaAIDChanged, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.isCasting else { return }
        self.reCast()
      }
    }
  }

  private func stopPolling() {
    stopPositionTimer()
    if let obs = aidChangedObserver {
      NotificationCenter.default.removeObserver(obs)
      aidChangedObserver = nil
    }
  }

  /// Starts only the position poll timer, leaving the audio track observer untouched.
  /// Called when re-entering the stable-playback state after a re-cast.
  private func startPositionTimer() {
    consecutiveTimeouts = 0
    positionTimer?.invalidate()
    positionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in await self?.pollOnce() }
    }
  }

  /// Stops only the position poll timer. The audio track observer remains active so any
  /// track switch the user makes during a re-cast is still captured.
  private func stopPositionTimer() {
    positionTimer?.invalidate()
    positionTimer = nil
  }

  /// Called when the user switches audio tracks during casting.
  /// Schedules a background remux for the new track; the device will re-cast
  /// when the remux finishes — no blocking wait on the main thread.
  private func reCast() {
    guard case .casting(_) = state,
          let player = activePlayerCore,
          let fileURL = player.info.currentURL, fileURL.isFileURL else { return }
    scheduleRemuxAndReCast(fileURL: fileURL, playerCore: player)
  }

  /// Starts a background remux for the currently selected audio track.
  /// Cancels any previously running remux task first.
  /// When the remux completes, calls `applyRemuxedFile(_:device:)` to re-cast.
  private func scheduleRemuxAndReCast(fileURL: URL, playerCore: PlayerCore) {
    guard let aid = playerCore.info.aid, aid > 0 else { return }
    let tracks = playerCore.info.audioTracks
    guard let track = tracks.first(where: { $0.id == aid }),
          let srcId = track.srcId else { return }

    let inputPath = fileURL.path
    let streamIndex = Int32(srcId)

    Logger.log("CastingManager: scheduling background remux (aid=\(aid) srcId=\(srcId))",
               level: .debug, subsystem: logger)
    if case .casting(var s) = state {
      s.isSwitchingAudio = true
      state = .casting(session: s)
    }

    // Cancel both in-flight remux and any ongoing re-cast — the latest track wins.
    reCastTask?.cancel()
    remuxTask?.cancel()
    remuxTask = Task { [weak self] in
      guard let self else { return }

      let tmpPath = await Task.detached(priority: .userInitiated) {
        try? AudioTrackRemuxer.remuxFile(inputPath, audioStreamIndex: streamIndex)
      }.value

      if Task.isCancelled {
        // Remux produced a file but the task was superseded; delete it immediately.
        if let tmp = tmpPath { try? FileManager.default.removeItem(atPath: tmp) }
        return
      }

      guard let tmpPath else {
        Logger.log("CastingManager: remux failed, keeping current stream",
                   level: .warning, subsystem: self.logger)
        if case .casting(var s) = self.state {
          s.isSwitchingAudio = false
          self.state = .casting(session: s)
        }
        return
      }

      Logger.log("CastingManager: remux done → \(tmpPath), applying", level: .debug, subsystem: self.logger)
      self.applyRemuxedFile(URL(fileURLWithPath: tmpPath))
    }
  }

  /// Swaps in the remuxed file and re-casts from the current playback position.
  /// Any previously running re-cast task is cancelled — the latest call always wins.
  private func applyRemuxedFile(_ tmpURL: URL) {
    guard case .casting(let session) = state else { return }
    let device = session.device

    if let old = registeredPath { server.unregister(path: old) }
    cleanupTempFile()
    currentTempFileURL = tmpURL
    let path = server.register(fileURL: tmpURL)
    registeredPath = path
    guard let newURL = server.mediaURL(for: path) else { return }
    currentMediaURL = newURL

    reCastTask?.cancel()
    reCastTask = Task { [weak self] in
      guard let self, !Task.isCancelled else { return }

      // Capture the latest polled position right before we stop the timer —
      // this is more accurate than the position captured when the remux finished.
      let position = self.state.session?.position ?? session.position
      self.stopPositionTimer()

      do {
        Logger.log("CastingManager: re-casting with remuxed file, position=\(position)",
                   level: .debug, subsystem: self.logger)
        try await self.provider.cast(mediaURL: newURL, to: device, startAt: position)

        // If cancelled (by a newer re-cast or stopCasting), leave timer management to
        // the caller: the next re-cast will restart it, or stopCasting already stopped it.
        guard !Task.isCancelled else { return }

        if case .casting(var s) = self.state {
          s.audioTrackId = self.activePlayerCore?.info.aid
          s.isSwitchingAudio = false
          self.state = .casting(session: s)
        }
        self.activePlayerCore?.mainWindow.displayOSD(
          .custom(NSLocalizedString("casting.osd.switched_audio", comment: "音轨切换完成"))
        )
      } catch {
        guard !Task.isCancelled else { return }

        Logger.log("CastingManager: re-cast with remuxed file failed: \(error)",
                   level: .warning, subsystem: self.logger)
        if case .casting(var s) = self.state {
          s.isSwitchingAudio = false
          self.state = .casting(session: s)
        }
        self.activePlayerCore?.mainWindow.displayOSD(
          .custom(NSLocalizedString("casting.osd.switch_audio_failed", comment: "音轨切换失败"))
        )
      }
      self.startPositionTimer()
    }
  }

  private func pollOnce() async {
    do {
      let info = try await provider.getPositionInfo()
      Logger.log("[playback] poll: pos=\(String(format: "%.1f", info.position))s dur=\(String(format: "%.1f", info.duration))s isPlaying=\(info.isPlaying)", level: .debug, subsystem: logger)
      consecutiveTimeouts = 0
      guard case .casting(var s) = state else { return }
      s.position = info.position
      s.duration = info.duration
      s.isPlaying = info.isPlaying
      state = .casting(session: s)
    } catch {
      consecutiveTimeouts += 1
      Logger.log("[playback] poll failed (\(consecutiveTimeouts)/3): \(error)", level: .warning, subsystem: logger)
      if consecutiveTimeouts == 3 {
        stopPolling()
        cleanupServer()
        cleanupTempFile()
        activePlayerCore = nil
        currentMediaURL = nil
        state = .idle
        // Run modal asynchronously so it doesn't block the main runloop during
        // state teardown, and cannot race with any subsequent startPolling() call.
        Task { @MainActor in self.showDeviceLostAlert() }
      }
    }
  }

  // MARK: - Playback controls (forwarded from PlayerWindowController)

  func togglePlayPause() {
    guard case .casting(var s) = state else {
      Logger.log("[playback] togglePlayPause: not in casting state, ignored", level: .warning, subsystem: logger)
      return
    }
    let wasPlaying = s.isPlaying
    Logger.log("[playback] togglePlayPause: wasPlaying=\(wasPlaying) → flipping to \(!wasPlaying)", level: .debug, subsystem: logger)
    s.isPlaying = !wasPlaying
    state = .casting(session: s)
    Task {
      do {
        if wasPlaying {
          Logger.log("[playback] sending Pause to device", level: .debug, subsystem: logger)
          try await provider.pause()
          Logger.log("[playback] Pause sent OK", level: .debug, subsystem: logger)
        } else {
          Logger.log("[playback] sending Play to device", level: .debug, subsystem: logger)
          try await provider.play()
          Logger.log("[playback] Play sent OK", level: .debug, subsystem: logger)
        }
      } catch {
        Logger.log("[playback] command failed: \(error) — reverting isPlaying to \(wasPlaying)", level: .warning, subsystem: logger)
        guard case .casting(var s) = state else { return }
        s.isPlaying = wasPlaying
        state = .casting(session: s)
      }
    }
  }

  func seek(to position: TimeInterval) {
    Task { try? await provider.seek(to: position) }
  }

  func seek(relative seconds: TimeInterval) {
    guard let currentPosition = state.session?.position else { return }
    Task { try? await provider.seek(to: currentPosition + seconds) }
  }

  func setVolume(_ volume: Double) {
    Task { try? await provider.setVolume(volume) }
  }

  func toggleMute() {
    guard case .casting(var s) = state else { return }
    s.isMuted.toggle()
    state = .casting(session: s)
    Task { try? await provider.setMute(s.isMuted) }
  }

  // MARK: - Helpers

  private func cleanupServer() {
    if let path = registeredPath { server.unregister(path: path); registeredPath = nil }
  }

  private func cleanupTempFile() {
    if let tmp = currentTempFileURL {
      try? FileManager.default.removeItem(at: tmp)
      currentTempFileURL = nil
    }
  }

  private func showErrorAlert(_ error: CastingError) {
    let desc = error.localizedDescription ?? "\(error)"
    Logger.log("Casting error: \(desc)", level: .warning, subsystem: logger)
    let a = NSAlert()
    a.messageText = NSLocalizedString("casting.error.alert.title", comment: "")
    a.informativeText = desc
    a.runModal()
  }

  private func showDeviceLostAlert() {
    let a = NSAlert()
    a.messageText = NSLocalizedString("casting.error.device_lost.title", comment: "投屏已中断")
    a.informativeText = NSLocalizedString("casting.error.device_lost.message", comment: "")
    a.runModal()
  }

  // MARK: - CastingProviderDelegate

  nonisolated func provider(_ provider: any CastingProviderProtocol,
                            didDiscover device: any CastingDevice) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      var devices = self.state.discoveredDevices
      guard !devices.contains(where: { $0.id == device.id }) else { return }
      devices.append(device)
      self.state = .discovering(devices)
    }
  }

  nonisolated func provider(_ provider: any CastingProviderProtocol,
                            didLose device: any CastingDevice) {
    Task { @MainActor [weak self] in
      guard let self, !self.isCasting else { return }
      let filtered = self.state.discoveredDevices.filter { $0.id != device.id }
      self.state = .discovering(filtered)
    }
  }

  nonisolated func provider(_ provider: any CastingProviderProtocol,
                            didFailWithError error: CastingError) {
    Task { @MainActor [weak self] in self?.state = .error(error) }
  }
}

extension Notification.Name {
  static let castingStateDidChange = Notification.Name("iina.castingStateDidChange")
}
