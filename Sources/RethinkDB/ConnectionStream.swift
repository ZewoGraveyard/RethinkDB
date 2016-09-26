import Core
import TCP
import Venice

class ConnectionStream: Stream {
    
    let tcp: TCPConnection
    var closed: Bool {
        return self.tcp.closed
    }
    
    init(config: ReqlConfig) throws {
        let deadline = config.timeout.fromNow()
        
        self.tcp = try TCPConnection(host: config.host,
                                     port: config.port,
                                     deadline: deadline)
        
        // open
        try self.tcp.open(deadline: deadline)
        
        // create authenticator
        let authenticator = ConnectionAuthenticator(username: config.username, password: config.password)
        
        // send handshake
        try self.write(ReqlProtocol.version, deadline: deadline)
        
        // send auth challenge
        try self.write([
            "protocol_version": Int(0),
            "authentication_method": "SCRAM-SHA-256",
            "authentication": authenticator.challenge
        ].asMap(), deadline: deadline)
        try self.write([UInt8(0)])
        
        // read handshake reply
        let handshakeReplyBuffer = try self.read(nullTerminatedMaxCount: 16384, deadline: deadline)
        guard let handshakeReply = try? JSONMapParser().parse(handshakeReplyBuffer) else {
            throw Error(code: .decoding, reason: "Could not decode handshake reply.")
        }
        guard handshakeReply["success"].bool == true else {
            throw Error(code: .handshake, reason: "Server rejected handshake.")
        }
        
        // read auth challenge reply
        let authChallengeReplyBuffer = try self.read(nullTerminatedMaxCount: 16384, deadline: deadline)
        guard let authChallengeReply = try? JSONMapParser().parse(authChallengeReplyBuffer) else {
            throw Error(code: .decoding, reason: "Could not decode auth challenge reply.")
        }
        guard let authChallengeResponse = authChallengeReply["authentication"].string,
              authChallengeReply["success"].bool == true else {
            throw Error(code: .authentication, reason: "Server rejected auth challenge.")
        }
        
        // send auth proof
        try self.write([
            "authentication": authenticator.receive(challengeResponse: authChallengeResponse)
        ].asMap(), deadline: deadline)
        try self.write([UInt8(0)])
        
        // read auth challenge reply
        let authProofReplyBuffer = try self.read(nullTerminatedMaxCount: 16384, deadline: deadline)
        guard let authProofReply = try? JSONMapParser().parse(authProofReplyBuffer) else {
            throw Error(code: .decoding, reason: "Could not decode auth challenge reply.")
        }
        guard let authProofResponse = authProofReply["authentication"].string,
              authProofReply["success"].bool == true else {
            throw Error(code: .authentication, reason: "Server rejected auth challenge.")
        }
        
        // validate auth proof
        try authenticator.receive(serverProof: authProofResponse)
    }
    
    func read(into: UnsafeMutableBufferPointer<UInt8>, deadline: Double) throws -> Int {
        return try self.tcp.read(into: into, deadline: deadline)
    }
    
    func write(_ buffer: UnsafeBufferPointer<UInt8>, deadline: Double) throws {
        try self.tcp.write(buffer, deadline: deadline)
        try self.tcp.flush(deadline: deadline)
    }
    
    func close() {
        self.tcp.close()
    }
    
    func flush(deadline: Double = 1.minute.fromNow()) throws {
        try self.tcp.flush(deadline: deadline)
    }
    
}

extension ConnectionStream {
    
    func read(nullTerminatedMaxCount count: Int, deadline: Double = 1.minute.fromNow()) throws -> Buffer {
        var bytes: [UInt8] = []
        
        let byte = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let buffer = UnsafeMutableBufferPointer(start: byte, count: 1)
        while bytes.count < count {
            guard try self.read(into: buffer, deadline: deadline) == 1 else {
                throw Error(code: .connection, reason: "Unexpected end of stream.")
            }
            
            // check for null
            guard byte.pointee == 0 else {
                bytes.append(byte.pointee)
                continue
            }
            
            return Buffer(bytes)
        }
        
        throw Error(code: .connection, reason: "Buffer overflowed before finding null terminator.")
    }
    
    func read(deadline: Double = 1.minute.fromNow()) throws -> Cursor.Response {
        let token: Int64 = try self.read(deadline: deadline)
        let length: Int32 = try self.read(deadline: deadline)
        
        var buffer: Buffer = Buffer()
        while buffer.count < Int(length) {
            let chunk = try self.read(upTo: Int(length) - buffer.count, deadline: deadline)
            buffer.append(chunk)
        }
        
        let map: Map
        do {
            map = try JSONMapParser().parse(buffer)
        } catch {
            throw Error(code: .decoding, reason: "Failed to decode response.", underlyingError: error)
        }
        
        return try Cursor.Response(token: token, map: map)
    }
    
    func read(deadline: Double = 1.minute.fromNow()) throws -> Int32 {
        let size = MemoryLayout<Int32>.size
        let buffer = try self.read(upTo: size, deadline: deadline)
        return buffer.withUnsafeBytes { (ptr: UnsafePointer<Int32>) -> Int32 in
            return ptr.pointee
        }
    }
    
    func read(deadline: Double = 1.minute.fromNow()) throws -> Int64 {
        let size = MemoryLayout<Int64>.size
        let buffer = try self.read(upTo: size, deadline: deadline)
        return buffer.withUnsafeBytes { (ptr: UnsafePointer<Int64>) -> Int64 in
            return ptr.pointee
        }
    }
    
    func read(deadline: Double = 1.minute.fromNow()) throws -> Int {
        let size = MemoryLayout<Int>.size
        let buffer = try self.read(upTo: size, deadline: deadline)
        return buffer.withUnsafeBytes { (ptr: UnsafePointer<Int>) -> Int in
            return ptr.pointee
        }
    }
    
}

extension ConnectionStream {

    func write(_ from: Cursor.Query, deadline: Double = 1.minute.fromNow()) throws {
        switch from {
        case .start(let token, let buffer, let opts):
            try self.write(token, deadline: deadline)
            
            var payload = Buffer()
            payload.append(Buffer("[\(ReqlProtocol.QueryType.start.rawValue),"))
            payload.append(buffer)
            if let opts = opts {
                payload.append(Buffer(",\(try opts.rawValue.reqlJSON())]"))
            } else {
                payload.append(Buffer(",{}]"))
            }
            
            try self.write(Int32(payload.count), deadline: deadline)
            try self.write(payload, deadline: deadline)

        case .continuation(let token, let type):
            try self.write(token)
            
            let payload = Buffer("[\(type.rawValue)]")
            
            try self.write(Int32(payload.count), deadline: deadline)
            try self.write(payload, deadline: deadline)
        }
    }
    
    func write(_ from: Map, deadline: Double = 1.minute.fromNow()) throws {
        let buffer = try JSONMapSerializer().serialize(from)
        try self.write(buffer)
    }
    
    func write(_ from: Int32, deadline: Double = 1.minute.fromNow()) throws {
        let size = MemoryLayout.size(ofValue: from)
        try [from].withUnsafeBufferPointer {
            try $0.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: size) {
                try self.write(UnsafeBufferPointer(start: $0, count: size), deadline: deadline)
            }
        }
    }
    
    func write(_ from: Int64, deadline: Double = 1.minute.fromNow()) throws {
        let size = MemoryLayout.size(ofValue: from)
        try [from].withUnsafeBufferPointer {
            try $0.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: size) {
                try self.write(UnsafeBufferPointer(start: $0, count: size), deadline: deadline)
            }
        }
    }
    
    func write(_ from: Int, deadline: Double = 1.minute.fromNow()) throws {
        let size = MemoryLayout.size(ofValue: from)
        try [from].withUnsafeBufferPointer {
            try $0.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: size) {
                try self.write(UnsafeBufferPointer(start: $0, count: size), deadline: deadline)
            }
        }
    }
    
}
