import Foundation

struct Subject: Codable, Hashable {
    let name: String
    let level: String // e.g., "AP", "IB", "Regular"
    
    enum CodingKeys: String, CodingKey {
        case name
        case level
    }
} 