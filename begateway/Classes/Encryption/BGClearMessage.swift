import UIKit
import Foundation

class BGClearMessage: BGMessage {
    
    /// Data of the message
    let data: Data
    
    /// Creates a clear message with data.
    ///
    /// - Parameter data: Data of the clear message
    required init(data: Data) {
        self.data = data
    }
    
    /// Creates a clear message from a string, with the specified encoding.
    ///
    /// - Parameters:
    ///   - string: String value of the clear message
    ///   - encoding: Encoding to use to generate the clear data
    /// - Throws: SwiftyRSAError
    convenience init(string: String, using encoding: String.Encoding) throws {
        guard let data = string.data(using: encoding) else {
            throw BGRSAError.stringToDataConversionFailed
        }
        self.init(data: data)
    }
    
    /// Returns the string representation of the clear message using the specified
    /// string encoding.
    ///
    /// - Parameter encoding: Encoding to use during the string conversion
    /// - Returns: String representation of the clear message
    /// - Throws: SwiftyRSAError
    func string(encoding: String.Encoding) throws -> String {
        guard let str = String(data: data, encoding: encoding) else {
            throw BGRSAError.dataToStringConversionFailed
        }
        return str
    }
    
    /// Encrypts a clear message with a public key and returns an encrypted message.
    ///
    /// - Parameters:
    ///   - key: Public key to encrypt the clear message with
    ///   - padding: Padding to use during the encryption
    /// - Returns: Encrypted message
    /// - Throws: SwiftyRSAError
    func encrypted(with key: BGPublicKey, padding: BGPadding) throws -> BGEncryptedMessage {
        
        let blockSize = SecKeyGetBlockSize(key.reference)
        
        var maxChunkSize: Int
        switch padding {
        case []:
            maxChunkSize = blockSize
        case .OAEP:
            maxChunkSize = blockSize - 42
        default:
            maxChunkSize = blockSize - 11
        }
        
        var decryptedDataAsArray = [UInt8](repeating: 0, count: data.count)
        (data as NSData).getBytes(&decryptedDataAsArray, length: data.count)
        
        var encryptedDataBytes = [UInt8](repeating: 0, count: 0)
        var idx = 0
        while idx < decryptedDataAsArray.count {
            
            let idxEnd = min(idx + maxChunkSize, decryptedDataAsArray.count)
            let chunkData = [UInt8](decryptedDataAsArray[idx..<idxEnd])
            
            var encryptedDataBuffer = [UInt8](repeating: 0, count: blockSize)
            var encryptedDataLength = blockSize
            
            let status = SecKeyEncrypt(key.reference, padding, chunkData, chunkData.count, &encryptedDataBuffer, &encryptedDataLength)
            
            guard status == noErr else {
                throw BGRSAError.chunkEncryptFailed(index: idx)
            }
            
            encryptedDataBytes += encryptedDataBuffer
            
            idx += maxChunkSize
        }
        
        let encryptedData = Data(bytes: UnsafePointer<UInt8>(encryptedDataBytes), count: encryptedDataBytes.count)
        return BGEncryptedMessage(data: encryptedData)
    }
    
    /// Signs a clear message using a private key.
    /// The clear message will first be hashed using the specified digest type, then signed
    /// using the provided private key.
    ///
    /// - Parameters:
    ///   - key: Private key to sign the clear message with
    ///   - digestType: Digest
    /// - Returns: Signature of the clear message after signing it with the specified digest type.
    /// - Throws: SwiftyRSAError
    func signed(with key: BGPrivateKey, digestType: BGSignature.DigestType) throws -> BGSignature {
        
        let digest = self.digest(digestType: digestType)
        let blockSize = SecKeyGetBlockSize(key.reference)
        let maxChunkSize = blockSize - 11
        
        guard digest.count <= maxChunkSize else {
            throw BGRSAError.invalidDigestSize(digestSize: digest.count, maxChunkSize: maxChunkSize)
        }
        
        var digestBytes = [UInt8](repeating: 0, count: digest.count)
        (digest as NSData).getBytes(&digestBytes, length: digest.count)
        
        var signatureBytes = [UInt8](repeating: 0, count: blockSize)
        var signatureDataLength = blockSize
        
        let status = SecKeyRawSign(key.reference, digestType.padding, digestBytes, digestBytes.count, &signatureBytes, &signatureDataLength)
        
        guard status == noErr else {
            throw BGRSAError.signatureCreateFailed(status: status)
        }
        
        let signatureData = Data(bytes: UnsafePointer<UInt8>(signatureBytes), count: signatureBytes.count)
        return BGSignature(data: signatureData)
    }
    
    /// Verifies the signature of a clear message.
    ///
    /// - Parameters:
    ///   - key: Public key to verify the signature with
    ///   - signature: Signature to verify
    ///   - digestType: Digest type used for the signature
    /// - Returns: Result of the verification
    /// - Throws: SwiftyRSAError
    func verify(with key: BGPublicKey, signature: BGSignature, digestType: BGSignature.DigestType) throws -> Bool {
        
        let digest = self.digest(digestType: digestType)
        var digestBytes = [UInt8](repeating: 0, count: digest.count)
        (digest as NSData).getBytes(&digestBytes, length: digest.count)
        
        var signatureBytes = [UInt8](repeating: 0, count: signature.data.count)
        (signature.data as NSData).getBytes(&signatureBytes, length: signature.data.count)
        
        let status = SecKeyRawVerify(key.reference, digestType.padding, digestBytes, digestBytes.count, signatureBytes, signatureBytes.count)
        
        if status == errSecSuccess {
            return true
        } else if status == -9809 {
            return false
        } else {
            throw BGRSAError.signatureVerifyFailed(status: status)
        }
    }
    
    func digest(digestType: BGSignature.DigestType) -> Data {
        
        let digest: Data
        
        switch digestType {
        case .sha1:
            digest = (data as NSData).swiftyRSASHA1()
        case .sha224:
            digest = (data as NSData).swiftyRSASHA224()
        case .sha256:
            digest = (data as NSData).swiftyRSASHA256()
        case .sha384:
            digest = (data as NSData).swiftyRSASHA384()
        case .sha512:
            digest = (data as NSData).swiftyRSASHA512()
        }
        
        return digest
    }
}
