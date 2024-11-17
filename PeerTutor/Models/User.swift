import Foundation
import FirebaseFirestoreSwift

struct User: Identifiable, Codable {
    @DocumentID var id: String?
    var email: String
    var name: String
    var profileImageUrl: String?
    var subjects: [Subject]
    var availability: [TimeSlot]
    var bio: String
    var averageRating: Double?
    var totalReviews: Int?
    
    var displayRating: Double {
        return averageRating ?? 5.0
    }
    
    var displayReviews: Int {
        return totalReviews ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case profileImageUrl
        case subjects
        case availability
        case bio
        case averageRating
        case totalReviews
    }
} 