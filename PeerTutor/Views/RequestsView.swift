// RequestsView.swift
import SwiftUI
import FirebaseFirestore
import FirebaseFirestoreSwift

enum RequestType {
    case incoming, outgoing
}

class RequestsViewModel: ObservableObject {
    @Published var outgoingRequests: [TutoringRequest] = []
    @Published var incomingRequests: [TutoringRequest] = []
    @Published var showError = false
    @Published var errorMessage: String?
    private let firebase = FirebaseManager.shared
    
    init() {
        listenForRequests()
    }
    
    func handleRequest(_ request: TutoringRequest, approved: Bool) {
        guard let requestId = request.documentId else { return }
        
        let db = firebase.firestore
        let batch = db.batch()
        
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
                documentId: nil
            )
            
            // Create alert for student
            let studentAlert = [
                "userId": request.studentId,
                "type": NotificationAlertType.requestAccepted.rawValue,
                "message": "Your tutoring request for \(request.subject) has been accepted",
                "relatedId": requestId,
                "timestamp": FieldValue.serverTimestamp(),
                "isRead": false
            ] as [String : Any]
            
            let studentAlertRef = db.collection("alerts").document()
            batch.setData(studentAlert, forDocument: studentAlertRef)
            
            // Add session and update request status
            do {
                let sessionRef = db.collection("sessions").document()
                try batch.setData(from: session, forDocument: sessionRef)
                batch.updateData(["status": TutoringRequest.RequestStatus.approved.rawValue], forDocument: db.collection("requests").document(requestId))
            } catch {
                print("Error encoding session: \(error)")
                return
            }
        } else {
            // Create decline alert for student
            let studentAlert = [
                "userId": request.studentId,
                "type": NotificationAlertType.requestDeclined.rawValue,
                "message": "Your tutoring request for \(request.subject) has been declined",
                "relatedId": requestId,
                "timestamp": FieldValue.serverTimestamp(),
                "isRead": false
            ] as [String : Any]
            
            let studentAlertRef = db.collection("alerts").document()
            batch.setData(studentAlert, forDocument: studentAlertRef)
            
            // Update request status
            batch.updateData(
                ["status": TutoringRequest.RequestStatus.declined.rawValue],
                forDocument: db.collection("requests").document(requestId)
            )
        }
        
        // Commit all changes
        batch.commit()
    }
    
    private func listenForRequests() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        // Listen for outgoing requests
        firebase.firestore.collection("requests")
            .whereField("studentId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching outgoing requests: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                self?.outgoingRequests = documents.compactMap { document in
                    var request = try? document.data(as: TutoringRequest.self)
                    request?.documentId = document.documentID
                    return request
                }
            }
        
        // Listen for incoming requests
        firebase.firestore.collection("requests")
            .whereField("tutorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching incoming requests: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                self?.incomingRequests = documents.compactMap { document in
                    var request = try? document.data(as: TutoringRequest.self)
                    request?.documentId = document.documentID
                    return request
                }
            }
    }
    
    func getStatusText(for status: TutoringRequest.RequestStatus) -> String {
        switch status {
        case .pending:
            return "Awaiting Response"
        case .approved:
            return "Request Approved"
        case .declined:
            return "Tutor Unavailable"
        }
    }
    
    @MainActor
    func refreshRequests() async {
        listenForRequests()
    }
}

struct RequestsView: View {
    @StateObject private var viewModel = RequestsViewModel()
    
    var body: some View {
        NavigationView {
            List {
                if !viewModel.outgoingRequests.isEmpty {
                    Section("Outgoing Requests") {
                        ForEach(viewModel.outgoingRequests) { request in
                            RequestRowView(request: request, type: .outgoing, viewModel: viewModel)
                        }
                    }
                }
                
                if !viewModel.incomingRequests.isEmpty {
                    Section("Incoming Requests") {
                        ForEach(viewModel.incomingRequests) { request in
                            RequestRowView(request: request, type: .incoming, viewModel: viewModel)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if request.status == .pending {
                                        Button("Approve") {
                                            viewModel.handleRequest(request, approved: true)
                                        }
                                        .tint(.green)
                                        
                                        Button("Decline") {
                                            viewModel.handleRequest(request, approved: false)
                                        }
                                        .tint(.red)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Requests")
            .refreshable {
                await viewModel.refreshRequests()
            }
        }
    }
}

struct RequestRowView: View {
    let request: TutoringRequest
    let type: RequestType
    @ObservedObject var viewModel: RequestsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(request.subject) Session Request")
                    .font(.headline)
                Spacer()
                StatusBadge(status: .request(request.status))
            }
            
            Text("Date: \(request.dateTime.formatted(date: .long, time: .shortened))")
            Text("Duration: \(request.duration) minutes")
            
            if let notes = request.notes, !notes.isEmpty {
                Text("Notes: \(notes)")
                    .foregroundColor(.secondary)
            }
            
            if request.isNewSubject {
                Label("New Subject Request", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            
            if request.isOutsideAvailability {
                Label("Outside Regular Availability", systemImage: "clock.badge.exclamationmark")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            
            if type == .incoming && request.status == .pending {
                HStack {
                    Button("Approve") {
                        viewModel.handleRequest(request, approved: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button("Decline") {
                        viewModel.handleRequest(request, approved: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                Text(viewModel.getStatusText(for: request.status))
                    .foregroundColor(getStatusColor(for: request.status))
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
    
    private func getStatusColor(for status: TutoringRequest.RequestStatus) -> Color {
        switch status {
        case .pending:
            return .gray
        case .approved:
            return .green
        case .declined:
            return .red
        }
    }
}

#Preview {
    RequestsView()
}
