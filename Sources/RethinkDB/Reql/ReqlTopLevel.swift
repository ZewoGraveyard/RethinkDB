import Foundation

public class ReqlTopLevel : ReqlAst {
    
    public static func expr(_ value: Any) -> ReqlExpr {
        return ReqlExpr(term: .datum, args: [value], parent: nil)
    }
    
    public static func configure(handler: (inout ReqlConfig) -> Void) {
        var config = self.config
        handler(&config)
        self.config = config
    }
    
    internal static var config: ReqlConfig = ReqlConfig() {
        didSet {
            self.connection = Connection(config: self.config)
        }
    }
    
    internal static var connection: Connection {
        get {
            let connection: Connection
            if let existing = self.connectionStorage {
                connection = existing
            } else {
                connection = Connection(config: self.config)
                connectionStorage = connection
            }
            return connection
        }
        set {
            connectionStorage?.close()
            connectionStorage = newValue
        }
    }
    
    private static var connectionStorage: Connection? = nil
    
}

public typealias r = ReqlTopLevel

extension ReqlAst {
    
    public func run(_ opts: ReqlGlobalOpts? = nil) throws -> Cursor {
        return try r.connection.run(ast: self, opts: opts)
    }
    
}
