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
    }
} 