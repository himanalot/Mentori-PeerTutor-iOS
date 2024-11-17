import SwiftUI
import FirebaseFirestore

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var tutor: User?
    private let firebase = FirebaseManager.shared
    
    func loadTutor(tutorId: String) {
        firebase.firestore.collection("users").document(tutorId).getDocument { [weak self] snapshot, error in
            if let data = snapshot?.data() {
                self?.tutor = try? Firestore.Decoder().decode(User.self, from: data)
            }
        }
    }
    
    func sendMessage(to tutorId: String, content: String) {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        let message = [
            "senderId": currentUserId,
            "receiverId": tutorId,
            "content": content,
            "timestamp": Timestamp(date: Date())
        ] as [String: Any]
        
        firebase.firestore.collection("messages").addDocument(data: message)
    }
    
    func listenForMessages(tutorId: String) {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        firebase.firestore.collection("messages")
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
}
