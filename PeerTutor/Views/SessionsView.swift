import SwiftUI
import FirebaseFirestore
import EventKit
import FirebaseFirestoreSwift

enum SessionFilter: String, CaseIterable {
    case upcoming, past, requests, all
}

class SessionViewModel: ObservableObject {
    @Published var sessions: [TutoringSession] = []
    @Published var incomingRequests: [TutoringRequest] = []
    @Published var outgoingRequests: [TutoringRequest] = []
    private var tutorNames: [String: String] = [:]
    private let firebase = FirebaseManager.shared
    
    var upcomingSessions: [TutoringSession] {
        let now = Date()
        return sessions.filter { session in
            session.status == .scheduled && session.dateTime > now
        }
    }
    
    var pastSessions: [TutoringSession] {
        let now = Date()
        return sessions.filter { session in
            session.status == .completed ||
            (session.status == .scheduled && session.dateTime <= now)
        }.sorted { $0.dateTime > $1.dateTime }
    }
    
    init() {
        listenForSessions()
        listenForRequests()
    }
    
    private func listenForSessions() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        firebase.firestore.collection("sessions")
            .whereFilter(FirebaseFirestore.Filter.orFilter([
                FirebaseFirestore.Filter.whereField("tutorId", isEqualTo: userId),
                FirebaseFirestore.Filter.whereField("studentId", isEqualTo: userId)
            ]))
            .order(by: "dateTime", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                let now = Date()
                self?.sessions = documents.compactMap { document in
                    var session = try? document.data(as: TutoringSession.self)
                    session?.documentId = document.documentID
                    
                    if session?.status == .scheduled && session?.dateTime ?? now <= now {
                        self?.firebase.firestore.collection("sessions")
                            .document(document.documentID)
                            .updateData([
                                "status": TutoringSession.SessionStatus.completed.rawValue,
                                "timestamp": FieldValue.serverTimestamp()
                            ])
                        
                        session?.status = .completed
                    }
                    
                    return session
                }
            }
    }
    
    private func listenForRequests() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        let now = Timestamp(date: Date())
        
        // Listen for incoming requests (as tutor)
        firebase.firestore.collection("requests")
            .whereField("tutorId", isEqualTo: userId)
            .whereField("status", isEqualTo: TutoringRequest.RequestStatus.pending.rawValue)
            .whereField("dateTime", isGreaterThan: now)
            .order(by: "dateTime", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                self?.incomingRequests = documents.compactMap { document in
                    var request = try? document.data(as: TutoringRequest.self)
                    request?.documentId = document.documentID
                    return request
                }
            }
        
        // Listen for outgoing requests (as student)
        firebase.firestore.collection("requests")
            .whereField("studentId", isEqualTo: userId)
            .whereField("status", isEqualTo: TutoringRequest.RequestStatus.pending.rawValue)
            .whereField("dateTime", isGreaterThan: now)
            .order(by: "dateTime", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                self?.outgoingRequests = documents.compactMap { document in
                    var request = try? document.data(as: TutoringRequest.self)
                    request?.documentId = document.documentID
                    return request
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
    
    func getOtherPartyName(for session: TutoringSession) -> String {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return "Loading..." }
        let idToFetch = session.tutorId == currentUserId ? session.studentId : session.tutorId
        return getTutorName(for: idToFetch)
    }
    
    func submitReview(for session: TutoringSession, rating: Rating) {
        guard let sessionId = session.documentId else {
            print("Error: Session document ID is missing for session: \(session.id)")
            return
        }
        
        let reviewData: [String: Any] = [
            "sessionId": sessionId,
            "tutorId": session.tutorId,
            "studentId": session.studentId,
            "rating": rating.rating,
            "comment": rating.comment,
            "date": Timestamp(date: Date())
        ]
        
        // Add review with auto-generated document ID
        firebase.firestore.collection("reviews")
            .addDocument(data: reviewData) { [weak self] error in
                if let error = error {
                    print("Error submitting review: \(error.localizedDescription)")
                    return
                }
                
                // Update session to mark as reviewed
                self?.firebase.firestore.collection("sessions")
                    .document(sessionId)
                    .updateData([
                        "hasReview": true
                    ]) { error in
                        if let error = error {
                            print("Error updating session review status: \(error.localizedDescription)")
                            return
                        }
                        
                        // Update tutor's average rating
                        self?.updateTutorRating(tutorId: session.tutorId)
                    }
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
        
        firebase.firestore.collection("sessions")
            .document(sessionId)
            .updateData([
                "status": TutoringSession.SessionStatus.cancelled.rawValue
            ]) { [weak self] error in
                if let error = error {
                    print("Error cancelling session: \(error.localizedDescription)")
                    return
                }
                
                // Update the local session status
                DispatchQueue.main.async {
                    if let index = self?.sessions.firstIndex(where: { $0.documentId == sessionId }) {
                        self?.sessions[index].status = .cancelled
                    }
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
            return sessions
                .filter { $0.dateTime > now && $0.status == .scheduled }
                .sorted { $0.dateTime < $1.dateTime }
        case .past:
            return sessions
                .filter { $0.status == .completed || ($0.status == .scheduled && $0.dateTime <= now) }
                .sorted { $0.dateTime > $1.dateTime }
        case .requests:
            return []
        case .all:
            let upcoming = sessions
                .filter { $0.dateTime > now && $0.status == .scheduled }
                .sorted { $0.dateTime < $1.dateTime }
            let past = sessions
                .filter { $0.status == .completed || ($0.status == .scheduled && $0.dateTime <= now) }
                .sorted { $0.dateTime > $1.dateTime }
            return upcoming + past
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
                var session = try? document.data(as: TutoringSession.self)
                session?.documentId = document.documentID
                return session
            }
        }
    }
    
    @MainActor
    func refreshRequests() async {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        let now = Timestamp(date: Date())
        
        // Refresh incoming requests
        let snapshot = try? await firebase.firestore.collection("requests")
            .whereField("tutorId", isEqualTo: userId)
            .whereField("status", isEqualTo: TutoringRequest.RequestStatus.pending.rawValue)
            .whereField("dateTime", isGreaterThan: now)
            .order(by: "dateTime", descending: false)
            .getDocuments()
        
        if let documents = snapshot?.documents {
            self.incomingRequests = documents.compactMap { document in
                var request = try? document.data(as: TutoringRequest.self)
                request?.documentId = document.documentID
                return request
            }
        }
        
        // Refresh outgoing requests
        let snapshotOutgoing = try? await firebase.firestore.collection("requests")
            .whereField("studentId", isEqualTo: userId)
            .whereField("status", isEqualTo: TutoringRequest.RequestStatus.pending.rawValue)
            .whereField("dateTime", isGreaterThan: now)
            .order(by: "dateTime", descending: false)
            .getDocuments()
        
        if let documents = snapshotOutgoing?.documents {
            self.outgoingRequests = documents.compactMap { document in
                var request = try? document.data(as: TutoringRequest.self)
                request?.documentId = document.documentID
                return request
            }
        }
    }
    
    func handleRequest(_ request: TutoringRequest, approved: Bool) {
        guard let requestId = request.documentId else {
            print("Error: Request document ID is missing for request: \(request.id)")
            return
        }
        
        if approved {
            // Create new session
            let session = TutoringSession(
                tutorId: request.tutorId,
                studentId: request.studentId,
                subject: request.subject,
                dateTime: request.dateTime,
                duration: request.duration,
                status: .scheduled,
                notes: request.notes,
                hasReview: false
            )
            
            do {
                // First create the session
                try firebase.firestore.collection("sessions")
                    .addDocument(from: session) { [weak self] error in
                        if let error = error {
                            print("Error creating session: \(error.localizedDescription)")
                            return
                        }
                        
                        // Then update request status
                        self?.firebase.firestore.collection("requests")
                            .document(requestId)
                            .updateData([
                                "status": TutoringRequest.RequestStatus.approved.rawValue
                            ]) { error in
                                if let error = error {
                                    print("Error updating request status: \(error.localizedDescription)")
                                } else {
                                    // Only remove from local state if update was successful
                                    DispatchQueue.main.async {
                                        self?.incomingRequests.removeAll { $0.id == request.id }
                                    }
                                }
                            }
                    }
            } catch {
                print("Error encoding session: \(error.localizedDescription)")
            }
        } else {
            // For declined requests, update status and remove from local state
            firebase.firestore.collection("requests")
                .document(requestId)
                .updateData([
                    "status": TutoringRequest.RequestStatus.declined.rawValue
                ]) { [weak self] error in
                    if let error = error {
                        print("Error updating request status: \(error.localizedDescription)")
                    } else {
                        // Only remove from local state if update was successful
                        DispatchQueue.main.async {
                            self?.incomingRequests.removeAll { $0.id == request.id }
                        }
                    }
                }
        }
    }
}

struct SessionsView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var selectedFilter: SessionFilter = .upcoming
    @State private var selectedSession: TutoringSession?
    @State private var showingReviewSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(SessionFilter.allCases, id: \.self) { filter in
                            FilterButton(title: filter.rawValue.capitalized,
                                       isSelected: selectedFilter == filter) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding()
                }
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        switch selectedFilter {
                        case .upcoming:
                            if viewModel.upcomingSessions.isEmpty {
                                ContentUnavailableView(
                                    "No Upcoming Sessions",
                                    systemImage: "calendar",
                                    description: Text("You don't have any upcoming sessions scheduled")
                                )
                            } else {
                                ForEach(viewModel.upcomingSessions) { session in
                                    SessionRow(
                                        session: session,
                                        tutorName: viewModel.getOtherPartyName(for: session),
                                        onCancel: { viewModel.cancelSession(session) },
                                        onReview: { selectedSession = session }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            
                        case .past:
                            if viewModel.pastSessions.isEmpty {
                                ContentUnavailableView(
                                    "No Past Sessions",
                                    systemImage: "clock.arrow.circlepath",
                                    description: Text("You haven't completed any sessions yet")
                                )
                            } else {
                                ForEach(viewModel.pastSessions) { session in
                                    SessionRow(
                                        session: session,
                                        tutorName: viewModel.getOtherPartyName(for: session),
                                        onCancel: nil,
                                        onReview: { selectedSession = session }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            
                        case .requests:
                            if viewModel.incomingRequests.isEmpty && viewModel.outgoingRequests.isEmpty {
                                ContentUnavailableView(
                                    "No Requests",
                                    systemImage: "tray",
                                    description: Text("You don't have any pending requests")
                                )
                            } else {
                                if !viewModel.incomingRequests.isEmpty {
                                    Section(header:
                                        Text("Incoming Requests")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal)
                                    ) {
                                        ForEach(viewModel.incomingRequests) { request in
                                            TutoringRequestRow(
                                                request: request,
                                                type: .incoming,
                                                onResponse: { approved in
                                                    viewModel.handleRequest(request, approved: approved)
                                                }
                                            )
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                                
                                if !viewModel.outgoingRequests.isEmpty {
                                    Section(header:
                                        Text("Outgoing Requests")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal)
                                            .padding(.top, 20)
                                    ) {
                                        ForEach(viewModel.outgoingRequests) { request in
                                            TutoringRequestRow(
                                                request: request,
                                                type: .outgoing,
                                                onResponse: { _ in }
                                            )
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                            }
                            
                        case .all:
                            if viewModel.sessions.isEmpty {
                                ContentUnavailableView(
                                    "No Sessions",
                                    systemImage: "calendar.badge.exclamationmark",
                                    description: Text("You don't have any sessions")
                                )
                            } else {
                                ForEach(viewModel.sessions) { session in
                                    SessionRow(
                                        session: session,
                                        tutorName: viewModel.getOtherPartyName(for: session),
                                        onCancel: { viewModel.cancelSession(session) },
                                        onReview: { selectedSession = session }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Sessions")
            .sheet(item: $selectedSession) { session in
                ReviewSheet(session: session) { rating in
                    viewModel.submitReview(for: session, rating: rating)
                }
            }
        }
        .refreshable {
            await viewModel.refreshSessions()
            await viewModel.refreshRequests()
        }
    }
}

struct SessionRow: View {
    let session: TutoringSession
    let tutorName: String
    let onCancel: (() -> Void)?
    let onReview: () -> Void
    private let firebase = FirebaseManager.shared
    @State private var showingCalendarAlert = false
    
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
                VStack(spacing: 8) {
                    // Add Calendar Button
                    Button(action: addToCalendar) {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Existing Cancel Button
                    Button(action: {
                        withAnimation {
                            onCancel?()
                        }
                    }) {
                        Label("Cancel Session", systemImage: "xmark.circle")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            } else if session.status == .completed {
                if session.hasReview {
                    // Show that review has been submitted
                    Label("Review Submitted", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    // Show review button only if no review has been submitted
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
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .alert("Added to Calendar", isPresented: $showingCalendarAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func addToCalendar() {
        Task {
            let eventStore = EKEventStore()
            
            // Use the new iOS 17+ API if available, fallback to older version
            if #available(iOS 17.0, *) {
                do {
                    let granted = try await eventStore.requestFullAccessToEvents()
                    if granted {
                        await createCalendarEvent(store: eventStore)
                    }
                } catch {
                    print("Error requesting calendar access: \(error.localizedDescription)")
                }
            } else {
                // Fallback for older iOS versions
                do {
                    let granted = try await eventStore.requestAccess(to: .event)
                    if granted {
                        await createCalendarEvent(store: eventStore)
                    }
                } catch {
                    print("Error requesting calendar access: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    private func createCalendarEvent(store: EKEventStore) {
        let event = EKEvent(eventStore: store)
        event.title = "Tutoring Session: \(session.subject)"
        event.startDate = session.dateTime
        event.endDate = session.dateTime.addingTimeInterval(TimeInterval(session.duration * 60))
        event.notes = session.notes
        event.calendar = store.defaultCalendarForNewEvents
        
        do {
            try store.save(event, span: .thisEvent)
            showingCalendarAlert = true
        } catch {
            print("Error saving event: \(error.localizedDescription)")
        }
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

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                .foregroundColor(isSelected ? .white : .blue)
                .cornerRadius(20)
        }
    }
}

struct ReviewSheet: View {
    let session: TutoringSession
    let onSubmit: (Rating) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 5
    @State private var comment = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Rating", selection: $rating) {
                        ForEach(1...5, id: \.self) { rating in
                            HStack {
                                Text("\(rating)")
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                            .tag(rating)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                
                Section {
                    TextEditor(text: $comment)
                        .frame(height: 100)
                }
                
                Section {
                    Button("Submit Review") {
                        let newRating = Rating(
                            sessionId: session.documentId ?? "",
                            rating: rating,
                            comment: comment,
                            date: Date()
                        )
                        onSubmit(newRating)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
                    .disabled(session.documentId == nil)
                }
            }
            .navigationTitle("Review Session")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
}
