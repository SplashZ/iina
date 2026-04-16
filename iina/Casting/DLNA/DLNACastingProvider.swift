import Foundation

final class DLNACastingProvider: NSObject, CastingProviderProtocol {
  weak var delegate: (any CastingProviderDelegate)?

  private let ssdpClient: SSDPClient
  // Serial queue protects discoveredDevices from concurrent SSDP callbacks
  private let discoveryQueue = DispatchQueue(label: "iina.casting.dlna.discovery")
  private var discoveredDevices: [String: DLNADevice] = [:]
  private let logger = Logger.makeSubsystem("casting.dlna")

  private var avTransport: AVTransportService?
  private var renderingControl: RenderingControlService?

  init(ssdpClient: SSDPClient = SSDPClient()) {
    self.ssdpClient = ssdpClient
    super.init()
    self.ssdpClient.delegate = self
  }

  func startDiscovery() {
    ssdpClient.cancel()
    discoveryQueue.sync { discoveredDevices.removeAll() }
    ssdpClient.search()
  }

  func stopDiscovery() { ssdpClient.cancel() }

  func cast(mediaURL: URL, to device: any CastingDevice, startAt: TimeInterval) async throws {
    guard let dlna = device as? DLNADevice,
          let avURL = dlna.avTransportControlURL else {
      throw CastingError.connectionFailed(NSLocalizedString("casting.error.no_avtransport", comment: ""))
    }
    avTransport = AVTransportService(controlURL: avURL)
    if let rcURL = dlna.renderingControlURL {
      renderingControl = RenderingControlService(controlURL: rcURL)
    }
    Logger.log("DLNACastingProvider: casting mediaURL=\(mediaURL)", level: .debug, subsystem: logger)
    let metadata = Self.buildDIDLMetadata(mediaURL: mediaURL)
    try await avTransport?.setAVTransportURI(mediaURL: mediaURL, metadata: metadata)

    // Poll GetTransportInfo until device reaches STOPPED/PLAYING (media loaded), max 8s.
    // Only keep polling while TRANSITIONING; break immediately on any stable state
    // (STOPPED, PLAYING, NO_MEDIA_PRESENT). Lazy-load devices stay NO_MEDIA_PRESENT
    // until they receive Play — no point waiting further.
    var lastState = "UNKNOWN"
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
      try await Task.sleep(nanoseconds: 500_000_000)
      lastState = (try? await avTransport?.getTransportState()) ?? "UNKNOWN"
      Logger.log("DLNACastingProvider: transport state = \(lastState)", level: .debug, subsystem: logger)
      if lastState == "TRANSITIONING" { continue }
      break
    }

    // Some devices are lazy-loaders: they stay in NO_MEDIA_PRESENT until Play is called,
    // only fetching the media after receiving Play. Just log and proceed.
    if lastState == "NO_MEDIA_PRESENT" {
      Logger.log("DLNACastingProvider: device still NO_MEDIA_PRESENT — attempting Play (lazy-load device)",
                 level: .debug, subsystem: logger)
    }

    // If the device is already PLAYING (some devices auto-play after SetAVTransportURI),
    // skip Play to avoid resetting the playback position to 0.
    if lastState != "PLAYING" {
      Logger.log("DLNACastingProvider: sending Play", level: .debug, subsystem: logger)
      try await avTransport?.play()
    } else {
      Logger.log("DLNACastingProvider: device already PLAYING, skipping Play", level: .debug, subsystem: logger)
    }

    if startAt > 0 {
      // Wait until transport is PLAYING before seeking, rather than using a fixed delay.
      let seekDeadline = Date().addingTimeInterval(3)
      while Date() < seekDeadline {
        try await Task.sleep(nanoseconds: 200_000_000)
        let s = (try? await avTransport?.getTransportState()) ?? "UNKNOWN"
        if s == "PLAYING" { break }
      }
      do {
        try await avTransport?.seek(to: startAt)
      } catch {
        Logger.log("DLNACastingProvider: seek failed (non-fatal, device will play from start): \(error)",
                   level: .warning, subsystem: logger)
      }
    }
  }

  func play() async throws {
    Logger.log("[playback] DLNACastingProvider.play() called", level: .debug, subsystem: logger)
    try await avTransport?.play()
  }

  func pause() async throws {
    Logger.log("[playback] DLNACastingProvider.pause() called", level: .debug, subsystem: logger)
    try await avTransport?.pause()
  }
  func seek(to position: TimeInterval) async throws { try await avTransport?.seek(to: position) }
  func setVolume(_ volume: Double) async throws { try await renderingControl?.setVolume(volume) }
  func setMute(_ muted: Bool) async throws { try await renderingControl?.setMute(muted) }

  func stopCasting() async throws {
    try await avTransport?.stop()
    avTransport = nil
    renderingControl = nil
  }

  func getPositionInfo() async throws -> (position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
    guard let av = avTransport else { return (0, 0, false) }
    return try await av.getPositionInfo()
  }

  // MARK: - DLNA metadata

  /// Builds minimal DIDL-Lite XML so the device knows the content type and protocol.
  /// Without this, many devices refuse to load the URL.
  private static func buildDIDLMetadata(mediaURL: URL) -> String {
    let mime = LocalMediaHTTPServer.mimeType(for: mediaURL)
    let upnpClass = mime.hasPrefix("audio") ? "object.item.audioItem.musicTrack"
                                            : "object.item.videoItem"
    let title = mediaURL.deletingPathExtension().lastPathComponent
    let escapedURL = mediaURL.absoluteString
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
    let escapedTitle = title
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
    return "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" " +
           "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" " +
           "xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">" +
           "<item id=\"0\" parentID=\"-1\" restricted=\"1\">" +
           "<dc:title>\(escapedTitle)</dc:title>" +
           "<upnp:class>\(upnpClass)</upnp:class>" +
           "<res protocolInfo=\"http-get:*:\(mime):*\">\(escapedURL)</res>" +
           "</item></DIDL-Lite>"
  }

}

extension DLNACastingProvider: SSDPClientDelegate {
  func ssdpClient(_ client: SSDPClient, didFindDeviceAt locationURL: URL) {
    // Fetch device description XML asynchronously so multiple devices load in parallel
    // instead of serializing all HTTP round-trips on a single queue.
    // Dictionary mutation is still protected via a sync block on discoveryQueue.
    Task { [weak self] in
      guard let self else { return }
      var req = URLRequest(url: locationURL, timeoutInterval: 10)
      req.httpMethod = "GET"
      guard let (data, _) = try? await URLSession.shared.data(for: req),
            let xml = String(data: data, encoding: .utf8),
            let device = DLNADeviceParser.parse(xml: xml, baseURL: locationURL) else { return }
      var isNew = false
      self.discoveryQueue.sync {
        guard self.discoveredDevices[device.id] == nil else { return }
        self.discoveredDevices[device.id] = device
        isNew = true
      }
      guard isNew else { return }
      self.delegate?.provider(self, didDiscover: device)
    }
  }
}
