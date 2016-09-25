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
    
    fileprivate static var config: ReqlConfig = ReqlConfig() {
        didSet {
            self.connection = Connection(config: self.config)
        }
    }
    
    fileprivate static var connection = Connection(config: ReqlConfig()) {
        didSet {
            oldValue.close()
        }
    }
    
}

public typealias r = ReqlTopLevel

extension ReqlAst {
    
    public func run() throws -> Cursor {
        return try r.connection.run(self)
    }
    
}
