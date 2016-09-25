import Foundation
import Core
import OpenSSL


class ConnectionAuthenticator {
    
    let username: String
    let password: String
    let challenge: String
    
    private let nonce: String
    private var clientProof: String = ""
    private var serverProof: String = ""
    
    
    init(username: String, password: String, nonce: String? = nil) {
        self.username = username
        self.password = password
        self.nonce = nonce ?? Data([UInt8](UUID().uuidString.utf8)).base64EncodedString()
        self.challenge = "n,,n=\(self.username),r=\(self.nonce)"
    }
    
    func receive(challengeResponse response: String) throws -> String {
        let pairs = self.parsePairs(from: response)
        guard let combinedNonce = pairs["r"],
              let salt = pairs["s"],
              let iterations = Int(pairs["i"] ?? ""),
              let saltData = Data(base64Encoded: salt) else {
            throw Error(code: .authentication, reason: "Could not parse authentication challenge.")
        }

        let passwordBuffer = Buffer(self.password)
        let saltBuffer = saltData.withUnsafeBytes { Buffer(bytes: UnsafeBufferPointer<UInt8>(start: $0, count: saltData.count)) }

        let passwordKeyBuffer: Buffer
        if iterations > 1 || !passwordBuffer.isEmpty {
            passwordKeyBuffer = try Hash.pbkdf2(.sha256, password: passwordBuffer, salt: saltBuffer, iterations: iterations)
        } else {
            var message = saltBuffer
            message.append(Buffer([UInt8(0x00), UInt8(0x00), UInt8(0x00), UInt8(0x01)]))
            passwordKeyBuffer = Hash.hmac(.sha256, key: passwordBuffer, message: message)
        }
        
        let clientKeyBuffer = Hash.hmac(.sha256, key: passwordKeyBuffer, message: "Client Key")
        let serverKeyBuffer = Hash.hmac(.sha256, key: passwordKeyBuffer, message: "Server Key")
        let storedKeyBuffer = Hash.hash(.sha256, message: clientKeyBuffer)
        
        let authBuffer = Buffer("n=\(self.username),r=\(self.nonce),\(response),c=biws,r=\(combinedNonce)")
        let clientSignatureBuffer = Hash.hmac(.sha256, key: storedKeyBuffer, message: authBuffer)
        let serverProofBuffer = Hash.hmac(.sha256, key: serverKeyBuffer, message: authBuffer)
        let clientProofBuffer = xor(key: clientSignatureBuffer, message: clientKeyBuffer)
        
        self.clientProof = clientProofBuffer.withUnsafeBytes {
            return Data(bytes: $0, count: clientProofBuffer.count).base64EncodedString()
        } ?? ""
        self.serverProof = serverProofBuffer.withUnsafeBytes {
            return Data(bytes: $0, count: serverProofBuffer.count).base64EncodedString()
        } ?? ""
        
        return "c=biws,r=\(combinedNonce),p=\(self.clientProof)"
    }
    
    @discardableResult
    func receive(serverProof: String) throws -> Bool {
        guard "v=\(self.serverProof)" == serverProof else {
            throw Error(code: .authentication, reason: "Could not verify server proof.")
        }
        return true
    }
    
    private func xor(key: Buffer, message: Buffer) -> Buffer {
        guard !message.isEmpty else {
            return Buffer()
        }
        
        return Buffer(count: message.count, fill: { (ptr) in
            message.copyBytes(to: ptr.baseAddress!, count: ptr.count)
            var y = 0
            for x in 0..<ptr.count {
                ptr[x] = ptr[x] ^ key[y]
                y += 1
                if y == key.count {
                    y = 0
                }
            }
        })
    }
    
    private func parsePairs(from response: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for part in response.characters.split(separator: ",") where String(part).characters.count >= 3 {
            let part = String(part)
            if let first = part.characters.first {
                let data = part[part.index(part.startIndex, offsetBy: 2)..<part.endIndex]
                pairs[String(first)] = data
            }
        }
        return pairs
    }
    
    
}
