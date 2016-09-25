import XCTest
import TCP
@testable import RethinkDB

public class ConnectionTests : XCTestCase {
//    private var configured: Bool = false

//    override func setUp() {
//        if !self.configured {
//            r.config = ReqlConfig(connect: { _ throws -> Transport in
//                let socket = try Socket.create()
//                try socket.connect(to: "localhost", port: 28015)
//                return socket
//            })
//            self.configured = true
//        }
//        super.setUp()
//    }
    
    func testConnectionStream() {
        do {
            _ = try ConnectionStream(config: ReqlConfig())
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testQuery() {
        let cursor = try! r.db("cdhb").table("docs").limit(500).run()
        
        while let next = try! cursor.next() {
            print("result: \(next)")
        }
        
        print("Done!")
    }

    func testAuthenticatorFauxEmptyPassword() {
        let nonce = "nonce"
        let challenge = "n,,n=admin,r=nonce"
        let challengeResponse = "r=serverNonce,s=c2VydmVyU2FsdA==,i=1"
        let clientProof = "c=biws,r=serverNonce,p=CaltpKq97KjfxpRAullAl9XTbvVfXbP5x2mYT4xFnlo="

        let authenticator = ConnectionAuthenticator(username: "admin", password: "", nonce: nonce)
        
        XCTAssertEqual(challenge, authenticator.challenge)
        XCTAssertEqual(clientProof, try? authenticator.receive(challengeResponse: challengeResponse))
    }

    func testAuthenticatorFauxPassword() {
        let nonce = "rOprNGfwEbeRWgbNEkqO"
        let challenge = "n,,n=user,r=rOprNGfwEbeRWgbNEkqO"
        let challengeResponse = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
        let clientProof = "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
        let serverProof = "v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="

        let authenticator = ConnectionAuthenticator(username: "user", password: "pencil", nonce: nonce)
        
        XCTAssertEqual(challenge, authenticator.challenge)
        XCTAssertEqual(clientProof, try? authenticator.receive(challengeResponse: challengeResponse))
        XCTAssertEqual(true, try? authenticator.receive(serverProof: serverProof))
        
    }
}

extension ConnectionTests {
    public static var allTests: [(String, (ConnectionTests) -> () throws -> Void)] {
        return [
            ("testAuthenticatorFauxEmptyPassword", testAuthenticatorFauxEmptyPassword),
            ("testAuthenticatorFauxPassword", testAuthenticatorFauxPassword),
        ]
    }
}
