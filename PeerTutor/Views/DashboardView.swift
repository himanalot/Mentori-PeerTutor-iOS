import SwiftUI
import FirebaseFirestore

class DashboardViewModel: ObservableObject {
    @Published var pendingRequests: [TutoringRequest] = []
    @Published var upcomingSessions: [TutoringSession] = []
    @Published var totalTutoringHours: Int = 0
    @Published var averageRating: Double = 5.0
    @Published var totalStudentsHelped: Int = 0
    private let firebase = FirebaseManager.shared
    private var tutorNames: [String: String] = [:]
    
    init() {
        listenForRequests()
        listenForSessions()
        calculateStats()
    }
    
    private func listenForRequests() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        firebase.firestore.collection("requests")
            .whereField("tutorId", isEqualTo: userId)
            .whereField("status", isEqualTo: TutoringRequest.RequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.pendingRequests = documents.compactMap { document in
                    try? document.data(as: TutoringRequest.self)
                }
            }
    }
    
    private func listenForSessions() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let now = Date()
        firebase.firestore.collection("sessions")
            .whereFilter(FirebaseFirestore.Filter.orFilter([
                FirebaseFirestore.Filter.whereField("tutorId", isEqualTo: userId),
                FirebaseFirestore.Filter.whereField("studentId", isEqualTo: userId)
            ]))
            .whereField("dateTime", isGreaterThan: now)
            .whereField("status", isEqualTo: TutoringSession.SessionStatus.scheduled.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.upcomingSessions = documents.compactMap { document in
                    try? document.data(as: TutoringSession.self)
                }
            }
    }
    
    private func calculateStats() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        // Calculate total tutoring hours from completed sessions
        firebase.firestore.collection("sessions")
            .whereField("tutorId", isEqualTo: userId)
            .whereField("status", isEqualTo: TutoringSession.SessionStatus.completed.rawValue)
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                let completedSessions = documents.compactMap { try? $0.data(as: TutoringSession.self) }
                let totalHours = completedSessions.reduce(0) { $0 + ($1.duration / 60) }
                let uniqueStudents = Set(completedSessions.map { $0.studentId }).count
                
                DispatchQueue.main.async {
                    self?.totalTutoringHours = totalHours
                    self?.totalStudentsHelped = uniqueStudents
                }
            }
        
        // Get tutor's rating
        firebase.firestore.collection("users")
            .document(userId)
            .getDocument { [weak self] snapshot, error in
                if let user = try? snapshot?.data(as: User.self) {
                    DispatchQueue.main.async {
                        self?.averageRating = user.averageRating ?? 5.0
                    }
                }
            }
    }
    
    func handleRequest(_ request: TutoringRequest, approved: Bool) {
        guard let requestId = request.documentId else { return }
        
        if approved {
            // Create new session
            let session = TutoringSession(
                tutorId: request.tutorId,
                studentId: request.studentId,
                subject: request.subject,
                dateTime: request.dateTime,
                duration: request.duration,
                status: .scheduled,
                notes: request.notes
            )
            
            do {
                // Add session
                try firebase.firestore.collection("sessions").addDocument(from: session)
                
                // Update request status
                firebase.firestore.collection("requests").document(requestId)
                    .updateData(["status": TutoringRequest.RequestStatus.approved.rawValue])
            } catch {
                print("Error creating session: \(error.localizedDescription)")
            }
        } else {
            // Update request status to declined
            firebase.firestore.collection("requests").document(requestId)
                .updateData(["status": TutoringRequest.RequestStatus.declined.rawValue])
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
    
    func cancelSession(_ session: TutoringSession) {
        guard let sessionId = session.documentId else { return }
        
        firebase.firestore.collection("sessions").document(sessionId).updateData([
            "status": TutoringSession.SessionStatus.cancelled.rawValue
        ]) { error in
            if let error = error {
                print("Error cancelling session: \(error.localizedDescription)")
            }
        }
    }
    
    var pastSessions: [TutoringSession] {
        let now = Date()
        return upcomingSessions.filter { session in
            let sessionEndTime = session.dateTime.addingTimeInterval(TimeInterval(session.duration * 60))
            return sessionEndTime < now || session.status == .completed || session.status == .cancelled
        }
    }
    
    @MainActor
    func refreshData() async {
        calculateStats()
    }
    
    @MainActor
    func refreshRequests() async {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let snapshot = try? await firebase.firestore.collection("requests")
            .whereField("tutorId", isEqualTo: userId)
            .whereField("status", isEqualTo: TutoringRequest.RequestStatus.pending.rawValue)
            .getDocuments()
        
        if let documents = snapshot?.documents {
            self.pendingRequests = documents.compactMap { document in
                try? document.data(as: TutoringRequest.self)
            }
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
            self.upcomingSessions = documents.compactMap { document in
                var session = try? document.data(as: TutoringSession.self)
                session?.documentId = document.documentID
                return session
            }
        }
    }
    
    func submitReview(for session: TutoringSession, rating: Rating) {
        guard let sessionId = session.documentId,
              let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        // Create review document
        let reviewData: [String: Any] = [
            "sessionId": sessionId,
            "tutorId": session.tutorId,
            "studentId": currentUserId,
            "rating": rating.rating,
            "comment": rating.comment,
            "date": Timestamp(date: Date())
        ]
        
        // Add review to Firestore
        firebase.firestore.collection("reviews").addDocument(data: reviewData) { [weak self] error in
            if let error = error {
                print("Error submitting review: \(error.localizedDescription)")
                return
            }
            
            // Update session to mark as reviewed
            self?.firebase.firestore.collection("sessions").document(sessionId)
                .updateData(["hasReview": true])
            
            // Update tutor's average rating
            self?.updateTutorRating(tutorId: session.tutorId)
        }
    }
    
    private func updateTutorRating(tutorId: String) {
        // Get all reviews for this tutor
        firebase.firestore.collection("reviews")
            .whereField("tutorId", isEqualTo: tutorId)
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents,
                      !documents.isEmpty else { return }
                
                // Calculate average rating
                let totalRating = documents.compactMap { $0.data()["rating"] as? Int }.reduce(0, +)
                let averageRating = Double(totalRating) / Double(documents.count)
                
                // Update tutor's profile
                self?.firebase.firestore.collection("users").document(tutorId)
                    .updateData([
                        "averageRating": averageRating,
                        "totalReviews": documents.count
                    ])
            }
    }
}

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Activity Graph Card
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Weekly Activity", systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        
                        TutoringHoursGraph(sessions: viewModel.upcomingSessions)
                            .frame(height: 200)
                    }
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)
                    
                    // Stats Grid
                    HStack(spacing: 16) {
                        StatCard(
                            title: "Upcoming\nSessions",
                            value: "\(viewModel.upcomingSessions.count)",
                            icon: "calendar.circle.fill",
                            color: .blue,
                            height: 120 // Fixed height for alignment
                        )
                        
                        StatCard(
                            title: "Rating",
                            value: String(format: "%.1f", viewModel.averageRating),
                            icon: "star.circle.fill",
                            color: .yellow,
                            height: 120 // Fixed height for alignment
                        )
                    }
                    .padding(.horizontal)
                    
                    // Pending Requests Section
                    if !viewModel.pendingRequests.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Pending Requests", systemImage: "person.2.circle.fill")
                                    .font(.title3.bold())
                                Spacer()
                                Text("\(viewModel.pendingRequests.count)")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(viewModel.pendingRequests) { request in
                                        RequestCard(request: request) { approved in
                                            viewModel.handleRequest(request, approved: approved)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.blue.opacity(0.05),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Dashboard")
            .refreshable {
                await viewModel.refreshData()
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let height: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5)
        }
    }
}

struct RequestCard: View {
    let request: TutoringRequest
    let onResponse: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.subject)
                .font(.headline)
            
            Text(request.dateTime.formatted(date: .numeric, time: .shortened))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button(action: { onResponse(true) }) {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                Button(action: { onResponse(false) }) {
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .frame(width: 280)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct SessionRowView: View {
    let session: TutoringSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.subject)
                    .font(.headline)
                Spacer()
                StatusBadge(status: .session(session.status))
            }
            
            Text(session.dateTime.formatted(date: .long, time: .shortened))
            Text("\(session.duration) minutes")
            
            if let notes = session.notes {
                Text("Notes: \(notes)")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct RequestRow: View {
    let request: TutoringRequest
    let onResponse: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(request.subject) Session Request")
                .font(.headline)
            
            Text("Date: \(request.dateTime.formatted(date: .long, time: .shortened))")
            Text("Duration: \(request.duration) minutes")
            
            if let notes = request.notes {
                Text("Notes: \(notes)")
                    .foregroundColor(.secondary)
            }
            
            if request.isNewSubject {
                Text("New Subject Request")
                    .foregroundColor(.orange)
            }
            
            if request.isOutsideAvailability {
                Text("Outside Regular Availability")
                    .foregroundColor(.orange)
            }
            
            HStack {
                Button("Approve") {
                    onResponse(true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                Button("Decline") {
                    onResponse(false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.vertical, 8)
    }
}

struct CalendarView: View {
    @State private var selectedDate = Date()
    
    var body: some View {
        VStack {
            DatePicker(
                "Select Date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(GraphicalDatePickerStyle())
            
            // Sessions for selected date would be shown here
        }
    }
}

struct TutoringHoursGraph: View {
    let sessions: [TutoringSession]
    @State private var animateGraph = false
    @State private var selectedPoint: Int? = nil
    private let firebase = FirebaseManager.shared
    
    var dailyHours: [(date: Date, hours: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        guard let currentUserId = firebase.auth.currentUser?.uid else { return [] }
        
        // Create array of last 7 days
        var days: [(date: Date, hours: Double)] = []
        for dayOffset in 0...6 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: sevenDaysAgo) {
                days.append((date: date, hours: 0.0))
            }
        }
        
        // Include both tutoring and learning sessions
        let relevantSessions = sessions.filter { session in
            session.status == .completed && 
            (session.tutorId == currentUserId || session.studentId == currentUserId)
        }
        
        // Calculate hours for each session
        for session in relevantSessions {
            let sessionDate = calendar.startOfDay(for: session.dateTime)
            if sessionDate >= sevenDaysAgo && sessionDate <= today {
                if let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: sessionDate) }) {
                    days[index].hours += Double(session.duration) / 60.0
                }
            }
        }
        
        return days
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Hours")
                .font(.headline)
            
            if dailyHours.isEmpty {
                Text("No tutoring activity yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.vertical, 60)
                    .frame(maxWidth: .infinity)
            } else {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let maxHours = max(dailyHours.map { $0.hours }.max() ?? 0, 1)
                    
                    // Background grid lines with gradient opacity
                    VStack(spacing: height / 4) {
                        ForEach(0..<4) { i in
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 1)
                        }
                    }
                    
                    // Curved graph line
                    Path { path in
                        let points = dailyHours.enumerated().map { index, day -> CGPoint in
                            let x = width * CGFloat(index) / CGFloat(dailyHours.count - 1)
                            let y = height - (height * CGFloat(day.hours) / CGFloat(maxHours))
                            return CGPoint(x: x, y: y)
                        }
                        
                        if let first = points.first {
                            path.move(to: first)
                            for i in 1..<points.count {
                                let previous = points[i-1]
                                let current = points[i]
                                let control1 = CGPoint(x: previous.x + (current.x - previous.x) / 2, y: previous.y)
                                let control2 = CGPoint(x: previous.x + (current.x - previous.x) / 2, y: current.y)
                                path.addCurve(to: current, control1: control1, control2: control2)
                            }
                        }
                    }
                    .trim(from: 0, to: animateGraph ? 1 : 0)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    
                    // Interactive data points
                    ForEach(dailyHours.indices, id: \.self) { index in
                        let x = width * CGFloat(index) / CGFloat(dailyHours.count - 1)
                        let y = height - (height * CGFloat(dailyHours[index].hours) / CGFloat(maxHours))
                        
                        Circle()
                            .fill(selectedPoint == index ? Color.blue : Color.white)
                            .frame(width: selectedPoint == index ? 12 : 8, height: selectedPoint == index ? 12 : 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                            .position(x: x, y: y)
                            .opacity(animateGraph ? 1 : 0)
                            .overlay(
                                Group {
                                    if selectedPoint == index {
                                        Text(String(format: "%.1f hrs", dailyHours[index].hours))
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(.systemBackground))
                                                    .shadow(radius: 2)
                                            )
                                            .offset(y: -24)
                                    }
                                }
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedPoint = selectedPoint == index ? nil : index
                                }
                            }
                    }
                }
            }
        }
        .frame(height: 200)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5)) {
                animateGraph = true
            }
        }
    }
}
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
