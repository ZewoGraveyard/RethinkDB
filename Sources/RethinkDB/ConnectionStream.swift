import Core
import TCP
import Venice

class ConnectionStream : Stream {
    
    let tcp: TCPStream
    let bufferCapacity = 2*1024
    let buffer = UnsafeMutableBufferPointer<Byte>(capacity: 2*1024)
    
    var closed: Bool {
        return tcp.closed
    }
    
    init(config: ReqlConfig) throws {
        let deadline = config.timeout.fromNow()
        
        self.tcp = try TCPStream(host: config.host,
                                 port: config.port,
                                 deadline: deadline)
        
        // open
        try tcp.open(deadline: deadline)
        
        // create authenticator
        let authenticator = ConnectionAuthenticator(username: config.username, password: config.password)
        
        // send handshake
        try write(ReqlProtocol.version, deadline: deadline)
        
        // send auth challenge
        try write([
            "protocol_version": 0,
            "authentication_method": "SCRAM-SHA-256",
            "authentication": authenticator.challenge
        ].asMap(), deadline: deadline)
        try write([0], deadline: deadline)
        
        // read handshake reply
        let handshakeReply: Map = try read(deadline: deadline)
        guard handshakeReply["success"].bool == true else {
            throw Error(code: .handshake, reason: "Server rejected handshake.")
        }
        
        // read auth challenge reply
        let authChallengeReply: Map = try read(deadline: deadline)
        guard let authChallengeResponse = authChallengeReply["authentication"].string,
              authChallengeReply["success"].bool == true else {
            throw Error(code: .authentication, reason: "Server rejected auth challenge.")
        }
        
        // send auth proof
        try write([
            "authentication": authenticator.receive(challengeResponse: authChallengeResponse)
        ].asMap(), deadline: deadline)
        try write([0], deadline: deadline)
        
        // read auth challenge reply
        let authProofReply: Map = try read(deadline: deadline)
        guard let authProofResponse = authProofReply["authentication"].string,
              authProofReply["success"].bool == true else {
            throw Error(code: .authentication, reason: "Server rejected auth challenge.")
        }
        
        // validate auth proof
        try authenticator.receive(serverProof: authProofResponse)
    }
    
    deinit {
        buffer.deallocate(capacity: bufferCapacity)
    }
    
    func read(into: UnsafeMutableBufferPointer<Byte>, deadline: Double) throws -> UnsafeBufferPointer<Byte> {
        return try tcp.read(into: into, deadline: .never)
    }
    
    func write(_ buffer: UnsafeBufferPointer<Byte>, deadline: Double) throws {
        try tcp.write(buffer, deadline: deadline)
        try flush(deadline: deadline)
    }
    
    func flush(deadline: Double) throws {
        try tcp.flush(deadline: deadline)
    }
    
    func open(deadline: Double) throws {
        // no-op
    }
    
    func close() {
        tcp.close()
    }
    
    
    
    
}

extension ConnectionStream {
    
    func write(_ message: Map, deadline: Double = 1.minute.fromNow()) throws {
        try write(JSONMapSerializer.serialize(message), deadline: deadline)
    }
    
    func read(upTo count: Int = 16384, deadline: Double = 1.minute.fromNow()) throws -> Map {
        var bytes: [Byte] = []
        
        let byteBuffer = UnsafeMutableBufferPointer<Byte>(capacity: 1)
        let byte = byteBuffer.baseAddress!
        defer {
            byteBuffer.deallocate(capacity: 1)
        }
        while bytes.count < count {
            guard try read(into: byteBuffer, deadline: deadline).count == 1 else {
                throw Error(code: .connection, reason: "Unexpected end of stream.")
            }
            
            // check for null
            guard byte.pointee == 0 else {
                bytes.append(byte.pointee)
                continue
            }
            
            do {
                return try JSONMapParser.parse(bytes)
            } catch {
                throw Error(code: .decoding, reason: "Could not decode json.", underlyingError: error)
            }
        }
        
        throw Error(code: .connection, reason: "Buffer overflowed before finding null terminator.")
    }
    
    func write(_ query: Cursor.Query, deadline: Double = 1.minute.fromNow()) throws {
        switch query {
        case .start(let token, let args, let opts):
            try write(token, deadline: deadline)
            
            var argsAndOpts: [Map] = []
            argsAndOpts.append(.int(ReqlProtocol.QueryType.start.rawValue))
            argsAndOpts.append(args)
            if let opts = opts {
                argsAndOpts.append(opts)
            }
            
            let payload: Buffer
            do {
                payload = try JSONMapSerializer.serialize(.array(argsAndOpts))
            } catch {
                throw Error(code: .encoding, reason: "Could not encode json.", underlyingError: error)
            }
            
            try write(Int32(payload.count), deadline: deadline)
            try write(payload, deadline: deadline)
            
        case .continuation(let token, let type):
            try write(token)
            
            let payload = Buffer("[\(type.rawValue.description)]")
            
            try write(Int32(payload.count), deadline: deadline)
            try write(payload, deadline: deadline)
        }
    }
    
    func read(deadline: Double = 1.minute.fromNow()) throws -> Cursor.Response {
        let token: Int64 = try read(deadline: deadline)
        let length: Int32 = try read(deadline: deadline)
        let parser = JSONMapParser()
        
        do {
            var remaining = Int(length)
            while remaining > 0 {
                let chunkCapacity = min(remaining, bufferCapacity)
                let chunk = try read(into: UnsafeMutableBufferPointer(start: buffer.baseAddress!, count: chunkCapacity), deadline: deadline)
                remaining -= chunk.count
                try parser.parse(chunk)
            }
            return try Cursor.Response(token: token, map: parser.finish())
        } catch let error as JSONMapParserError {
            throw Error(code: .decoding, reason: "Failed to decode response.", underlyingError: error)
        } catch {
            throw Error(code: .decoding, reason: "Failed to read response.", underlyingError: error)
        }
        
    }
    
    func read(deadline: Double = 1.minute.fromNow()) throws -> Int32 {
        let size = MemoryLayout<Int32>.size
        let buffer: Buffer = try read(upTo: size, deadline: deadline)
        return buffer.withUnsafeBytes { (ptr: UnsafePointer<Int32>) -> Int32 in
            return ptr.pointee
        }
    }
    
    
    func read(deadline: Double = 1.minute.fromNow()) throws -> Int64 {
        let size = MemoryLayout<Int64>.size
        let buffer: Buffer = try read(upTo: size, deadline: deadline)
        return buffer.withUnsafeBytes { (ptr: UnsafePointer<Int64>) -> Int64 in
            return ptr.pointee
        }
    }
    
    func write(_ value: Int32, deadline: Double = 1.minute.fromNow()) throws {
        let size = MemoryLayout.size(ofValue: value)
        try [value].withUnsafeBufferPointer {
            try $0.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: size) {
                try self.write(UnsafeBufferPointer(start: $0, count: size), deadline: deadline)
            }
        }
    }
    
    func write(_ value: Int64, deadline: Double = 1.minute.fromNow()) throws {
        let size = MemoryLayout.size(ofValue: value)
        try [value].withUnsafeBufferPointer {
            try $0.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: size) {
                try self.write(UnsafeBufferPointer(start: $0, count: size), deadline: deadline)
            }
        }
    }
    
}
