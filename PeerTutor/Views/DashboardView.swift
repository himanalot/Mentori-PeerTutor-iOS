import SwiftUI
import FirebaseFirestore

class DashboardViewModel: ObservableObject {
    @Published var upcomingSessions: [TutoringSession] = []
    @Published var totalTutoringHours: Int = 0
    @Published var averageRating: Double = 5.0
    @Published var totalStudentsHelped: Int = 0
    private let firebase = FirebaseManager.shared
    private var tutorNames: [String: String] = [:]
    
    init() {
        listenForSessions()
        calculateStats()
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
            .order(by: "dateTime")
            .limit(to: 5) // Only show next 5 upcoming sessions
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.upcomingSessions = documents.compactMap { document in
                    try? document.data(as: TutoringSession.self)
                }
            }
    }
    
    private func calculateStats() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
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
        
        // Fetch user rating
        firebase.firestore.collection("users")
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let data = snapshot?.data(),
                   let rating = data["averageRating"] as? Double {
                    DispatchQueue.main.async {
                        self?.averageRating = rating
                    }
                }
            }
    }
}

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Stats Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCard(title: "Hours Tutored", value: "\(viewModel.totalTutoringHours)", icon: "clock.fill")
                        StatCard(title: "Students Helped", value: "\(viewModel.totalStudentsHelped)", icon: "person.2.fill")
                        StatCard(title: "Rating", value: String(format: "%.1f", viewModel.averageRating), icon: "star.fill")
                    }
                    .padding(.horizontal)
                    
                    // Upcoming Sessions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Upcoming Sessions")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        if viewModel.upcomingSessions.isEmpty {
                            ContentUnavailableView(
                                "No Upcoming Sessions",
                                systemImage: "calendar",
                                description: Text("You don't have any sessions scheduled")
                            )
                            .padding(.top)
                        } else {
                            ForEach(viewModel.upcomingSessions) { session in
                                DashboardSessionRow(session: session)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Dashboard")
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct DashboardSessionRow: View {
    let session: TutoringSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.subject)
                .font(.headline)
            
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text(session.dateTime.formatted(date: .numeric, time: .shortened))
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(session.duration)min")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            if let notes = session.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}
