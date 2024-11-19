import SwiftUI

struct AvailabilityView: View {
    let availability: [TimeSlot]
    let isCompact: Bool
    
    init(availability: [TimeSlot], isCompact: Bool = false) {
        self.availability = availability
        self.isCompact = isCompact
    }
    
    private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isCompact {
                Label("Availability", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            
            ForEach(availability.sorted(by: { $0.dayOfWeek < $1.dayOfWeek }), id: \.self) { slot in
                HStack {
                    Text(weekdays[slot.dayOfWeek - 1])
                        .frame(width: isCompact ? 80 : 100, alignment: .leading)
                        .font(isCompact ? .caption : .subheadline)
                    
                    Text(slot.startTime.formatted(date: .omitted, time: .shortened))
                        .font(isCompact ? .caption : .subheadline)
                    Text("-")
                        .font(isCompact ? .caption : .subheadline)
                        .foregroundColor(.secondary)
                    Text(slot.endTime.formatted(date: .omitted, time: .shortened))
                        .font(isCompact ? .caption : .subheadline)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
} 