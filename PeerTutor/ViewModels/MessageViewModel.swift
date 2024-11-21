import SwiftUI
import FirebaseFirestore
import FirebaseFirestoreSwift
import Combine

class MessageViewModel: ObservableObject {
    @Published var unreadCount: Int = 0
    private let firebase = FirebaseManager.shared
    private var listener: ListenerRegistration?
    
    init() {
        listenForUnreadMessages()
    }
    
    deinit {
        listener?.remove()
    }
    
    private func listenForUnreadMessages() {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        listener = firebase.firestore.collection("messages")
            .whereField("recipientId", isEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                DispatchQueue.main.async {
                    self?.unreadCount = documents.count
                }
            }
    }
    
    func markMessagesAsRead(in conversationId: String) {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let batch = firebase.firestore.batch()
        
        firebase.firestore.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("recipientId", isEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                documents.forEach { doc in
                    batch.updateData(["isRead": true], forDocument: doc.reference)
                }
                
                batch.commit()
            }
    }
} 