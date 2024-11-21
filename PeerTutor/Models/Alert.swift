import Foundation
import FirebaseFirestore

struct Alert: Identifiable, Codable {
    var id: String?
    let userId: String
    let type: AlertType
    let message: String
    let relatedId: String
    let timestamp: Date
    var isRead: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, userId, type, message, relatedId, timestamp, isRead
    }
}

enum AlertType: String, Codable {
    case newRequest = "New tutoring request"
    case requestAccepted = "Request accepted"
    case requestDeclined = "Request declined"
    case sessionCancelled = "Session cancelled"
    case upcomingSession = "Upcoming session reminder"
    case newReview = "New review received"
} 