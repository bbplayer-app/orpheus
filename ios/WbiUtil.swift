import Foundation
import CommonCrypto

class WbiUtil {
    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
        33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
        61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
        36, 20, 34, 44, 52
    ]

    static func getMixinKey(orig: String) -> String {
        var result = ""
        let origChars = Array(orig)
        for i in 0..<32 {
            if i < mixinKeyEncTab.count {
                let index = mixinKeyEncTab[i]
                if index < origChars.count {
                    result.append(origChars[index])
                }
            }
        }
        return result
    }

    static func encodeURIComponent(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~") // RFC 3986 unreserved characters
        
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        // Kotlin implementation specifically replaces:
        // .replace("+", "%20") -> handled by addingPercentEncoding usually (space becomes %20)
        // .replace("*", "%2A") -> standard doesn't encode *, kotlin manual replace does
        // .replace("%7E", "~") -> standard might encode ~, kotlin decodes it back
        
        // Let's mimic the Kotlin behavior on top of standard URL encoding if needed,
        // but standard `.alphanumerics` + `-_.~` usually produces compatible output for B-site.
        // Bilibili specifically wants: !'()~ to be unencoded? No, JS encodeURIComponent encodes !'()*.
        // Kotlin: URLEncoder.encode uses application/x-www-form-urlencoded (space -> +), so it manually fixes + -> %20.
        // Swift `addingPercentEncoding` uses percent encoding (space -> %20).
        // So we mainly need to ensure * is encoded to %2A if it's not in allowed set.
        // Actually, just sticking to standard RFC 3986 is usually fine for WBI, but let's be precise.
        
        return encoded
    }
    
    static func md5(_ string: String) -> String {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: length)
        if let data = string.data(using: .utf8) {
            _ = data.withUnsafeBytes { body -> String in
                CC_MD5(body.baseAddress, CC_LONG(data.count), &digest)
                return ""
            }
        }
        return (0..<length).reduce("") {
            $0 + String(format: "%02x", digest[$1])
        }
    }

    static func sign(params: [String: Any], imgKey: String, subKey: String) -> [String: String] {
        let mixinKey = getMixinKey(orig: imgKey + subKey)
        let currTime = Int(Date().timeIntervalSince1970)
        
        var sortedParams = params
        sortedParams["wts"] = currTime
        
        // Sort keys
        let keys = sortedParams.keys.sorted()
        
        var queryParts: [String] = []
        for key in keys {
            if let value = sortedParams[key] {
                let strValue = "\(value)"
                // Filter characters per some implementations? Kotlin just encodeURIComponent.
                // Note: Kotlin implementation filters characters?
                // "val queryStr = sortedParams.entries.joinToString("&") { (k, v) -> "${k.encodeURIComponent()}=${v.encodeURIComponent()}" }"
                // No character filtering in the provided Kotlin snippet.
                
                queryParts.append("\(encodeURIComponent(key))=\(encodeURIComponent(strValue))")
            }
        }
        
        let queryStr = queryParts.joined(separator: "&")
        let w_rid = md5(queryStr + mixinKey)
        
        var finalMap: [String: String] = [:]
        for (k, v) in sortedParams {
            finalMap[k] = "\(v)"
        }
        finalMap["w_rid"] = w_rid
        
        return finalMap
    }
    
    static func extractKey(url: String) -> String {
        // url.substringAfterLast("/").substringBeforeLast(".")
        guard let lastComponent = url.split(separator: "/").last else { return "" }
        let filename = String(lastComponent)
        if let dotIndex = filename.lastIndex(of: ".") {
            return String(filename[..<dotIndex])
        }
        return filename
    }
}
