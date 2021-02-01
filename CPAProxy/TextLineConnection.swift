//
//  TextLineConnection.swift
//  TorProxy
//
//  Created by Yury Klushin on 02.02.2021.
//  Copyright © 2021 SJLabs. All rights reserved.
//

import Foundation

protocol TextLineConnectionDelegate: class {
    func connection(_ connection: TextLineConnection, didConnectTo host: String, port: UInt16)
    func connection(_ connection: TextLineConnection, didDisconnectWithError: Error)
    func connection(_ connection: TextLineConnection, didRead string: String)
}

class TextLineConnection {
    private var socket: AsyncSocket?
    private weak var delegate: TextLineConnectionDelegate?
    private var delegateQueue: DispatchQueue?
    private var buffer = Data()

    public init(delegate: TextLineConnectionDelegate? = nil,
                delegateQueue: DispatchQueue = .main) {
        self.delegate = delegate
        self.delegateQueue = delegateQueue
        socket = AsyncSocket(delegate: self, delegateQueue: delegateQueue)
    }

    func connect(to host: String, port: UInt16) throws {
        try socket?.connect(to: host, port: port)
    }

    func write(string: String, completion: ((Bool) -> Void)? = nil) {
        print("Tor <- \(string)")
        let toSend = string + kCPAProxyCRLF
        guard let data = toSend.data(using: .utf8) else {
            guard let completion = completion else { return }
            completion(false)
            return
        }
        socket?.write(data, completion: completion)
    }

    private func onReaded(_ data: Data) {
        buffer.append(data)
        while buffer.count > 0 {
            guard let lines = String(data: buffer, encoding: String.Encoding.utf8) else { return }
            guard let range = lines.range(of: kCPAProxyCRLF) else { return }
            let line = lines[..<range.lowerBound]
            print("Tor -> [\(line)]")
            guard let portion = line.data(using: String.Encoding.utf8) else { return }
            buffer = buffer.suffix(buffer.count - portion.count - 2)
            reportLine(String(line))
        }
    }

    private func reportLine(_ string: String) {
        guard let delegate = delegate else { return }
        delegateQueue?.async { [weak self] in
            guard let self = self else { return }
            delegate.connection(self, didRead: string)
        }
    }
}

extension TextLineConnection: AsyncSocketDelegate {
    func socket(_ socket: AsyncSocket, didConnectTo host: String, port: UInt16) {
        guard let delegate = delegate else { return }
        delegateQueue?.async { [weak self] in
            guard let self = self else { return }
            delegate.connection(self, didConnectTo: host, port: port)
        }
    }

    func socket(_ socket: AsyncSocket, didDisconnectWithError: Error) {
        guard let delegate = delegate else { return }
        delegateQueue?.async { [weak self] in
            guard let self = self else { return }
            delegate.connection(self, didDisconnectWithError: didDisconnectWithError)
        }
    }

    func socket(_ socket: AsyncSocket, didRead data: Data) {
        onReaded(data)
    }
}
