//
//  TorCommand.swift
//  Pods
//
//  Created by David Chiles on 10/8/14.
//
//

import Foundation

enum ProcessingResult {
    case notProcessed
    case processed
    case finished
}

class TorCommand {
    enum Result {
        case unknown
        case positive
        case temporaryNegative
        case negative
    }

    typealias ResponseBlock = (_ command: TorCommand) -> Void

    var string: String {
        return "Unspecified command"
    }
    private var responseBlock: ResponseBlock?
    private var responseQueue: DispatchQueue
    var isSuccess: Bool {
        return (result == .positive)
    }
    var replyCode: Int = -1
    var result: Result = .unknown
    private var isMultiline = false
    private var currentLine: UInt = 0

    init(responseBlock: ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        self.responseBlock = responseBlock
        self.responseQueue = responseQueue ?? DispatchQueue.main
    }

    func send(socket: TorControlConnection?) {
        guard let socket = socket else { return }
        socket.send(command: self)
    }

    func processReply(string: String) -> ProcessingResult {
        let scanner = Scanner(string: string)
        scanner.caseSensitive = false

        var multilineFlag: String? = "+"
        if isMultiline {
            if string == "." {
                isMultiline = false
                return .processed
            }
        } else {
            scanner.scanInt(&replyCode)
            if (replyCode >= 200) && (replyCode < 300) {
                result = .positive
            } else if (replyCode >= 400) && (replyCode < 500) {
                result = .temporaryNegative
            } else if (replyCode >= 500) && (replyCode < 600) {
                result = .negative
            } else {
                return .notProcessed
            }

            scanner.charactersToBeSkipped = nil
            multilineFlag = scanner.scanCharacters(from: CharacterSet(charactersIn: " -+"))
            scanner.charactersToBeSkipped = CharacterSet(charactersIn: " \t")
            isMultiline = (multilineFlag == "+")
        }

        if multilineFlag == " " {
            guard let responseBlock = self.responseBlock else { return .finished }
            self.responseQueue.async { [self] in
                responseBlock(self)
            }
            return .finished
        }

        let tail = String(scanner.string[scanner.currentIndex...])
        parseReply(string: tail, lineNumber: currentLine)
        currentLine += 1
        return .processed
    }

    func parseReply(string: String, lineNumber: UInt) {
    }
}

class TorCommandAuthenticate: TorCommand {
    private let cookie: String

    init(cookie: String, responseBlock: ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        self.cookie = cookie
        super.init(responseBlock: responseBlock, responseQueue: responseQueue)
    }

    override var string: String {
        return "AUTHENTICATE " + cookie
    }
}

class TorCommandGetConf: TorCommand {
    private let keyword: String

    init(keyword: String, responseBlock: ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        self.keyword = keyword
        super.init(responseBlock: responseBlock, responseQueue: responseQueue)
    }

    override var string: String {
        return "GETCONF " + keyword
    }
}

class TorCommandSignal: TorCommand {
    private let keyword: String

    init(keyword: String, responseBlock: ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        self.keyword = keyword
        super.init(responseBlock: responseBlock, responseQueue: responseQueue)
    }

    override var string: String {
        return "SIGNAL " + keyword
    }
}

class TorCommandGetInfo: TorCommand {
    private let keyword: String
    private var multilineFag: String?
    var value = String()

    init(keyword: String, responseBlock: ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        self.keyword = keyword
        super.init(responseBlock: responseBlock, responseQueue: responseQueue)
    }

    override var string: String {
        return "GETINFO " + keyword
    }

    override func parseReply(string: String, lineNumber: UInt) {
        if lineNumber == 0 {
            let scanner = Scanner(string: string)
            scanner.caseSensitive = false
            _ = scanner.scanString(keyword)
            _ = scanner.scanString("=")
            value = String(scanner.string[scanner.currentIndex...])
        } else {
            if value.count > 0 {
                value += "\n"
            }
            value += string
        }
    }
}

class TorCommandSetEvents: TorCommand {
    private let events: [String]
    private let extended: Bool

    init(events: [String], extended: Bool, responseBlock: ResponseBlock? = nil, responseQueue: DispatchQueue? = nil) {
        self.events = events
        self.extended = extended
        super.init(responseBlock: responseBlock, responseQueue: responseQueue)
    }

    override var string: String {
        var command = "SETEVENTS"
        if events.count > 0 {
            if extended {
                command += " EXTENDED"
            }

            for event in events {
                command += " " + event
            }
        }
        return command
    }
}
