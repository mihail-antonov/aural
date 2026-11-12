import Darwin
import Foundation

/// Checks macOS "Local Network" privacy access for Aural.
///
/// Soloist (a child process of Aural) uses multicast DNS so the Spotify app can
/// find it. macOS attributes that traffic to Aural; without permission the
/// packets are silently dropped and the device never appears. Soloist does not
/// report this, so Aural checks it itself by sending one mDNS query — which also
/// makes macOS show its permission prompt early, during setup.
public enum LocalNetworkAccess {
    public enum Status: Sendable, Equatable {
        case allowed
        /// Denied, or the permission prompt has not been answered yet.
        case blocked
        /// The check itself failed for another reason (e.g. no network).
        case unknown
    }

    /// Opens Privacy & Security → Local Network in System Settings.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")! // constant literal

    /// Sends a standard mDNS query for Spotify Connect devices to 224.0.0.251:5353.
    public static func check() -> Status {
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return .unknown }
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(5353).bigEndian
        address.sin_addr.s_addr = inet_addr("224.0.0.251")

        let packet = mdnsQuery(for: "_spotify-connect._tcp.local")
        // `sendto` takes a generic `sockaddr` pointer; `withMemoryRebound`
        // reinterprets our `sockaddr_in` as one (the C idiom of casting).
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent >= 0 { return .allowed }
        // EHOSTUNREACH ("No route to host") is what macOS returns when Local Network access is not granted.
        return errno == EHOSTUNREACH ? .blocked : .unknown
    }

    /// A DNS query packet: 12-byte header with one question, then the PTR question.
    static func mdnsQuery(for name: String) -> [UInt8] {
        var packet: [UInt8] = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0] // id 0, flags 0, 1 question
        for label in name.split(separator: ".") {
            packet.append(UInt8(label.utf8.count))
            packet.append(contentsOf: label.utf8)
        }
        packet.append(0)                         // end of name
        packet.append(contentsOf: [0, 12, 0, 1]) // type PTR, class IN
        return packet
    }
}
