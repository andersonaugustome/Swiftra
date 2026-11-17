import Foundation

/// TOTP (RFC 6238) / HOTP (RFC 4226) sem dependências externas,
/// com SHA-1 e HMAC implementados aqui para portabilidade (Linux/macOS).
public enum TOTP {
    public static let period: TimeInterval = 30
    public static let digits = 6

    /// Segredo novo em Base32 (compatível com Google/Microsoft Authenticator).
    public static func generateSecret(byteCount: Int = 20) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Base32.encode(bytes)
    }

    public static func code(secret: String, at date: Date = Date()) -> String? {
        guard let key = Base32.decode(secret) else { return nil }
        return hotp(key: key, counter: UInt64(date.timeIntervalSince1970 / period))
    }

    /// Aceita a janela atual e uma de tolerância para cada lado (relógio).
    public static func verify(_ code: String, secret: String, at date: Date = Date()) -> Bool {
        let normalized = code.filter(\.isNumber)
        guard normalized.count == digits, let key = Base32.decode(secret) else { return false }
        let counter = UInt64(date.timeIntervalSince1970 / period)
        for drift in Int64(-1)...1 {
            let candidate = counter.advanced(by: Int(drift))
            if hotp(key: key, counter: candidate) == normalized { return true }
        }
        return false
    }

    public static func provisioningURI(secret: String, account: String, issuer: String) -> String {
        let label = "\(issuer):\(account)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account
        let query = "secret=\(secret)&issuer=\(issuer)&algorithm=SHA1&digits=\(digits)&period=\(Int(period))"
        return "otpauth://totp/\(label)?\(query)"
    }

    static func hotp(key: [UInt8], counter: UInt64) -> String {
        var bigEndian = counter.bigEndian
        let counterBytes = withUnsafeBytes(of: &bigEndian) { Array($0) }
        let hash = HMAC.sha1(key: key, message: counterBytes)
        let offset = Int(hash[hash.count - 1] & 0x0F)
        let binary = (UInt32(hash[offset]) & 0x7F) << 24
            | (UInt32(hash[offset + 1]) & 0xFF) << 16
            | (UInt32(hash[offset + 2]) & 0xFF) << 8
            | (UInt32(hash[offset + 3]) & 0xFF)
        let value = binary % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", value)
    }
}

// MARK: - Base32 (RFC 4648)

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        var output = ""
        var index = 0
        while index < bytes.count {
            let chunk = Array(bytes[index..<min(index + 5, bytes.count)])
            var buffer: UInt64 = 0
            for byte in chunk { buffer = (buffer << 8) | UInt64(byte) }
            buffer <<= UInt64(8 * (5 - chunk.count))
            let chars = (chunk.count * 8 + 4) / 5
            for position in 0..<8 {
                if position < chars {
                    let shift = 35 - 5 * position
                    output.append(alphabet[Int((buffer >> UInt64(shift)) & 0x1F)])
                } else {
                    output.append("=")
                }
            }
            index += 5
        }
        return output
    }

    static func decode(_ string: String) -> [UInt8]? {
        let cleaned = string.uppercased().filter { $0 != "=" && !$0.isWhitespace }
        var bits = 0
        var bitsCount = 0
        var output: [UInt8] = []
        for character in cleaned {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            bits = (bits << 5) | value
            bitsCount += 5
            if bitsCount >= 8 {
                bitsCount -= 8
                output.append(UInt8((bits >> bitsCount) & 0xFF))
            }
        }
        return output
    }
}

// MARK: - HMAC-SHA1

enum HMAC {
    static func sha1(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var key = key
        if key.count > 64 { key = SHA1.hash(key) }
        key += Array(repeating: 0, count: 64 - key.count)
        let inner = key.map { $0 ^ 0x36 } + message
        let outer = key.map { $0 ^ 0x5C } + SHA1.hash(inner)
        return SHA1.hash(outer)
    }
}

// MARK: - SHA-1 (FIPS 180-1)

enum SHA1 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        var padded = message
        let bitLength = UInt64(message.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }
        for chunkStart in stride(from: 0, to: padded.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = UInt32(padded[offset]) << 24 | UInt32(padded[offset + 1]) << 16
                    | UInt32(padded[offset + 2]) << 8 | UInt32(padded[offset + 3])
            }
            for i in 16..<80 {
                w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotatedLeft(1)
            }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            for i in 0..<80 {
                let (f, k): (UInt32, UInt32)
                switch i {
                case 0..<20: (f, k) = ((b & c) | (~b & d), 0x5A827999)
                case 20..<40: (f, k) = (b ^ c ^ d, 0x6ED9EBA1)
                case 40..<60: (f, k) = ((b & c) | (b & d) | (c & d), 0x8F1BBCDC)
                default: (f, k) = (b ^ c ^ d, 0xCA62C1D6)
                }
                let temp = a.rotatedLeft(5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = b.rotatedLeft(30); b = a; a = temp
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e
        }
        return h.flatMap { value in
            [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
    }
}

private extension UInt32 {
    func rotatedLeft(_ amount: UInt32) -> UInt32 {
        (self << amount) | (self >> (32 - amount))
    }
}
