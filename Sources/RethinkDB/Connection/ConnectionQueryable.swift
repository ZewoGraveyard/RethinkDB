import Foundation
import Core

protocol ConnectionQueryable {
    func run(ast: ReqlAst) throws -> Map
}
