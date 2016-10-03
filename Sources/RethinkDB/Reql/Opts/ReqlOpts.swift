import Axis

public protocol ReqlOpts : MapFallibleRepresentable {
    var rawValue: [String: Any] { get }
    
}

extension ReqlOpts  {
    
    public func asMap() throws -> Map {
        return try rawValue.asMap()
    }
    
}
