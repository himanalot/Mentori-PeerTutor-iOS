//
//  ContentView.swift
//  PeerTutor
//
//  Created by Ishan Ramrakhiani on 11/16/24.
//

import SwiftUI


struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var firebaseManager = FirebaseManager.shared
    @StateObject private var sessionViewModel = SessionViewModel()
    
    var body: some View {
        Group {
            if !firebaseManager.authInitialized {
                ProgressView("Initializing...")
            } else if authViewModel.isAuthenticated {
                if firebaseManager.isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else if let currentUser = firebaseManager.currentUser {
                    MainTabView()
                        .environmentObject(firebaseManager)
                        .environmentObject(sessionViewModel)
                } else {
                    LoginView(viewModel: authViewModel)
                }
            } else {
                LoginView(viewModel: authViewModel)
            }
        }
    }
}

struct MainTabView: View {
    @StateObject private var messageViewModel = MessageViewModel()
    @EnvironmentObject private var firebaseManager: FirebaseManager
    
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house")
                }
            
            TutorSearchView()
                .tabItem {
                    Label("Find Tutor", systemImage: "magnifyingglass")
                }
            
            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
                .badge(messageViewModel.unreadCount > 0 ? String(messageViewModel.unreadCount) : nil)
            
            SessionsView()
                .tabItem {
                    Label("Sessions", systemImage: "calendar")
                }
            
            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
        }
        .environmentObject(messageViewModel)
    }
}

#Preview {
    ContentView()
}
