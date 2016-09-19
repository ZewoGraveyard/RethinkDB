import Core
import Venice


public class Cursor {
    
    enum State {
        case started
        case finishedPartial
        case finished
        case failed(Error)
        case closed
    }
    
    private let token: Int64
    
    internal init(token: Int64) {
        self.token = token
    }
    
    public func next(deadline: Double = .never) throws -> Map? {
        fatalError()
    }
    
    public func all(deadline: Double = .never) throws -> [Map] {
        fatalError()
    }
    
    public func close() {
        fatalError()
    }
    
}
