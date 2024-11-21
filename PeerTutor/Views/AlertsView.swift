import SwiftUI
import FirebaseFirestore

class AlertsViewModel: ObservableObject {
    @Published var alerts: [NotificationAlert] = []
    @Published var unreadCount: Int = 0
    private let firebase = FirebaseManager.shared
    private var listener: ListenerRegistration?
    
    init() {
        listenForAlerts()
    }
    
    deinit {
        listener?.remove()
    }
    
    private func listenForAlerts() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        // Remove existing listener if any
        listener?.remove()
        
        // Set up new listener
        listener = firebase.firestore.collection("alerts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    self.alerts = documents.compactMap { document in
                        var alert = try? document.data(as: NotificationAlert.self)
                        alert?.id = document.documentID
                        return alert
                    }
                    
                    self.unreadCount = self.alerts.filter { !$0.isRead }.count
                }
            }
    }
    
    func markAllAsRead() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let batch = firebase.firestore.batch()
        
        alerts.filter { !$0.isRead }.forEach { alert in
            if let id = alert.id {
                let ref = firebase.firestore.collection("alerts").document(id)
                batch.updateData(["isRead": true], forDocument: ref)
            }
        }
        
        batch.commit()
    }
    
    @MainActor
    func refreshAlerts() async {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let snapshot = try? await firebase.firestore.collection("alerts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        if let documents = snapshot?.documents {
            self.alerts = documents.compactMap { document in
                var alert = try? document.data(as: NotificationAlert.self)
                alert?.id = document.documentID
                return alert
            }
            
            self.unreadCount = self.alerts.filter { !$0.isRead }.count
        }
    }
}

struct NotificationAlert: Identifiable, Codable {
    var id: String?
    let userId: String
    let type: NotificationAlertType
    let message: String
    let relatedId: String
    let timestamp: Date
    var isRead: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, userId, type, message, relatedId, timestamp, isRead
    }
}

enum NotificationAlertType: String, Codable {
    case newRequest = "New tutoring request"
    case requestAccepted = "Request accepted"
    case requestDeclined = "Request declined"
    case sessionCancelled = "Session cancelled"
    case upcomingSession = "Upcoming session reminder"
    case newReview = "New review received"
}

struct AlertRow: View {
    let alert: NotificationAlert
    @StateObject private var viewModel = AlertRowViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Alert Type Header
            HStack {
                Image(systemName: getIconForType(alert.type))
                    .foregroundColor(getColorForType(alert.type))
                    .font(.system(size: 16, weight: .semibold))
                Text(getDisplayType(alert.type))
                    .font(.headline)
            }
            
            // Alert Message
            Text(alert.message)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            // User Info
            if let userInfo = viewModel.userInfo {
                HStack {
                    Text(getRoleText())
                        .font(.caption)
                        .foregroundColor(.secondary) +
                    Text(": \(userInfo.name)")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            
            // Timestamp
            Text(alert.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if !alert.isRead {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: UIColor.systemBackground))
                        .shadow(color: getColorForType(alert.type).opacity(0.15), radius: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(getColorForType(alert.type).opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Color.clear
                }
            }
        )
        .opacity(alert.isRead ? 0.8 : 1.0)
        .onAppear {
            viewModel.fetchUserInfo(for: alert)
        }
    }
    
    private func getRoleText() -> String {
        guard let currentUserId = FirebaseManager.shared.auth.currentUser?.uid else { return "" }
        
        switch alert.type {
        case .newRequest:
            return currentUserId == alert.userId ? "Student" : "Tutor"
        case .requestAccepted, .requestDeclined:
            let tutorId = alert.relatedId.components(separatedBy: "_").first ?? ""
            return currentUserId == tutorId ? "Student" : "Tutor"
        case .sessionCancelled, .upcomingSession:
            let sessionComponents = alert.relatedId.components(separatedBy: "_")
            let tutorId = sessionComponents[0]
            return currentUserId == tutorId ? "Student" : "Tutor"
        case .newReview:
            return currentUserId == alert.userId ? "Student" : "Tutor"
        }
    }
    
    private func getIconForType(_ type: NotificationAlertType) -> String {
        switch type {
        case .newRequest:
            return "person.2.fill"
        case .requestAccepted:
            return "checkmark.circle.fill"
        case .requestDeclined:
            return "xmark.circle.fill"
        case .sessionCancelled:
            return "calendar.badge.minus"
        case .upcomingSession:
            return "calendar.badge.clock"
        case .newReview:
            return "star.fill"
        }
    }
    
    private func getColorForType(_ type: NotificationAlertType) -> Color {
        switch type {
        case .newRequest:
            return .blue
        case .requestAccepted:
            return .green
        case .requestDeclined:
            return .red
        case .sessionCancelled:
            return .red
        case .upcomingSession:
            return .orange
        case .newReview:
            return .yellow
        }
    }
    
    private func getDisplayType(_ type: NotificationAlertType) -> String {
        switch type {
        case .newRequest:
            return "New Session Request"
        case .requestAccepted:
            return "Request Accepted"
        case .requestDeclined:
            return "Request Declined"
        case .sessionCancelled:
            return "Session Cancelled"
        case .upcomingSession:
            return "New Session Scheduled"
        case .newReview:
            return "New Review"
        }
    }
}

class AlertRowViewModel: ObservableObject {
    @Published var userInfo: User?
    @Published var isUserTutor = false
    private let firebase = FirebaseManager.shared
    
    func fetchUserInfo(for alert: NotificationAlert) {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        // Determine which user ID to fetch based on alert type
        let userIdToFetch: String = {
            switch alert.type {
            case .newRequest:
                return alert.userId // Student's ID
            case .requestAccepted, .requestDeclined:
                return alert.relatedId.components(separatedBy: "_").first ?? "" // Tutor's ID
            case .sessionCancelled, .upcomingSession:
                // For sessions, fetch the other party's info
                let sessionComponents = alert.relatedId.components(separatedBy: "_")
                let tutorId = sessionComponents[0]
                let studentId = sessionComponents[1]
                isUserTutor = tutorId == currentUserId
                return currentUserId == tutorId ? studentId : tutorId
            case .newReview:
                return alert.userId // Student's ID
            }
        }()
        
        firebase.firestore.collection("users").document(userIdToFetch).getDocument { [weak self] snapshot, _ in
            if let userData = try? snapshot?.data(as: User.self) {
                DispatchQueue.main.async {
                    self?.userInfo = userData
                }
            }
        }
    }
}

struct AlertsView: View {
    @StateObject private var viewModel = AlertsViewModel()
    
    var body: some View {
        List {
            if viewModel.alerts.isEmpty {
                ContentUnavailableView(
                    "No Alerts",
                    systemImage: "bell.slash",
                    description: Text("You don't have any notifications")
                )
            } else {
                ForEach(viewModel.alerts) { alert in
                    AlertRow(alert: alert)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Alerts")
        .refreshable {
            await viewModel.refreshAlerts()
        }
        .onAppear {
            viewModel.markAllAsRead()
        }
    }
} 