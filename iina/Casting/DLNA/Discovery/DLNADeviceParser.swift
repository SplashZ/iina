import Foundation

final class DLNADevice: CastingDevice {
  let id: String
  let name: String
  let type = "DLNA"
  let avTransportControlURL: URL?
  let renderingControlURL: URL?

  init(id: String, name: String, avTransportControlURL: URL?, renderingControlURL: URL?) {
    self.id = id; self.name = name
    self.avTransportControlURL = avTransportControlURL
    self.renderingControlURL = renderingControlURL
  }
}

enum DLNADeviceParser {

  static func parse(xml: String, baseURL: URL) -> DLNADevice? {
    guard let data = xml.data(using: .utf8) else { return nil }
    let parser = XMLParser(data: data)
    let handler = Handler(baseURL: baseURL)
    parser.delegate = handler
    guard parser.parse() else { return nil }
    return handler.buildDevice()
  }

  private final class Handler: NSObject, XMLParserDelegate {
    private let baseURL: URL
    private var currentText = ""
    private var inService = false
    private var currentServiceType = ""
    private var currentControlURL = ""
    private var friendlyName = ""
    private var udn = ""
    private var avTransportControlURL: URL?
    private var renderingControlURL: URL?

    init(baseURL: URL) { self.baseURL = baseURL }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
      currentText = ""
      if name == "service" { inService = true; currentServiceType = ""; currentControlURL = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
      let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
      switch name {
      case "friendlyName": friendlyName = text
      case "UDN":          udn = text
      case "serviceType":  if inService { currentServiceType = text }
      case "controlURL":   if inService { currentControlURL = text }
      case "service":
        inService = false
        if currentServiceType.contains("AVTransport") {
          avTransportControlURL = URL(string: currentControlURL, relativeTo: baseURL)?.absoluteURL
        } else if currentServiceType.contains("RenderingControl") {
          renderingControlURL = URL(string: currentControlURL, relativeTo: baseURL)?.absoluteURL
        }
      default: break
      }
    }

    func buildDevice() -> DLNADevice? {
      guard avTransportControlURL != nil else { return nil }
      return DLNADevice(
        id: udn.isEmpty ? UUID().uuidString : udn,
        name: friendlyName.isEmpty ? "Unknown Device" : friendlyName,
        avTransportControlURL: avTransportControlURL,
        renderingControlURL: renderingControlURL
      )
    }
  }
}
