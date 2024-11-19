import SwiftUI
import FirebaseFirestore
import EventKit

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
    @State private var showingCalendarAlert = false
    
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
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
