import Foundation
import Darwin

protocol SSDPClientDelegate: AnyObject {
  func ssdpClient(_ client: SSDPClient, didFindDeviceAt locationURL: URL)
}

final class SSDPClient {
  static let multicastHost = "239.255.255.250"
  static let multicastPort: UInt16 = 1900

  weak var delegate: SSDPClientDelegate?

  private var sockFd: Int32 = -1
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "iina.casting.ssdp", qos: .userInitiated)
  private let logger = Logger.makeSubsystem("casting.ssdp")

  func search(timeout: TimeInterval = 5) {
    cancel()
    queue.async { [weak self] in
      self?.runSearch(timeout: timeout)
    }
  }

  func cancel() {
    lock.lock()
    let fd = sockFd
    sockFd = -1
    lock.unlock()
    if fd >= 0 { Darwin.close(fd) }
  }

  // MARK: - Static helpers（便于单元测试）

  static func buildMSearchMessage(maxWait: Int = 3) -> String {
    ["M-SEARCH * HTTP/1.1",
     "HOST: \(multicastHost):\(multicastPort)",
     "MAN: \"ssdp:discover\"",
     "MX: \(maxWait)",
     "ST: urn:schemas-upnp-org:device:MediaRenderer:1",
     "", ""].joined(separator: "\r\n")
  }

  static func parseLocation(from response: String) -> URL? {
    for line in response.components(separatedBy: "\r\n") {
      if line.lowercased().hasPrefix("location:") {
        let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
        return URL(string: value)
      }
    }
    return nil
  }

  // MARK: - Private

  private func runSearch(timeout: TimeInterval) {
    // Create UDP socket
    let s = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
    guard s >= 0 else {
      Logger.log("SSDP: failed to create socket (errno=\(errno))", level: .warning, subsystem: logger)
      return
    }

    lock.lock()
    sockFd = s
    lock.unlock()

    // SO_REUSEADDR
    var opt: Int32 = 1
    Darwin.setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

    // Per-recv timeout of 1 second (loop until overall timeout)
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    Darwin.setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    // Bind to INADDR_ANY:0
    var localAddr = sockaddr_in()
    localAddr.sin_family = sa_family_t(AF_INET)
    localAddr.sin_port = 0
    localAddr.sin_addr.s_addr = INADDR_ANY
    let bindOK = withUnsafePointer(to: &localAddr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
      }
    }
    guard bindOK else {
      Logger.log("SSDP: bind failed (errno=\(errno))", level: .warning, subsystem: logger)
      Darwin.close(s)
      lock.lock(); if sockFd == s { sockFd = -1 }; lock.unlock()
      return
    }

    // Send M-SEARCH to multicast group
    let msg = Self.buildMSearchMessage()
    guard let msgData = msg.data(using: .utf8) else {
      Darwin.close(s)
      lock.lock(); if sockFd == s { sockFd = -1 }; lock.unlock()
      return
    }

    var destAddr = sockaddr_in()
    destAddr.sin_family = sa_family_t(AF_INET)
    destAddr.sin_port = Self.multicastPort.bigEndian
    inet_pton(AF_INET, Self.multicastHost, &destAddr.sin_addr)

    msgData.withUnsafeBytes { msgPtr in
      withUnsafePointer(to: &destAddr) { destPtr in
        destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
          let _ = Darwin.sendto(s, msgPtr.baseAddress, msgData.count, 0,
                                sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
    }
    Logger.log("SSDP: M-SEARCH sent", level: .debug, subsystem: logger)

    // Receive loop — recvfrom returns packets from any source address (device responses)
    var buffer = [UInt8](repeating: 0, count: 4096)
    var fromAddr = sockaddr_in()
    var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      let n: Int = buffer.withUnsafeMutableBytes { bufPtr in
        withUnsafeMutablePointer(to: &fromAddr) { fromPtr in
          fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.recvfrom(s, bufPtr.baseAddress, bufPtr.count, 0, sockPtr, &fromLen)
          }
        }
      }

      if n <= 0 {
        // EAGAIN / EWOULDBLOCK = per-recv timeout expired, keep looping
        if errno == EAGAIN || errno == EWOULDBLOCK { continue }
        break  // socket closed (cancel()) or unrecoverable error
      }

      if let response = String(bytes: buffer.prefix(n), encoding: .utf8),
         let location = Self.parseLocation(from: response) {
        Logger.log("SSDP: found device at \(location)", level: .debug, subsystem: logger)
        let loc = location
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.delegate?.ssdpClient(self, didFindDeviceAt: loc)
        }
      }
    }

    Darwin.close(s)
    lock.lock(); if sockFd == s { sockFd = -1 }; lock.unlock()
    Logger.log("SSDP: search finished", level: .debug, subsystem: logger)
  }
}
