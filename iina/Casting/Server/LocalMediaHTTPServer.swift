import Network
import Foundation

final class LocalMediaHTTPServer {
  private var listener: NWListener?
  private var registrations: [String: URL] = [:]
  private let lock = NSLock()
  // Listener-only queue — kept lightweight so new connections are accepted immediately
  private let listenerQueue = DispatchQueue(label: "iina.casting.httpserver.listener", qos: .userInitiated)
  private let logger = Logger.makeSubsystem("casting.httpserver")
  private let preferredPort: UInt16

  var port: UInt16 { listener?.port?.rawValue ?? 0 }

  init(port: UInt16 = 8765) { self.preferredPort = port }

  func start() throws {
    guard let nwPort = preferredPort == 0
            ? NWEndpoint.Port.any
            : NWEndpoint.Port(rawValue: preferredPort) else {
      throw CastingError.connectionFailed("Invalid port: \(preferredPort)")
    }
    let l = try NWListener(using: .tcp, on: nwPort)
    listener = l
    l.newConnectionHandler = { [weak self] in self?.handleConnection($0) }
    let sem = DispatchSemaphore(value: 0)
    l.stateUpdateHandler = { state in
      switch state {
      case .ready, .failed, .cancelled: sem.signal()
      default: break
      }
    }
    l.start(queue: listenerQueue)
    _ = sem.wait(timeout: .now() + 5)
    Logger.log("LocalMediaHTTPServer: listening on port \(port)", level: .debug, subsystem: logger)
  }

  func stop() {
    listener?.cancel()
    listener = nil
    lock.lock()
    registrations.removeAll()
    lock.unlock()
  }

  func register(fileURL: URL) -> String {
    // Include the original file extension so DLNA devices can determine the format from the URL
    let ext = fileURL.pathExtension
    let suffix = ext.isEmpty ? "" : ".\(ext)"
    let path = "/media/\(UUID().uuidString)\(suffix)"
    lock.lock()
    registrations[path] = fileURL
    lock.unlock()
    return path
  }

  func unregister(path: String) {
    lock.lock()
    registrations.removeValue(forKey: path)
    lock.unlock()
  }

  func mediaURL(for path: String) -> URL? {
    guard let ip = try? NetworkInterface.lanIPAddress() else { return nil }
    return URL(string: "http://\(ip):\(port)\(path)")
  }

  // MARK: - HTTP

  private func handleConnection(_ connection: NWConnection) {
    Logger.log("LocalMediaHTTPServer: connection from \(connection.endpoint)", level: .debug, subsystem: logger)
    // Each connection gets its own serial queue so file I/O on one connection
    // never delays accepting or serving other connections.
    let connQueue = DispatchQueue(label: "iina.casting.httpserver.conn", qos: .userInitiated)
    connection.start(queue: connQueue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
      guard let self, let data, !data.isEmpty else { connection.cancel(); return }
      self.processRequest(data: data, connection: connection)
    }
  }

  private func processRequest(data: Data, connection: NWConnection) {
    guard let text = String(data: data, encoding: .utf8) else {
      respondSimple(connection, status: 400); return
    }
    let lines = text.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { respondSimple(connection, status: 400); return }

    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2 else { respondSimple(connection, status: 400); return }
    let method = String(parts[0]).uppercased()
    let path = String(parts[1])

    Logger.log("LocalMediaHTTPServer: \(method) \(path)", level: .debug, subsystem: logger)

    let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
      .map { String($0.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)) }

    lock.lock()
    let fileURL = registrations[path]
    lock.unlock()
    guard let fileURL else {
      Logger.log("LocalMediaHTTPServer: 404 \(path)", level: .debug, subsystem: logger)
      respondSimple(connection, status: 404); return
    }

    serveFile(at: fileURL, method: method, range: rangeHeader, connection: connection)
  }

  private func serveFile(at url: URL, method: String, range: String?, connection: NWConnection) {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let fileSize = attrs[.size] as? Int else {
      respondSimple(connection, status: 500); return
    }
    let mimeType = Self.mimeType(for: url)

    // HEAD: metadata only — no file I/O
    if method == "HEAD" {
      Logger.log("LocalMediaHTTPServer: HEAD → 200 size=\(fileSize) type=\(mimeType)", level: .debug, subsystem: logger)
      sendHeaders(connection, status: 200, extraHeaders: [
        "Content-Length": "\(fileSize)",
        "Content-Type": mimeType,
        "Accept-Ranges": "bytes"
      ], thenClose: true)
      return
    }

    guard let fh = try? FileHandle(forReadingFrom: url) else {
      respondSimple(connection, status: 500); return
    }

    if let range, range.lowercased().hasPrefix("bytes=") {
      let spec = String(range.dropFirst("bytes=".count))
      let rangeParts = spec.split(separator: "-", maxSplits: 1)
      let start = Int(rangeParts.first ?? "") ?? 0
      let requestedEnd = rangeParts.count > 1 && !rangeParts[1].isEmpty
        ? (Int(rangeParts[1]) ?? (fileSize - 1)) : (fileSize - 1)
      let clampedEnd = min(requestedEnd, fileSize - 1)
      let totalLength = max(0, clampedEnd - start + 1)

      Logger.log("LocalMediaHTTPServer: GET Range → 206 bytes=\(start)-\(clampedEnd)/\(fileSize) (\(totalLength) bytes)", level: .debug, subsystem: logger)
      sendHeaders(connection, status: 206, extraHeaders: [
        "Content-Range": "bytes \(start)-\(clampedEnd)/\(fileSize)",
        "Content-Length": "\(totalLength)",
        "Content-Type": mimeType,
        "Accept-Ranges": "bytes"
      ], thenClose: false)

      // Stream the range in chunks — never read the whole (potentially GB-sized) range at once
      try? fh.seek(toOffset: UInt64(start))
      sendChunks(fh: fh, remaining: totalLength, connection: connection)

    } else {
      Logger.log("LocalMediaHTTPServer: GET full → 200 size=\(fileSize)", level: .debug, subsystem: logger)
      sendHeaders(connection, status: 200, extraHeaders: [
        "Content-Length": "\(fileSize)",
        "Content-Type": mimeType,
        "Accept-Ranges": "bytes"
      ], thenClose: false)
      sendChunks(fh: fh, remaining: fileSize, connection: connection)
    }
  }

  // Stream file data in 256 KB chunks so the connection queue stays free between sends.
  // Uses an explicit async dispatch rather than direct recursion to avoid unbounded call
  // stack growth over thousands of chunks (e.g. a 5 GB file ≈ 20 000 chunks).
  // The FileHandle is closed exactly once: either when remaining reaches 0, when the
  // read returns empty, or on the first send error — guarded by a single close point
  // at each exit so it is never closed more than once per streaming session.
  private func sendChunks(fh: FileHandle, remaining: Int, connection: NWConnection) {
    guard remaining > 0 else {
      try? fh.close()
      connection.cancel()
      return
    }
    let chunk = fh.readData(ofLength: min(remaining, 262_144))
    guard !chunk.isEmpty else {
      try? fh.close()
      connection.cancel()
      return
    }
    connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
      // Close the file handle and cancel the connection on error OR if the server was
      // deallocated (self == nil). Using separate conditions avoids accidentally closing
      // the handle when self is nil but there is no error (which would be a silent bug).
      guard error == nil, let self else {
        try? fh.close()
        connection.cancel()
        return
      }
      // Dispatch next iteration asynchronously to break the direct recursion chain
      let next = remaining - chunk.count
      DispatchQueue.global(qos: .userInitiated).async {
        self.sendChunks(fh: fh, remaining: next, connection: connection)
      }
    })
  }

  // MARK: - Response helpers

  private func sendHeaders(_ connection: NWConnection, status: Int,
                           extraHeaders: [String: String], thenClose: Bool) {
    let phrase = [200: "OK", 206: "Partial Content", 400: "Bad Request",
                  404: "Not Found", 500: "Internal Server Error"][status] ?? "Unknown"
    let hdrLines = extraHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
    let raw = "HTTP/1.1 \(status) \(phrase)\r\n\(hdrLines)\r\n\r\n"
    let data = raw.data(using: .utf8)!
    if thenClose {
      connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    } else {
      connection.send(content: data, completion: .contentProcessed { _ in })
    }
  }

  private func respondSimple(_ connection: NWConnection, status: Int) {
    sendHeaders(connection, status: status, extraHeaders: ["Content-Length": "0"], thenClose: true)
  }

  // MARK: - MIME type

  static func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "mp4", "m4v":          return "video/mp4"
    case "mkv":                  return "video/x-matroska"
    case "avi":                  return "video/x-msvideo"
    case "mov":                  return "video/quicktime"
    case "mpg", "mpeg":          return "video/mpeg"
    case "ts", "m2ts", "mts":   return "video/MP2T"
    case "wmv":                  return "video/x-ms-wmv"
    case "flv":                  return "video/x-flv"
    case "webm":                 return "video/webm"
    case "mp3":                  return "audio/mpeg"
    case "flac":                 return "audio/flac"
    case "aac":                  return "audio/aac"
    case "ogg", "oga":           return "audio/ogg"
    case "wav":                  return "audio/wav"
    case "m4a":                  return "audio/mp4"
    default:                     return "application/octet-stream"
    }
  }
}
