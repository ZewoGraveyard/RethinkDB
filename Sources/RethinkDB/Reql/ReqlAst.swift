import Foundation
import Core

public class ReqlAst {
    fileprivate let term: ReqlTerm
    fileprivate let args: [Any]
    fileprivate let opts: [String: Any]

    fileprivate let sourceLocation: (file: String, line: Int)
    fileprivate var cachedMap: Map? = nil

    internal init(term: ReqlTerm, args: [Any], parent: ReqlAst?, file: String = #file, line: Int = #line) {
        // get args only
        var mutableArgs = args.filter { !($0 is ReqlOpts) }

        // extract reql opts
        var mutableOpts: [String: Any] = [:]
        for arg in args {
            guard let opts = arg as? ReqlOpts else {
                continue
            }
            for (k, v) in opts.rawValue {
                mutableOpts[k] = v
            }
        }

        // funcall has a special case where function needs to be encoded first
        if term == .funcall {
            if let last = mutableArgs.popLast() {
                mutableArgs.insert(last, at: 0)
            }
        }

        // insert parents
        if let parent = parent {
            mutableArgs.insert(parent, at: 0)
        }

        self.args = mutableArgs
        self.opts = mutableOpts
        self.term = term
        self.sourceLocation = (file: file, line: line)
    }
}

extension ReqlAst : ReqlArg {
    
    public func asMap() throws -> Map {
        guard cachedMap == nil else {
            return cachedMap!
        }
        
        var map: [Map] = []
        do {
            try map.append(term.rawValue.asMap())
            
            var argsMap: [Map] = []
            for arg in args {
                if let arg = arg as? MapFallibleRepresentable {
                    try argsMap.append(arg.asMap())
                } else if let arg = ReqlFunction(arg) {
                    try argsMap.append(arg.asMap())
                } else {
                    throw Error(code: .reql(backtrace: nil), reason: "Invalid argument type. Got '\(arg.self)'.")
                }
            }
            
            map.append(.array(argsMap))
            
            if !opts.isEmpty {
                try map.append(opts.asMap())
            }
        } catch let error as Error {
            guard case .reql(let backtrace) = error.code else {
                throw error
            }
            
            var parts: [String?] = [backtrace]
            parts.insert("\(sourceLocation.file)#\(sourceLocation.line)", at: 0)
            parts = parts.filter { $0 != nil}
            
            throw Error(code: .reql(backtrace: parts.map { $0! } .joined(separator: "\n")), reason: "Could not compile reql.")
        }
        
        cachedMap = .array(map)
        
        return cachedMap!
    }
}
