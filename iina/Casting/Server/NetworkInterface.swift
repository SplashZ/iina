import Foundation
import Darwin

enum NetworkInterface {
  static func lanIPAddress() throws -> String {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { throw CastingError.noNetworkInterface }
    defer { freeifaddrs(ifaddr) }

    var ptr = ifaddr
    while let cur = ptr {
      let iface = cur.pointee
      if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
        let name = String(cString: iface.ifa_name)
        if name.hasPrefix("en") {
          var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
          getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                      &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
          let ip = String(cString: hostname)
          if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") && !ip.isEmpty {
            return ip
          }
        }
      }
      ptr = cur.pointee.ifa_next
    }
    throw CastingError.noNetworkInterface
  }
}
