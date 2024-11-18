import SwiftUI
import FirebaseFirestore

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    private let tutorId: String
    private let firebase = FirebaseManager.shared
    private var listener: ListenerRegistration?
    
    init(tutorId: String) {
        self.tutorId = tutorId
    }
    
    func startListening() {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        listener = firebase.firestore.collection("messages")
            .whereFilter(FirebaseFirestore.Filter.orFilter([
                FirebaseFirestore.Filter.andFilter([
                    FirebaseFirestore.Filter.whereField("senderId", isEqualTo: currentUserId),
                    FirebaseFirestore.Filter.whereField("receiverId", isEqualTo: tutorId)
                ]),
                FirebaseFirestore.Filter.andFilter([
                    FirebaseFirestore.Filter.whereField("senderId", isEqualTo: tutorId),
                    FirebaseFirestore.Filter.whereField("receiverId", isEqualTo: currentUserId)
                ])
            ]))
            .order(by: "timestamp")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.messages = documents.compactMap { document in
                    let data = document.data()
                    let senderId = data["senderId"] as? String ?? ""
                    return ChatMessage(
                        sender: senderId,
                        content: data["content"] as? String ?? "",
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        isFromCurrentUser: senderId == currentUserId
                    )
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
    }
    
    func sendMessage(content: String) {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        let message = [
            "senderId": currentUserId,
            "receiverId": tutorId,
            "content": content,
            "timestamp": Timestamp(date: Date())
        ] as [String: Any]
        
        firebase.firestore.collection("messages").addDocument(data: message)
    }
}
