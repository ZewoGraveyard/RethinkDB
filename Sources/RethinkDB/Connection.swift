import Core
import TCP
import Venice


class Connection {
    
    private enum State {
        case handshake
        case queries
    }
    
    private let config: ReqlConfig
    private let queryChannel = Channel<Cursor.Query>()
    
    private var nextToken: Int64 = 1
    private var closed: Bool = false
    private var buffer = Buffer()
    
    private var responseChannelsByToken: [Int64: FallibleChannel<Cursor.Response>] = [:]
    
    init(config: ReqlConfig) {
        self.config = config
        self.start()
    }
    deinit {
    }
    
    func close() {
        self.closed = true
        guard self.responseChannelsByToken.isEmpty else {
            return
        }
        self.queryChannel.close()
    }
    
    func run(ast: ReqlAst, opts: ReqlGlobalOpts?) throws -> Cursor {
        // get next token
        let token = self.nextToken
        self.nextToken += 1
        
        // compile the reql and convert to buffer
        let buffer = Buffer(try ast.reqlJSON())
        
        // create the query
        let query = Cursor.Query.start(token: token, buffer: buffer, opts: opts)
        
        // create a response channel
        let responseChannel: FallibleChannel<Cursor.Response> = FallibleChannel<Cursor.Response>()
        
        // create a cursor
        let cursor = Cursor(token: token,
                            queryChannel: self.queryChannel.sendingChannel,
                            responseChannel: responseChannel.receivingChannel)
        
        // store the response channel so we can send responses to it
        self.responseChannelsByToken[token] = responseChannel
        
        // in a coroutine send the query to be accepted
        co {
            self.queryChannel.send(query)
        }
        
        // return the cursor
        return cursor
    }

    private func start() {
        co {
            while !self.closed {
                // connect stream
                let stream = self.connectStream()
                
                // query loop
                co {
                    forSelect { when, done in
                        guard !self.closed && !stream.closed else {
                            done()
                            return
                        }
                        
                        when.receive(from: self.queryChannel.receivingChannel) { query in
                            do {
                                try stream.write(query)
                            } catch {
                                self.config.failure(error)
                                for (_, channel) in self.responseChannelsByToken {
                                    channel.close()
                                }
                                stream.close()
                            }
                        }
                    }
                }
                
                // response loop
                while !self.closed && !stream.closed {
                    do {
                        let response: Cursor.Response = try stream.read(deadline: .never)
                        self.responseChannelsByToken[response.token]?.send(response)
                    } catch {
                        self.config.failure(error)
                        for (_, channel) in self.responseChannelsByToken {
                            channel.close()
                        }
                        stream.close()
                    }
                }
                
                // clear channels
                for (_, channel) in self.responseChannelsByToken {
                    channel.close()
                }
                self.responseChannelsByToken = [:]
            }
        }
    }
    
    private func connectStream() -> ConnectionStream {
        while true {
            do {
                let stream = try ConnectionStream(config: self.config)
                return stream
            } catch {
                self.config.failure(error)
                nap(for: 1.second)
            }
        }
    }
}
