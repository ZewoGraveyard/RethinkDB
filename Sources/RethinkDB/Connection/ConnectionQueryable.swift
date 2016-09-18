import Foundation
import JSON


protocol ConnectionQueryable {
    
    func run(ast: ReqlAst) throws -> JSON
    
}
