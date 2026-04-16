import Foundation

final class AVTransportService {
  private let controlURL: URL
  private let soap: SOAPClient
  private let svcType = "urn:schemas-upnp-org:service:AVTransport:1"
  private let logger = Logger.makeSubsystem("casting.avtransport")

  init(controlURL: URL, soapClient: SOAPClient = SOAPClient()) {
    self.controlURL = controlURL
    self.soap = soapClient
  }

  func setAVTransportURI(mediaURL: URL, metadata: String = "") async throws {
    _ = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                              action: "SetAVTransportURI",
                              arguments: [
                                "InstanceID": "0",
                                "CurrentURI": mediaURL.absoluteString,
                                "CurrentURIMetaData": metadata
                              ])
  }

  func play() async throws {
    Logger.log("[playback] AVTransport Play → \(controlURL)", level: .debug, subsystem: logger)
    let result = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                                       action: "Play",
                                       arguments: ["InstanceID": "0", "Speed": "1"])
    Logger.log("[playback] AVTransport Play response: \(result)", level: .debug, subsystem: logger)
  }

  func pause() async throws {
    Logger.log("[playback] AVTransport Pause → \(controlURL)", level: .debug, subsystem: logger)
    let result = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                                       action: "Pause",
                                       arguments: ["InstanceID": "0"])
    Logger.log("[playback] AVTransport Pause response: \(result)", level: .debug, subsystem: logger)
  }

  func stop() async throws {
    _ = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                              action: "Stop",
                              arguments: ["InstanceID": "0"])
  }

  func seek(to position: TimeInterval) async throws {
    let target = Self.formatTime(position)
    do {
      _ = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                                action: "Seek",
                                arguments: [
                                  "InstanceID": "0",
                                  "Unit": "ABS_TIME",
                                  "Target": target
                                ])
    } catch {
      // Some devices (e.g. Kodi) reject ABS_TIME — fall back to REL_TIME.
      // This works when the device just started from position 0 (REL_TIME == ABS_TIME).
      Logger.log("AVTransport Seek ABS_TIME failed, retrying with REL_TIME: \(error)",
                 level: .warning, subsystem: logger)
      _ = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                                action: "Seek",
                                arguments: [
                                  "InstanceID": "0",
                                  "Unit": "REL_TIME",
                                  "Target": target
                                ])
    }
  }

  func getTransportState() async throws -> String {
    let result = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                                       action: "GetTransportInfo",
                                       arguments: ["InstanceID": "0"])
    return result["CurrentTransportState"] ?? "UNKNOWN"
  }

  func getPositionInfo() async throws -> (position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
    let posResult = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                                          action: "GetPositionInfo",
                                          arguments: ["InstanceID": "0"])
    let transportState = try await getTransportState()
    let isPlaying = transportState == "PLAYING"
    Logger.log("[playback] AVTransport GetPositionInfo: pos=\(posResult["RelTime"] ?? "?") dur=\(posResult["TrackDuration"] ?? "?") transportState=\(transportState) isPlaying=\(isPlaying)", level: .debug, subsystem: logger)
    return (Self.parseTime(posResult["RelTime"] ?? "0:00:00"),
            Self.parseTime(posResult["TrackDuration"] ?? "0:00:00"),
            isPlaying)
  }

  // MARK: - Static time helpers（便于单元测试）

  static func formatTime(_ seconds: TimeInterval) -> String {
    let t = Int(max(0, seconds))
    return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
  }

  static func parseTime(_ s: String) -> TimeInterval {
    let p = s.split(separator: ":").compactMap { Double($0) }
    guard p.count == 3 else { return 0 }
    return p[0] * 3600 + p[1] * 60 + p[2]
  }
}
