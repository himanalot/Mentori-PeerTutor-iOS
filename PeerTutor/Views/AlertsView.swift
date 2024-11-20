import SwiftUI
import FirebaseFirestore

class AlertsViewModel: ObservableObject {
    @Published var alerts: [Alert] = []
    @Published var unreadCount: Int = 0
    private let firebase = FirebaseManager.shared
    
    init() {
        listenForAlerts()
    }
    
    private func listenForAlerts() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        firebase.firestore.collection("alerts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.alerts = documents.compactMap { document in
                    var alert = try? document.data(as: Alert.self)
                    alert?.id = document.documentID
                    return alert
                }
                
                self?.unreadCount = self?.alerts.filter { !$0.isRead }.count ?? 0
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
                var alert = try? document.data(as: Alert.self)
                alert?.id = document.documentID
                return alert
            }
            
            self.unreadCount = self.alerts.filter { !$0.isRead }.count
        }
    }
}

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
    case newRequest
    case requestUpdate
    case upcomingSession
    case sessionCancelled
    case newReview
    case reviewReminder
}

struct AlertsView: View {
    @StateObject private var viewModel = AlertsViewModel()
    
    var body: some View {
        NavigationView {
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
                    }
                }
            }
            .navigationTitle("Alerts")
            .toolbar {
                if !viewModel.alerts.isEmpty {
                    Button("Clear All") {
                        viewModel.markAllAsRead()
                    }
                }
            }
            .refreshable {
                await viewModel.refreshAlerts()
            }
        }
        .tabItem {
            Image(systemName: "bell.fill")
            Text("Alerts")
        }
        .badge(viewModel.unreadCount)
    }
}

struct AlertRow: View {
    let alert: Alert
    
    var body: some View {
        HStack {
            Circle()
                .fill(alert.isRead ? Color.clear : Color.blue)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.message)
                    .font(.subheadline)
                
                Text(alert.timestamp.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
} 