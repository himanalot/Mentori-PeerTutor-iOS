import Foundation

struct TutoringSession: Identifiable, Codable, Hashable {
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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TutoringSession, rhs: TutoringSession) -> Bool {
        lhs.id == rhs.id
    }
}

public struct TutoringRequest: Identifiable, Codable, Hashable {
    public var id: UUID
    public let tutorId: String
    public let studentId: String
    public let subject: String
    public let dateTime: Date
    public let duration: Int
    public let notes: String?
    public var status: RequestStatus
    public let isOutsideAvailability: Bool
    public let isNewSubject: Bool
    public let createdAt: Date
    public var documentId: String?
    
    public enum RequestStatus: String, Codable {
        case pending
        case approved
        case declined
    }
    
    public init(id: UUID = UUID(), tutorId: String, studentId: String, subject: String, dateTime: Date, duration: Int, notes: String?, status: RequestStatus, isOutsideAvailability: Bool, isNewSubject: Bool, createdAt: Date, documentId: String? = nil) {
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
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: TutoringRequest, rhs: TutoringRequest) -> Bool {
        lhs.id == rhs.id
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
