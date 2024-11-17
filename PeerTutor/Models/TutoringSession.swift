import Foundation

struct TutoringSession: Identifiable, Codable {
    var id: UUID
    let tutorId: String
    let studentId: String
    let subject: String
    let dateTime: Date
    let duration: Int // in minutes
    var status: SessionStatus
    var rating: Rating?
    var notes: String?
    var documentId: String?
    var hasReview: Bool = false
    
    init(id: UUID = UUID(), tutorId: String, studentId: String, subject: String, dateTime: Date, duration: Int, status: SessionStatus, rating: Rating? = nil, notes: String? = nil, documentId: String? = nil, hasReview: Bool = false) {
        self.id = id
        self.tutorId = tutorId
        self.studentId = studentId
        self.subject = subject
        self.dateTime = dateTime
        self.duration = duration
        self.status = status
        self.rating = rating
        self.notes = notes
        self.documentId = documentId
        self.hasReview = hasReview
    }
    
    enum SessionStatus: String, Codable {
        case scheduled
        case completed
        case cancelled
    }
}

struct TutoringRequest: Identifiable, Codable {
    var id: UUID
    let tutorId: String
    let studentId: String
    let subject: String
    let dateTime: Date
    let duration: Int
    let notes: String?
    var status: RequestStatus
    let isOutsideAvailability: Bool
    let isNewSubject: Bool
    let createdAt: Date
    var documentId: String?
    
    init(id: UUID = UUID(), tutorId: String, studentId: String, subject: String, dateTime: Date, duration: Int, notes: String?, status: RequestStatus, isOutsideAvailability: Bool, isNewSubject: Bool, createdAt: Date, documentId: String? = nil) {
        self.id = id
        self.tutorId = tutorId
        self.studentId = studentId
        self.subject = subject
        self.dateTime = dateTime
        self.duration = duration
        self.notes = notes
        self.status = status
        self.isOutsideAvailability = isOutsideAvailability
        self.isNewSubject = isNewSubject
        self.createdAt = createdAt
        self.documentId = documentId
    }
    
    enum RequestStatus: String, Codable {
        case pending
        case approved
        case declined
    }
}

struct Rating: Identifiable, Codable {
    var id: UUID
    let sessionId: String
    let rating: Int // 1-5
    let comment: String
    let date: Date
    
    init(id: UUID = UUID(), sessionId: String, rating: Int, comment: String, date: Date) {
        self.id = id
        self.sessionId = sessionId
        self.rating = rating
        self.comment = comment
        self.date = date
    }
} 