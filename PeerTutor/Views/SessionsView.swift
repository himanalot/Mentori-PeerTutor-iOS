import SwiftUI
import FirebaseFirestore

enum SessionFilter: String, CaseIterable {
    case upcoming, past, all
}

class SessionViewModel: ObservableObject {
    @Published var sessions: [TutoringSession] = []
    private var tutorNames: [String: String] = [:]
    private let firebase = FirebaseManager.shared
    
    var upcomingSessions: [TutoringSession] {
        let now = Date()
        return sessions.filter { session in
            let endTime = session.dateTime.addingTimeInterval(TimeInterval(session.duration * 60))
            return endTime > now && session.status == .scheduled
        }
    }
    
    var pastSessions: [TutoringSession] {
        let now = Date()
        return sessions.filter { session in
            let endTime = session.dateTime.addingTimeInterval(TimeInterval(session.duration * 60))
            return endTime <= now || session.status == .cancelled || session.status == .completed
        }
    }
    
    init() {
        listenForSessions()
    }
    
    private func listenForSessions() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        firebase.firestore.collection("sessions")
            .whereFilter(FirebaseFirestore.Filter.orFilter([
                FirebaseFirestore.Filter.whereField("tutorId", isEqualTo: userId),
                FirebaseFirestore.Filter.whereField("studentId", isEqualTo: userId)
            ]))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.sessions = documents.compactMap { document in
                    var session = try? document.data(as: TutoringSession.self)
                    session?.documentId = document.documentID
                    return session
                }
            }
    }
    
    func getTutorName(for tutorId: String) -> String {
        if let cachedName = tutorNames[tutorId] {
            return cachedName
        }
        
        // Fetch from Firestore
        firebase.firestore.collection("users").document(tutorId).getDocument { [weak self] snapshot, _ in
            if let data = snapshot?.data(),
               let name = data["name"] as? String {
                DispatchQueue.main.async {
                    self?.tutorNames[tutorId] = name
                }
            }
        }
        
        return tutorNames[tutorId] ?? "Loading..."
    }
    
    func submitReview(for session: TutoringSession, rating: Rating) {
        guard let sessionId = session.documentId else { return }
        
        let reviewData: [String: Any] = [
            "sessionId": sessionId,
            "tutorId": session.tutorId,
            "rating": rating.rating,
            "comment": rating.comment,
            "date": Timestamp(date: Date())
        ]
        
        // Add review
        firebase.firestore.collection("reviews").addDocument(data: reviewData) { [weak self] error in
            if let error = error {
                print("Error submitting review: \(error.localizedDescription)")
                return
            }
            
            // Update session to mark as reviewed
            self?.firebase.firestore.collection("sessions").document(sessionId).updateData([
                "hasReview": true
            ])
            
            // Update tutor's average rating
            self?.updateTutorRating(tutorId: session.tutorId)
        }
    }
    
    private func updateTutorRating(tutorId: String) {
        // Fetch all reviews for this tutor
        firebase.firestore.collection("reviews")
            .whereField("tutorId", isEqualTo: tutorId)
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching reviews: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                // Calculate new average rating
                let reviews = documents.compactMap { document -> Int? in
                    return document.data()["rating"] as? Int
                }
                
                let totalRating = reviews.reduce(0, +)
                let averageRating = Double(totalRating) / Double(reviews.count)
                
                // Update tutor's document with new rating
                self?.firebase.firestore.collection("users").document(tutorId).updateData([
                    "averageRating": averageRating,
                    "totalReviews": reviews.count
                ]) { error in
                    if let error = error {
                        print("Error updating tutor rating: \(error.localizedDescription)")
                    }
                }
            }
    }
    
    func cancelSession(_ session: TutoringSession) {
        guard let sessionId = session.documentId else { return }
        
        firebase.firestore.collection("sessions").document(sessionId).updateData([
            "status": TutoringSession.SessionStatus.cancelled.rawValue
        ]) { [weak self] error in
            if let error = error {
                print("Error cancelling session: \(error.localizedDescription)")
                // Handle error if needed
            }
        }
    }
    
    func addSession(_ session: TutoringSession) {
        sessions.append(session)
        // Here you would update the backend
    }
    
    func filteredSessions(filter: SessionFilter) -> [TutoringSession] {
        let now = Date()
        switch filter {
        case .upcoming:
            return sessions.filter { $0.dateTime > now && $0.status == .scheduled }
        case .past:
            return sessions.filter { $0.dateTime <= now || $0.status == .cancelled || $0.status == .completed }
        case .all:
            return sessions
        }
    }
    
    @MainActor
    func refreshSessions() async {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let snapshot = try? await firebase.firestore.collection("sessions")
            .whereFilter(FirebaseFirestore.Filter.orFilter([
                FirebaseFirestore.Filter.whereField("tutorId", isEqualTo: userId),
                FirebaseFirestore.Filter.whereField("studentId", isEqualTo: userId)
            ]))
            .getDocuments()
        
        if let documents = snapshot?.documents {
            self.sessions = documents.compactMap { document in
                try? document.data(as: TutoringSession.self)
            }
        }
    }
}

struct SessionsView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var selectedFilter: SessionFilter = .upcoming
    @State private var selectedSession: TutoringSession?
    @State private var showingReviewSheet = false
    
    var filteredSessions: [TutoringSession] {
        switch selectedFilter {
        case .upcoming:
            return viewModel.upcomingSessions
        case .past:
            return viewModel.pastSessions
        case .all:
            return viewModel.sessions
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(SessionFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue.capitalized)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                if filteredSessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("You don't have any \(selectedFilter.rawValue) sessions")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredSessions) { session in
                                SessionRow(
                                    session: session,
                                    tutorName: viewModel.getTutorName(for: session.tutorId),
                                    onCancel: { viewModel.cancelSession(session) },
                                    onReview: {
                                        selectedSession = session
                                        showingReviewSheet = true
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Sessions")
            .sheet(isPresented: $showingReviewSheet) {
                if let session = selectedSession {
                    ReviewSessionView(
                        session: session,
                        tutorName: viewModel.getTutorName(for: session.tutorId),
                        onSubmit: { rating in
                            viewModel.submitReview(for: session, rating: rating)
                            showingReviewSheet = false
                        }
                    )
                }
            }
            .refreshable {
                await viewModel.refreshSessions()
            }
        }
    }
}

struct SessionRow: View {
    let session: TutoringSession
    let tutorName: String
    let onCancel: () -> Void
    let onReview: () -> Void
    private let firebase = FirebaseManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Subject and Status
            HStack(alignment: .center) {
                Text(session.subject)
                    .font(.headline)
                Spacer()
                StatusBadge(status: .session(session.status))
            }
            
            // Tutor/Student Info
            if let currentUserId = firebase.auth.currentUser?.uid {
                Text(session.tutorId == currentUserId ? "Student" : "Tutor")
                    .font(.subheadline)
                    .foregroundColor(.secondary) +
                Text(": \(tutorName)")
                    .font(.subheadline)
            }
            
            // Time and Duration
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text(session.dateTime.formatted(date: .numeric, time: .shortened))
                    .font(.subheadline)
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(session.duration)min")
                    .font(.subheadline)
            }
            
            // Notes if present
            if let notes = session.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Action Buttons
            if session.status == .scheduled {
                Button(action: onCancel) {
                    Label("Cancel Session", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            } else if session.status == .completed && !session.hasReview {
                Button(action: onReview) {
                    Label("Leave Review", systemImage: "star")
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct ReviewSessionView: View {
    let session: TutoringSession
    let tutorName: String
    let onSubmit: (Rating) -> Void
    
    @State private var rating = 3
    @State private var comment = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Rate Your Session with \(tutorName)")) {
                    HStack {
                        ForEach(1...5, id: \.self) { index in
                            Image(systemName: index <= rating ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.title2)
                                .onTapGesture {
                                    rating = index
                                }
                        }
                    }
                    .padding(.vertical)
                }
                
                Section(header: Text("Comments")) {
                    TextEditor(text: $comment)
                        .frame(height: 100)
                }
                
                Section {
                    Button("Submit Review") {
                        let newRating = Rating(
                            sessionId: session.id.uuidString,
                            rating: rating,
                            comment: comment,
                            date: Date()
                        )
                        onSubmit(newRating)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Review Session")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
}

struct SessionsView_Previews: PreviewProvider {
    static var previews: some View {
        SessionsView()
    }
}
