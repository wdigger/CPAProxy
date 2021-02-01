//  TorProxyManager.swift
//
//  Copyright (c) 2013 Claudiu-Vlad Ursache.
//  See LICENCE for licensing information
//

import Foundation

public class TorProxyManager {
    // Tor connnection states
    enum Status {
        case closed
        case connecting
        case open
    }

    public typealias BootstrapCompletionBlock = (_ socksHost: String?, _ socksPort: UInt, _ error: Error?) -> Void
    public typealias BootstrapProgressBlock = (_ progress: UInt, _ summaryString: String?) -> Void

    /**
     The thread used for wrapping the Tor client.
     */
    private var torThread: TorThread

    /**
     The configuration object being used by this instance of `CPAProxyManager`. This is usually set at initialization.
     */
    private var configuration: TorConfiguration

    /**
     Returns bootstrap connection status of Tor
     */
    var status: Status = .closed

    /**
     *  Returns whether or not CPAProxyManager thinks Tor is fully connected.
     *  Shortcut for status == CPAStatusOpen
     */
    var isConnected: Bool {
        return (status == .open)
    }

    /**
     Convenience method that returns the configuration's SOCKS host
     */
    var socksHost: String {
        return configuration.socksHost
    }

    /**
     Convenience method that returns the configuration's SOCKS port
     */
    var SOCKSPort: UInt16 {
        return configuration.socksPort
    }

    /**
     The socket manager that writes and reads data from the Tor client's control port.
     */
    var socketManager: TorControlConnection?

    public var opensslVersion: String? {
        return getOpenSSLVersion()
    }

    public var libeventVersion: String? {
        return getLibEventVersion()
    }

    public var torVersion: String? {
        return getTorVersion()
    }

    let CPAConnectToTorSocketDelay = TimeInterval(0.2) // Amount of time to wait before attempting to connect again
    let CPATimeoutDelay = TimeInterval(60 * 3) // Sometimes Tor takes a long time to bootstrap
    let CPAMaxNumberControlConnectionAttempts = 10 // Max number of retries before firing an error

    enum CPAError: Error {
        case CPAErrorTorrcOrGeoipPathNotSet(String)
        case CPAErrorTorAuthenticationFailed(String)
        case CPAErrorSocketOpenFailed(String)
        case CPAErrorTorSetupTimedOut(String)
    }

    enum CPAControlPortStatus {
        case closed
        case connecting
        case authenticated
    }

    var timeoutTimer: Timer?

    var completionBlock: BootstrapCompletionBlock?
    var progressBlock: BootstrapProgressBlock?
    var callbackQueue: DispatchQueue?
    var workQueue: DispatchQueue?

    var controlPortStatus: CPAControlPortStatus = .closed
    var bootstrapProgress: UInt = 0
    var controlPortConnectionAttempts = 0

    public init(configuration: TorConfiguration) {
        self.configuration = configuration
        torThread = TorThread(configuration: configuration)
        socketManager = TorControlConnection(delegate: self)

        socketManager?.registerEvent(
            TorEventStatus { [weak self] (event, _) in
                guard let self = self else { return }
                guard let eventStatus = event as? TorEventStatus else { return }
                if eventStatus.action == "BOOTSTRAP" {
                    self.onBootstrapProgress(data: eventStatus.data)
                } else if eventStatus.action == "CIRCUIT_ESTABLISHED" {
                    self.onCircuitEstablished()
                }
            }
        )

        var label = String(describing: self) + ".work."
        withUnsafePointer(to: self) {
            label += "\($0)"
        }
        workQueue = DispatchQueue(label: label)
    }

    deinit {
        torThread.cancel()
    }

    // MARK: -

    public func setup(completion: @escaping BootstrapCompletionBlock,
                      progress: @escaping BootstrapProgressBlock) {
        setup(completion: completion, progress: progress, callbackQueue: nil)
    }

    public func setup(completion: @escaping BootstrapCompletionBlock,
                      progress: @escaping BootstrapProgressBlock,
                      callbackQueue: DispatchQueue?) {
        guard controlPortStatus == .closed else { return }

        controlPortStatus = .connecting
        status = .connecting

        completionBlock = completion
        progressBlock = progress
        self.callbackQueue = callbackQueue ?? DispatchQueue.main

        if configuration.torrcPath == nil || configuration.geoipPath == nil {
            let error: CPAError = .CPAErrorTorrcOrGeoipPathNotSet("Torrc or geoip path not set.")
            fail(error: error)
            return
        }

        // Only start the tor thread if it's not already executing
        if !torThread.isExecuting {
            torThread.start()
        }

        resetTimeoutTimer()

        // This is a pretty ungly hack but it will have to do for the moment.
        // Wait for a constant amount of time after starting the main Tor client before opening a socket
        // and send an authentication message.
        tryConnectingControlPort(afterDelay: CPAConnectToTorSocketDelay)
    }

    func tryConnectingControlPort(afterDelay: TimeInterval) {
        workQueue?.asyncAfter(deadline: .now() + afterDelay) { [weak self] in
            guard let self = self else { return }
            self.connectSocket()
        }
    }

    func connectSocket() {
        guard controlPortStatus == .connecting else { return }
        guard let socketManager = socketManager else { return }
        _ = socketManager.connect(host: configuration.socksHost, port: configuration.controlPort)
    }

    func resetTimeoutTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: self.CPATimeoutDelay,
                                                     repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.handleTimeout()
            }
        }
    }

    // MARK: - Utilities

    func removeTimeoutTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = nil
        }
    }

    func fail(error: Error) {
        removeTimeoutTimer()
        guard let completionBlock = completionBlock else { return }
        callbackQueue?.async { [weak self] in
            guard let self = self else { return }
            completionBlock(nil, 0, error)
            self.completionBlock = nil
            self.progressBlock = nil
        }
    }

    func handleTimeout() {
        let error = CPAError.CPAErrorTorSetupTimedOut("Tor setup did timeout.")
        fail(error: error)
    }

    // MARK: - workflow
    func onCommandSocketConnected() {
        guard let torCookieHex = configuration.torCookieDataAsHex else { return }
        let command = TorCommandAuthenticate(cookie: torCookieHex) { [weak self] (command) in
            guard let self = self else { return }
            if command.isSuccess {
                self.controlPortStatus = .authenticated
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.onAuthenticated()
                }
            } else {
               let error = CPAError.CPAErrorTorAuthenticationFailed("""
Failed to authenticate to Tor. \
The control_auth_cookie in Tor's temporary directory may contain a wrong value.
""")
                self.fail(error: error)
            }
        }
        command.send(socket: socketManager)
    }

    func onAuthenticated() {
//        let commandVersion = TorCommandGetInfo(keyword: kCPAProxyStatusVersion)
//        commandVersion.send(socket: socketManager)

        let command = TorCommandGetInfo(keyword: kCPAProxyStatusBootstrapPhase) { [weak self] (command) in
            guard let self = self else { return }
            if let commandGetInfo = command as? TorCommandGetInfo {
                let data = TorEventStatus.parseStatus(string: commandGetInfo.value)
                self.onBootstrapProgress(data: data)
            }
            self.onBootstrapPhaseReceived()
        }
        command.send(socket: socketManager)
    }

    func onBootstrapProgress(data: TorEventStatus.StatusData?) {
        guard let data = data else { return }
        let progress = UInt(data.parameters["PROGRESS"] ?? "0") ?? 0
        if bootstrapProgress != progress {
            resetTimeoutTimer()
        }
        bootstrapProgress = progress

        guard let progressBlock = self.progressBlock else { return }
        callbackQueue?.async {
            progressBlock(progress, data.parameters["SUMMARY"])
        }
    }

    func onBootstrapPhaseReceived() {
        let command = TorCommandSetEvents(events: [kCPAProxyEventStatusClient], extended: false)
        command.send(socket: socketManager)
    }

    func onCircuitEstablished() {
        status = .open
        removeTimeoutTimer()

        let socksHost = configuration.socksHost
        let socksPort = configuration.socksPort
        if completionBlock != nil {
            callbackQueue?.async { [weak self] in
                guard let self = self else { return }
                if let completionBlock = self.completionBlock {
                    completionBlock(socksHost, UInt(socksPort), nil)
                }
                self.completionBlock = nil
                self.progressBlock = nil
            }
        }
    }
}

extension TorProxyManager: TorControlConnectionDelegate {
    func torDidReceiveResponse(connection: TorControlConnection, response: String) {
    }

    public func torDidConnected(connection: TorControlConnection) {
        controlPortConnectionAttempts = 0
        if controlPortStatus == .connecting {
            onCommandSocketConnected()
        }
    }

    public func torDidDisconnected(connection: TorControlConnection, error: Error) {
        controlPortStatus = .closed
        controlPortConnectionAttempts += 1
        if controlPortConnectionAttempts < CPAMaxNumberControlConnectionAttempts {
            controlPortStatus = .connecting
            tryConnectingControlPort(afterDelay: CPAConnectToTorSocketDelay)
        } else {
            let error = CPAError.CPAErrorSocketOpenFailed("Failed to connect to control port socket")
            fail(error: error)
        }
    }
}
