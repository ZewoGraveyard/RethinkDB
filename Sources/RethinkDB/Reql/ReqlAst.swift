import Foundation
import Core

public class ReqlAst {
    fileprivate let term: ReqlTerm
    fileprivate let args: [Any]
    fileprivate let opts: [String: Any]

    fileprivate let sourceLocation: (file: String, line: Int)
    fileprivate var cachedReqlJSON: String? = nil

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
    public func reqlJSON() throws -> String {
        guard self.cachedReqlJSON == nil else {
            return self.cachedReqlJSON!
        }

        var cachedReqlJSON: String = ""
        do {
            cachedReqlJSON += "["
            cachedReqlJSON += try self.term.rawValue.reqlJSON()
            cachedReqlJSON += ",["

            for (idx, arg) in self.args.enumerated() {
                if let arg = arg as? ReqlArg {
                    cachedReqlJSON += try arg.reqlJSON()
                } else if let arg = ReqlFunction(arg) {
                    cachedReqlJSON += try arg.reqlJSON()
                } else {
                    throw Error(code: .reql(backtrace: nil), reason: "Invalid argument type. Got '\(arg.self)'.")
                }

                if idx + 1 < self.args.count {
                    cachedReqlJSON += ","
                }
            }
            
            cachedReqlJSON += "]"

            if self.opts.count > 0 {
                cachedReqlJSON += ","
                cachedReqlJSON += try opts.reqlJSON()
            }

            cachedReqlJSON += "]"
        } catch let error as Error {
            guard case .reql(let backtrace) = error.code else {
                throw error
            }

            var parts: [String?] = [backtrace]
            parts.insert("\(self.sourceLocation.file)#\(self.sourceLocation.line)", at: 0)
            parts = parts.filter { $0 != nil}

            throw Error(code: .reql(backtrace: parts.map { $0! } .joined(separator: "\n")), reason: "Could not compile reql.")
        }

        self.cachedReqlJSON = cachedReqlJSON
        return cachedReqlJSON
    }
}
