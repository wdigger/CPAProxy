//  TorThread.swift
//
//  Copyright (c) 2013 Claudiu-Vlad Ursache.
//  See LICENCE for licensing information
//

import Foundation

class TorThread: Thread {
    var configuration: TorConfiguration

    let kTorArgsValueIsolateDestPort = "IsolateDestPort"
    let kTorArgsValueIsolateDestAddr = "IsolateDestAddr"
    let kTorArgsKeyARG0 = "tor"
    let kTorArgsKeyDataDirectory = "DataDirectory"
    let kTorArgsKeyControlPort = "ControlPort"
    let kTorArgsKeyKeySOCKSPort = "SocksPort"
    let kTorArgsKeyGeoIPFile = "GeoIPFile"
    let kTorArgsKeyTorrcFile = "-f"
    let kTorArgsKeyLog = "Log"
#if DEBUG
    let kTorArgsValueLogLevel = "warn stderr"
#else
    let kTorArgsValueLogLevel = "notice stderr"
#endif

    init(configuration: TorConfiguration) {
        self.configuration = configuration
        super.init()
    }

    override func main() {
        var socksPort = "localhost:\(configuration.socksPort)"
        if configuration.isolateDestinationAddress {
            socksPort += " " + kTorArgsValueIsolateDestAddr
        }
        if configuration.isolateDestinationPort {
            socksPort += " " + kTorArgsValueIsolateDestPort
        }

        let params = [kTorArgsKeyARG0,
                      kTorArgsKeyDataDirectory, configuration.torDataDirectoryPath,
                      kTorArgsKeyControlPort, "\(configuration.controlPort)",
                      kTorArgsKeyKeySOCKSPort, socksPort,
                      kTorArgsKeyGeoIPFile, configuration.geoipPath,
                      kTorArgsKeyTorrcFile, configuration.torrcPath,
                      kTorArgsKeyLog, kTorArgsValueLogLevel]
        TorMain(params as [Any])
    }
}
