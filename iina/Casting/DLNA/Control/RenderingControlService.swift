import Foundation

final class RenderingControlService {
  private let controlURL: URL
  private let soap: SOAPClient
  private let svcType = "urn:schemas-upnp-org:service:RenderingControl:1"

  init(controlURL: URL, soapClient: SOAPClient = SOAPClient()) {
    self.controlURL = controlURL
    self.soap = soapClient
  }

  func setVolume(_ volume: Double) async throws {
    let v = Int(min(1.0, max(0.0, volume)) * 100)
    _ = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                              action: "SetVolume",
                              arguments: [
                                "InstanceID": "0",
                                "Channel": "Master",
                                "DesiredVolume": "\(v)"
                              ])
  }

  func setMute(_ muted: Bool) async throws {
    _ = try await soap.invoke(controlURL: controlURL, serviceType: svcType,
                              action: "SetMute",
                              arguments: [
                                "InstanceID": "0",
                                "Channel": "Master",
                                "DesiredMute": muted ? "1" : "0"
                              ])
  }
}
