import Foundation
import Venice


public class Cursor {
    
    internal struct Query {
        let token: Int64
        let type: ReqlProtocol.QueryType
        let buffer: Buffer?
    }
    
    internal enum Response {
        
        case success(token: Int64, results: [Map], done: Bool)
        case failure(token: Int64, error: Error)
        
        var token: Int64 {
            switch self {
            case .success(let token, _, _):
                return token
            case .failure(let token, _):
                return token
            }
        }
        
        var results: [Map]? {
            switch self {
            case .success(_, let results, _):
                return results
            case .failure:
                return nil
            }
        }
        
        var error: Error? {
            switch self {
            case .success:
                return nil
            case .failure(_, let error):
                return error
            }
        }
        
        var final: Bool {
            switch self {
            case .success(_, _, let done):
                return done
            case .failure:
                return true
            }
        }
        
        init(token: Int64, map: Map) throws {
            guard let type = ReqlProtocol.ResponseType(rawValue: map["t"].int ?? -1) else {
                throw Error(code: .decoding, reason: "Could not decode response.")
            }
            
            let results = map["r"].array
            
            switch type {
            case .successAtom, .successPartial, .successSequence, .waitComplete, .serverInfo:
                guard results != nil  else {
                    throw Error(code: .decoding, reason: "Could not decode response.")
                }
                self = .success(token: token, results: results!, done: type.final)
            case .clientError:
                let backtrace = map["b"].string ?? "No Backtrace"
                let reason = results?.first?.string ?? "No Reason"
                let error = Error(code: .query(type: "Client Error", backtrace: backtrace), reason: reason)
                self = .failure(token: token, error: error)
            case .compileError:
                let backtrace = map["b"].string ?? "No Backtrace"
                let reason = results?.first?.string ?? "No Reason"
                let error = Error(code: .query(type: "Client Error", backtrace: backtrace), reason: reason)
                self = .failure(token: token, error: error)
            case .runtimeError:
                let backtrace = map["b"].string ?? "No Backtrace"
                let reason = results?.first?.string ?? "No Reason"
                let error = Error(code: .query(type: "Client Error", backtrace: backtrace), reason: reason)
                self = .failure(token: token, error: error)
            }
        }
    }
    
    internal let token: Int64
    
    private let queryChannel: SendingChannel<Query>
    private let responseChannel: FallibleReceivingChannel<Response>
    
    private var needsContinue: Bool = false
    private var finished: Bool = false
    private var remainingResults: [Map] = []
    
    internal init(token: Int64,
                  queryChannel: SendingChannel<Query>,
                  responseChannel: FallibleReceivingChannel<Response>) {
        self.token = token
        self.queryChannel = queryChannel
        self.responseChannel = responseChannel
    }
    deinit {
        self.close()
    }
    
    public func next() throws -> Map? {
        // if we have any remaining results return them first
        guard self.remainingResults.count == 0 else {
            return self.remainingResults.remove(at: 0)
        }
        
        // if we're finished just return nil we have nothing else
        guard !self.finished else {
            return nil
        }
        
        // send a new request to the server
        if self.needsContinue {
            guard !self.queryChannel.closed else {
                throw Error(code: .connection, reason: "Unexpected end of query.")
            }
            self.queryChannel.send(Query(token: self.token, type: .`continue`, buffer: nil))
        }
        
        // receive a new response from server
        guard let response = try self.responseChannel.receive() else {
            throw Error(code: .connection, reason: "Unexpected end of query.")
        }
        
        // check for error
        let error = response.error
        guard error == nil else {
            self.finished = true
            throw error!
        }
        
        // check for results
        self.needsContinue = !response.final
        self.finished = response.final
        self.remainingResults += (response.results ?? [])
        
        // enter next loop again
        return try self.next()
    }
    
    public func all() throws -> [Map] {
        var all: [Map] = []
        while let n = try self.next() {
            all.append(n)
        }
        return all
    }
    
    public func close() {
        self.finished = true
        self.responseChannel.close()
    }
    
}
