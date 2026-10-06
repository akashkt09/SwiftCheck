import Foundation

struct UserProfileLoader {
    // Bug: force unwrap on optional data — crashes if "name" is missing or not a String.
    static func displayName(from json: [String: Any]) -> String {
        json["name"] as! String
    }
}
