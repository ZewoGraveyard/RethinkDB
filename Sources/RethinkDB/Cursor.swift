import Foundation
import Venice


public class Cursor {
    
    internal struct Query {
        let type: ReqlProtocol.QueryType
        let data: Data?
    }
    
    internal struct Response {
        let type: ReqlProtocol.ResponseType
        let map: Map
        
        var results: [Map]? {
            switch self.type {
            case .successAtom, .successPartial, .successSequence:
                return self.map["r"].array
            default:
                return nil
            }
        }
        
        var error: Error? {
            switch self.type {
            case .clientError:
                let backtrace = self.map["b"].string ?? "No Backtrace"
                let reason = self.map["r"].array?.first?.string ?? "No Reason"
                return Error(code: .query(type: "Client", backtrace: backtrace), reason: reason)
            case .compileError:
                let backtrace = self.map["b"].string ?? "No Backtrace"
                let reason = self.map["r"].array?.first?.string ?? "No Reason"
                return Error(code: .query(type: "Compile", backtrace: backtrace), reason: reason)
            case .runtimeError:
                let backtrace = self.map["b"].string ?? "No Backtrace"
                let reason = self.map["r"].array?.first?.string ?? "No Reason"
                return Error(code: .query(type: "Runtime", backtrace: backtrace), reason: reason)
            default:
                return nil
            }
        }
        
        var final: Bool {
            return self.type.final
        }
    }
    
    private let sender: FallibleSendingChannel<Query>
    private let receiver: FallibleReceivingChannel<Response>
    
    private var finished: Bool = false
    private var remainingResults: [Map] = []
    
    internal init(sender: FallibleSendingChannel<Query>, receiver: FallibleReceivingChannel<Response>) {
        self.sender = sender
        self.receiver = receiver
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
        guard !self.sender.closed else {
            throw Error(code: .connection, reason: "Unexpected end of query.")
        }
        self.sender.send(Query(type: .`continue`, data: nil))
        
        // receive a new response from server
        guard let response = try self.receiver.receive() else {
            throw Error(code: .connection, reason: "Unexpected end of query.")
        }
        
        // check for error
        let error = response.error
        guard error == nil else {
            self.finished = true
            throw error!
        }
        
        // check for results
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
        self.receiver.close()
    }
    
}
