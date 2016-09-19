import Foundation

public class ReqlTopLevel : ReqlAst {
    
    public static func expr(_ value: Any) -> ReqlExpr {
        return ReqlExpr(term: .datum, args: [value], parent: nil)
    }
    
}

public typealias r = ReqlTopLevel
