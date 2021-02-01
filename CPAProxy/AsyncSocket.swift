//
//  AsyncSocket.swift
//  TorProxy
//
//  Created by Chris Ballinger on 10/20/19.
//

import Foundation
import Network

protocol AsyncSocketDelegate: class {
    func socket(_ socket: AsyncSocket, didConnectTo host: String, port: UInt16)
    func socket(_ socket: AsyncSocket, didDisconnectWithError: Error)
    func socket(_ socket: AsyncSocket, didRead data: Data)
}

extension AsyncSocketDelegate {
    func socket(_ socket: AsyncSocket, didConnectTo host: String, port: UInt16) {}
    func socket(_ socket: AsyncSocket, didDisconnectWithError: Error) {}
    func socket(_ socket: AsyncSocket, didRead data: Data) {}
}

enum AsyncSocketError: Int, Error {
    case badConfig
}

class AsyncSocket {
    private weak var delegate: AsyncSocketDelegate?
    private var delegateQueue: DispatchQueue

    private let socketQueue = DispatchQueue(label: "TorSocket")
    private var connection: NWConnection?

    public init(delegate: AsyncSocketDelegate? = nil,
                delegateQueue: DispatchQueue = .main) {
        self.delegate = delegate
        self.delegateQueue = delegateQueue
    }

    func connect(to host: String, port: UInt16) throws {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw AsyncSocketError.badConfig
        }

        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            switch newState {
            case .ready:
                print("\(String(describing: self.connection)) established")

                self.read()

                // Notify your delegate that the connection is ready.
                if let delegate = self.delegate {
                    delegate.socket(self, didConnectTo: host, port: port.rawValue)
                }
            case .failed(let error):
                print("\(String(describing: self.connection)) failed with \(error)")

                // Cancel the connection upon a failure.
                self.connection?.cancel()

                // Notify your delegate that the connection failed.
                if let delegate = self.delegate {
                    delegate.socket(self, didDisconnectWithError: error)
                }
            default:
                break
            }
        }
        connection?.start(queue: socketQueue)
    }

    func write(_ data: Data, completion: ((Bool) -> Void)?) {
        connection?.send(content: data, completion: .contentProcessed({ (_) in
            guard let completion = completion else { return }
            completion(true)
        }))
    }

    private func read() {
        connection?.receive(minimumIncompleteLength: 1,
                            maximumLength: Int.max, completion: { [weak self] (data, _, _, _) in
            guard let self = self else { return }
            guard let data = data else { return }
            guard !data.isEmpty else { return }
            guard let delegate = self.delegate else { return }
            self.delegateQueue.async {
                delegate.socket(self, didRead: data)
            }
            self.read()
        })
    }
}
