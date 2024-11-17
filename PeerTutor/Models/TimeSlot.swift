import Foundation

struct TimeSlot: Codable, Hashable {
    let dayOfWeek: Int // 1-7 (Sunday-Saturday)
    let startTime: Date
    let endTime: Date
    
    enum CodingKeys: String, CodingKey {
        case dayOfWeek
        case startTime
        case endTime
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dayOfWeek)
        hasher.combine(startTime)
        hasher.combine(endTime)
    }
    
    static func == (lhs: TimeSlot, rhs: TimeSlot) -> Bool {
        return lhs.dayOfWeek == rhs.dayOfWeek &&
               lhs.startTime == rhs.startTime &&
               lhs.endTime == rhs.endTime
    }
} 