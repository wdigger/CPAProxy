//  TorConfiguration.swift
//
//  Copyright (c) 2013 Claudiu-Vlad Ursache.
//  See LICENCE for licensing information
//

import Foundation

public class TorConfigurationError: Error {
}

/**
`TorConfiguration` handles data used used by `TorThread` and `TorProxyManager`.
 It provides information like the temporary directory to be used for storing the
 Tor clients's data, control port, SOCKS port and paths to torrc and geoip.
 
*/

public class TorConfiguration {
    /**
     The port for the Tor SOCKS proxy.
     */
    var socksPortInt: UInt16?
    public var socksPort: UInt16 {
        get {
            guard let socksPortInt = socksPortInt else {
                if useDefaultSocksPort {
                    return 9050
                } else {
                    self.socksPortInt = UInt16((arc4random() % 1000) + 60000)
                    return self.socksPortInt!
                }
            }
            return socksPortInt
        }
        set(port) {
            socksPortInt = port
        }
    }

    /** If set, socksPort will be 9050 */
    var useDefaultSocksPort = false

    /**
     The hostname for the Tor SOCKS proxy.
     */
    public var socksHost: String {
        return "127.0.0.1"
    }

    /**
     The control port used by a Tor client.
     */
    public var controlPort: UInt16 {
        return socksPort + 1
    }

    /**
     Returns the control auth cookie saved by the Tor client on startup.
     If the Tor client has not been started, this will be nil.
     */
    var torCookieData: Data? {
        let controlAuthCookie = torDataDirectoryPath + "/" + "control_auth_cookie"
        let cookie = try? Data(contentsOf: URL(fileURLWithPath: controlAuthCookie))
        return cookie
    }

    /**
     Returns the Tor control auth cookie as hex.
     */
    public var torCookieDataAsHex: String? {
        guard let torCookieData = torCookieData else { return nil }
        return torCookieData.map { String(format: "%02hhx", $0) }.joined()
    }

    /**
     Returns the path to the Tor data directory.
     */
    var torDataDirectoryPath: String

    /**
     Returns the path to the torrc file.
     */
    public var torrcPath: String?

    /**
     Returns the path to the geoip file.
     */
    public var geoipPath: String?

    /**
     *  Don’t share circuits with streams targetting a different destination port.
     *  See IsolateDestPort in https://www.torproject.org/docs/tor-manual.html.en for more details.
     *  Defaults to NO.
     */
    var isolateDestinationPort = false

    /**
     *  Don’t share circuits with streams targetting a different destination address.
     *  See IsolateDestAddr in https://www.torproject.org/docs/tor-manual.html.en for more details.
     *  Defaults to NO.
     */
    var isolateDestinationAddress = false

    public init(torrcPath: String, geoipPath: String) throws {
        torDataDirectoryPath = try TorConfiguration.createCachesDirectory()
        self.torrcPath = torrcPath
        self.geoipPath = geoipPath
    }

    private static func createCachesDirectory() throws -> String {
        guard var cachesDirectory = FileManager.default.urls(for: .cachesDirectory,
                                                             in: .userDomainMask).first else {
            throw TorConfigurationError()
        }
        cachesDirectory.appendPathComponent("tor")
        try? FileManager.default.createDirectory(at: cachesDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        return cachesDirectory.path
    }
}
