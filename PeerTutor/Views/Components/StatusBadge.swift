import SwiftUI

struct StatusBadge: View {
    enum StatusType {
        case session(TutoringSession.SessionStatus)
        case request(TutoringRequest.RequestStatus)
    }
    
    let status: StatusType
    
    var body: some View {
        Text(statusText)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(8)
    }
    
    private var statusText: String {
        switch status {
        case .session(let status):
            return status.rawValue.capitalized
        case .request(let status):
            return status.rawValue.capitalized
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .session(let status):
            switch status {
            case .scheduled: return .green
            case .completed: return .blue
            case .cancelled: return .red
            }
        case .request(let status):
            switch status {
            case .pending: return .orange
            case .approved: return .green
            case .declined: return .red
            }
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        StatusBadge(status: .session(.scheduled))
        StatusBadge(status: .session(.completed))
        StatusBadge(status: .session(.cancelled))
        StatusBadge(status: .request(.pending))
        StatusBadge(status: .request(.approved))
        StatusBadge(status: .request(.declined))
    }
    .padding()
} 