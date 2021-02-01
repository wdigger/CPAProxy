//
//  TorEvent.swift
//  TorProxy
//
//  Created by Yury Klushin on 02.02.2021.
//  Copyright © 2021 SJLabs. All rights reserved.
//

import Foundation

class TorEvent {
    typealias ResponseBlock = (_ event: TorEvent, _ string: String) -> Void

    private var filterString: String
    private var responseBlock: ResponseBlock?
    private var responseQueue: DispatchQueue

    init(filterString: String, responseBlock: ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        self.filterString = filterString
        self.responseBlock = responseBlock
        self.responseQueue = responseQueue ?? DispatchQueue.main
    }

    func processReply(string: String) -> ProcessingResult {
        if string.contains(filterString) {
            guard let responseBlock = self.responseBlock else { return .finished }
            self.responseQueue.async { [self] in
                parseReply(string: string)
                responseBlock(self, string)
            }
            return .processed
        }
        return .notProcessed
    }

    func parseReply(string: String) {
    }
}

class TorEventStatus: TorEvent {
    enum `Type` {
        case unknown
        case general // GENERAL
        case client  // CLIENT
        case server  // SERVER
    }

    enum Severity {
        case unknown
        case notice   // NOTICE
        case warning  // WARN
        case error    // ERR
    }

    struct StatusData {
        var severity: Severity = .unknown
        var action: String?
        var parameters: [String: String] = [:]
    }

    var data: StatusData?
    var type: Type = .unknown
    var severity: Severity {
        guard let data = data else { return .unknown }
        return data.severity
    }
    var action: String? {
        guard let data = data else { return nil }
        return data.action
    }
    var parameters: [String: String] {
        guard let data = data else { return [:] }
        return data.parameters
    }

    init(responseBlock: TorEvent.ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        super.init(filterString: "650 STATUS_", responseBlock: responseBlock, responseQueue: responseQueue)
    }

    override func parseReply(string: String) {
        let scanner = Scanner(string: string)
        scanner.caseSensitive = false
        _ = scanner.scanString("650 STATUS_")

        if scanner.scanString("GENERAL") != nil {
            type = .general
        } else if scanner.scanString("CLIENT") != nil {
            type = .client
        } else if scanner.scanString("SERVER") != nil {
            type = .server
        }

        data = TorEventStatus.parseStatus(string: String(scanner.string[scanner.currentIndex...]))
    }

    static func parseStatus(string: String) -> StatusData? {
        var data = StatusData()

        let scanner = Scanner(string: string)
        scanner.caseSensitive = false

        if scanner.scanString("NOTICE") != nil {
            data.severity = .notice
        } else if scanner.scanString("WARN") != nil {
            data.severity = .warning
        } else if scanner.scanString("ERR") != nil {
            data.severity = .error
        } else {
            return nil
        }

        data.action = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: " "))

        while !scanner.isAtEnd {
            guard let keyword = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "=")) else { return nil }
            _ = scanner.scanCharacter()
            var stopChar = " "
            if string[scanner.currentIndex] == "\"" {
                _ = scanner.scanCharacter()
                stopChar = "\""
            }
            guard let value = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: stopChar)) else { return nil }
            if string[scanner.currentIndex] == "\"" {
                _ = scanner.scanCharacter()
            }
            data.parameters[keyword] = value
        }

        return data
    }
}
