import Foundation

protocol URLSessionProtocol {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
extension URLSession: URLSessionProtocol {}

final class SOAPClient {
  private let session: any URLSessionProtocol
  private let logger = Logger.makeSubsystem("casting.soap")

  init(session: any URLSessionProtocol = URLSession.shared) { self.session = session }

  /// arguments uses KeyValuePairs to preserve insertion order (UPnP requires spec-defined order)
  func invoke(controlURL: URL, serviceType: String, action: String,
              arguments: KeyValuePairs<String, String>) async throws -> [String: String] {
    let body = buildBody(serviceType: serviceType, action: action, arguments: arguments)
    guard let bodyData = body.data(using: .utf8) else {
      throw CastingError.controlFailed("Failed to encode SOAP body")
    }

    var req = URLRequest(url: controlURL, timeoutInterval: 15)
    req.httpMethod = "POST"
    req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
    req.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPAction")
    req.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")
    req.httpBody = bodyData

    Logger.log("SOAP \(action) → \(controlURL)", level: .debug, subsystem: logger)

    do {
      let (data, response) = try await session.data(for: req)
      guard let http = response as? HTTPURLResponse else {
        throw CastingError.controlFailed(NSLocalizedString("casting.error.non_http_response", comment: ""))
      }
      Logger.log("SOAP \(action) ← HTTP \(http.statusCode)", level: .debug, subsystem: logger)
      guard (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        Logger.log("SOAP error body: \(body)", level: .warning, subsystem: logger)
        throw CastingError.controlFailed("HTTP \(http.statusCode)")
      }
      return parseResponse(data: data)
    } catch let e as CastingError { throw e
    } catch {
      Logger.log("SOAP \(action) error: \(error)", level: .warning, subsystem: logger)
      throw CastingError.controlFailed(error.localizedDescription)
    }
  }

  private func buildBody(serviceType: String, action: String,
                         arguments: KeyValuePairs<String, String>) -> String {
    // Use ordered array — dict iteration order is non-deterministic and breaks strict DLNA devices
    let args = arguments.map { "<\($0.key)>\($0.value)</\($0.key)>" }.joined()
    return """
    <?xml version="1.0" encoding="utf-8"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <s:Body><u:\(action) xmlns:u="\(serviceType)">\(args)</u:\(action)></s:Body>
    </s:Envelope>
    """
  }

  private static let responseRegex: NSRegularExpression = {
    // Force-try is safe here: the pattern is a compile-time constant that is always valid.
    try! NSRegularExpression(pattern: "<([^/:][^>]*)>([^<]+)</[^>]+>")
  }()

  private func parseResponse(data: Data) -> [String: String] {
    guard let xml = String(data: data, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    let regex = Self.responseRegex
    for match in regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
      if let kRange = Range(match.range(at: 1), in: xml),
         let vRange = Range(match.range(at: 2), in: xml) {
        result[String(xml[kRange])] = String(xml[vRange])
      }
    }
    return result
  }
}
