import SwiftUI
import FirebaseFirestore

public enum TutoringRequestType {
    case incoming, outgoing
}

public struct TutoringRequestRow: View {
    private let request: TutoringRequest
    private let type: TutoringRequestType
    private let onResponse: (Bool) -> Void
    private let firebase = FirebaseManager.shared
    @State private var otherPartyName: String = "Loading..."
    
    public init(request: TutoringRequest, type: TutoringRequestType, onResponse: @escaping (Bool) -> Void) {
        self.request = request
        self.type = type
        self.onResponse = onResponse
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(request.subject)
                    .font(.headline)
                Spacer()
                StatusBadge(status: .request(.pending))
            }
            
            // Add the other party's role and name
            if let currentUserId = firebase.auth.currentUser?.uid {
                Text(request.tutorId == currentUserId ? "Student" : "Tutor")
                    .font(.subheadline)
                    .foregroundColor(.secondary) +
                Text(": \(otherPartyName)")
                    .font(.subheadline)
            }
            
            // Time and Duration
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text(request.dateTime.formatted(date: .numeric, time: .shortened))
                    .font(.subheadline)
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(request.duration)min")
                    .font(.subheadline)
            }
            
            if let notes = request.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if request.isNewSubject {
                Label("New Subject Request", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            if request.isOutsideAvailability {
                Label("Outside Regular Hours", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            // Only show action buttons for incoming requests
            if type == .incoming {
                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            onResponse(true)
                        }
                    } label: {
                        Text("Approve")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button {
                        withAnimation {
                            onResponse(false)
                        }
                    } label: {
                        Text("Decline")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            fetchOtherPartyName()
        }
    }
    
    private func fetchOtherPartyName() {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        let otherPartyId = request.tutorId == currentUserId ? request.studentId : request.tutorId
        
        firebase.firestore.collection("users").document(otherPartyId).getDocument { snapshot, error in
            if let error = error {
                print("Error fetching user name: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    otherPartyName = "Unknown User"
                }
                return
            }
            
            if let data = snapshot?.data(),
               let name = data["name"] as? String {
                DispatchQueue.main.async {
                    otherPartyName = name
                }
            } else {
                DispatchQueue.main.async {
                    otherPartyName = "Unknown User"
                }
            }
        }
    }
} 