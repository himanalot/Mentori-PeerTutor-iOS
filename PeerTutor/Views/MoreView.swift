import SwiftUI

struct MoreView: View {
    @StateObject private var alertsViewModel = AlertsViewModel()
    
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: ProfileView()) {
                    Label("Profile", systemImage: "person.circle")
                }
                
                NavigationLink(destination: AlertsView()) {
                    HStack {
                        Label("Alerts", systemImage: "bell.fill")
                        Spacer()
                        if alertsViewModel.unreadCount > 0 {
                            Text("\(alertsViewModel.unreadCount)")
                                .foregroundColor(.white)
                                .font(.caption2.bold())
                                .padding(6)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .navigationTitle("More")
        }
        .tabItem {
            Label("More", systemImage: "ellipsis")
        }
        .badge(alertsViewModel.unreadCount)
    }
} 