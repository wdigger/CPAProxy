//  TorSocketManager.swift
//
//  Copyright (c) 2013 Claudiu-Vlad Ursache.
//  See LICENCE for licensing information
//

import Foundation

/**
 The CPASocketManagerDelegate defines methods used to respond to events related to the manager's socket.
 */
protocol TorControlConnectionDelegate: class {
    func torDidConnected(connection: TorControlConnection)
    func torDidDisconnected(connection: TorControlConnection, error: Error)
    func torDidReceiveResponse(connection: TorControlConnection, response: String)
}

public class TorControlConnection {
    enum ResponseType {
        case unknown
        case success
        case temporaryNegative
        case permanentNegative
        case asynchronous
    }

    weak var delegate: TorControlConnectionDelegate?

    var connection: TextLineConnection?
    var delegateQueue: DispatchQueue

    var commandQueue: [TorCommand] = []
    var sentCommand: TorCommand?
    var events: [TorEvent] = []

    init(delegate: TorControlConnectionDelegate, delegateQueue: DispatchQueue? = nil) {
        self.delegateQueue = delegateQueue ?? DispatchQueue.main
        self.delegate = delegate
        self.connection = TextLineConnection(delegate: self)
    }

    // MARK: - Public Methods

    public func connect(host: String, port: UInt16) -> Bool {
        guard let socket = self.connection else { return false }
        do {
            try socket.connect(to: host, port: port)
            return true
        } catch {
            return false
        }
    }

    func send(command: TorCommand) {
        commandQueue.append(command)
        sendNextCommand()
    }

    private func write(string: String) {
        self.connection?.write(string: string)
    }

    private func sendNextCommand() {
        guard sentCommand == nil else { return }
        guard !commandQueue.isEmpty else { return }
        sentCommand = commandQueue.first
        commandQueue.remove(at: 0)
        if let sentCommand = sentCommand {
            write(string: sentCommand.string)
        }
    }

    // MARK: - events
    func registerEvent(_ event: TorEvent) {
        events.append(event)
    }

    // MARK: - handle socket

    private func handleSocketConnected() {
        self.delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.torDidConnected(connection: self)
        }
    }

    private func handleSocketDisconnected(error: Error) {
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.torDidDisconnected(connection: self, error: error)
        }
    }

    private func handleResponse(_ response: String) {
        if let sentCommand = sentCommand {
            switch sentCommand.processReply(string: response) {
            case .finished:
                self.sentCommand = nil
                sendNextCommand()
                return
            case .processed:
                return
            case .notProcessed:
                break
            }
        }
        if responseType(response: response) == .asynchronous {
            let events = self.events
            for event in events {
                switch event.processReply(string: response) {
                case .notProcessed:
                    continue
                case .processed:
                    return
                case .finished:
                    self.events.removeAll {$0 === event}
                    return
                }
            }
        }
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.torDidReceiveResponse(connection: self, response: response)
        }
    }

    func handleSocketDataAsString(string: String) {
        handleResponse(string)
    }

    func responseType(response: String) -> ResponseType {
        let scanner = Scanner(string: response)
        guard let code = scanner.scanInt() else { return .unknown }
        if (code >= 200) && (code < 300) {
            return .success
        } else if (code >= 400) && (code < 500) {
            return .temporaryNegative
        } else if (code >= 500) && (code < 600) {
            return .permanentNegative
        } else if (code >= 600) && (code < 700) {
            return .asynchronous
        }
        return .unknown
    }
}

extension TorControlConnection: TextLineConnectionDelegate {
    func connection(_ connection: TextLineConnection, didConnectTo host: String, port: UInt16) {
        handleSocketConnected()
    }

    func connection(_ connection: TextLineConnection, didDisconnectWithError: Error) {
        handleSocketDisconnected(error: didDisconnectWithError)
    }

    func connection(_ connection: TextLineConnection, didRead string: String) {
        handleSocketDataAsString(string: string)
    }
}
