import SwiftUI
import FirebaseFirestore

// MARK: - Models
struct Message: Identifiable {
    let id = UUID()
    var sender: String // Now holds the tutor's name
    let lastMessage: String
    let timestamp: Date
    var conversation: [ChatMessage]
    let tutorId: String
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: String
    let content: String
    let timestamp: Date
    let isFromCurrentUser: Bool
}

// MARK: - Messages View
struct MessagesView: View {
    @StateObject private var viewModel = MessagesViewModel()
    @State private var showingNewMessage = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.messages) { message in
                    NavigationLink(
                        destination: ChatView(
                            conversation: message.conversation,
                            tutorName: message.sender,
                            tutorId: message.tutorId
                        )
                    ) {
                        MessageRow(message: message)
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewMessage = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingNewMessage) {
                NewMessageView(isPresented: $showingNewMessage, onSelectTutor: { tutor in
                    viewModel.startNewChat(with: tutor)
                })
            }
            .refreshable {
                await viewModel.refreshMessages()
            }
        }
    }
}

// MARK: - New Message View
struct NewMessageView: View {
    @Binding var isPresented: Bool
    let onSelectTutor: (User) -> Void
    @StateObject private var tutorSearchViewModel = TutorSearchViewModel()
    @State private var searchText = ""
    
    var filteredTutors: [User] {
        if searchText.isEmpty {
            return tutorSearchViewModel.tutors
        }
        return tutorSearchViewModel.tutors.filter { tutor in
            tutor.name.localizedCaseInsensitiveContains(searchText) ||
            tutor.subjects.map { $0.name }.joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredTutors) { tutor in
                    Button(action: {
                        onSelectTutor(tutor)
                        isPresented = false
                    }) {
                        TutorRowView(tutor: tutor)
                    }
                }
            }
            .navigationTitle("New Message")
            .searchable(text: $searchText, prompt: "Search tutors")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Messages ViewModel
class MessagesViewModel: ObservableObject {
    @Published var messages: [Message] = []
    private let firebase = FirebaseManager.shared
    private var tutorNames: [String: String] = [:] // Cache for tutor names
    
    init() {
        listenForMessages()
    }
    
    func startNewChat(with tutor: User) {
        guard let tutorId = tutor.id,
              let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        // Create initial message
        let message = [
            "senderId": currentUserId,
            "receiverId": tutorId,
            "content": "Started a conversation",
            "timestamp": Timestamp(date: Date())
        ] as [String : Any]
        
        firebase.firestore.collection("messages").addDocument(data: message)
    }
    
    private func listenForMessages() {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        firebase.firestore.collection("messages")
            .whereFilter(FirebaseFirestore.Filter.orFilter([
                FirebaseFirestore.Filter.whereField("senderId", isEqualTo: currentUserId),
                FirebaseFirestore.Filter.whereField("receiverId", isEqualTo: currentUserId)
            ]))
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching messages: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                // Group messages by conversation
                var conversationMap: [String: (lastMessage: String, timestamp: Date, messages: [ChatMessage], tutorId: String)] = [:]
                
                for document in documents {
                    let data = document.data()
                    let senderId = data["senderId"] as? String ?? ""
                    let receiverId = data["receiverId"] as? String ?? ""
                    let content = data["content"] as? String ?? ""
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    
                    // Determine the tutorId (the other user)
                    let tutorId = senderId == currentUserId ? receiverId : senderId
                    let conversationId = [senderId, receiverId].sorted().joined(separator: "_")
                    
                    let message = ChatMessage(
                        sender: senderId,
                        content: content,
                        timestamp: timestamp,
                        isFromCurrentUser: senderId == currentUserId
                    )
                    
                    if var existing = conversationMap[conversationId] {
                        if timestamp > existing.timestamp {
                            existing.lastMessage = content
                            existing.timestamp = timestamp
                        }
                        existing.messages.append(message)
                        conversationMap[conversationId] = existing
                    } else {
                        conversationMap[conversationId] = (
                            lastMessage: content,
                            timestamp: timestamp,
                            messages: [message],
                            tutorId: tutorId
                        )
                    }
                }
                
                // Convert conversations to messages array
                self?.messages = conversationMap.map { _, value in
                    Message(
                        sender: value.tutorId,
                        lastMessage: value.lastMessage,
                        timestamp: value.timestamp,
                        conversation: value.messages.sorted { $0.timestamp < $1.timestamp },
                        tutorId: value.tutorId
                    )
                }.sorted { $0.timestamp > $1.timestamp }
                
                self?.fetchTutorNames()
            }
    }
    
    private func fetchTutorNames() {
        for index in messages.indices {
            let tutorId = messages[index].tutorId
            if tutorNames[tutorId] == nil {
                fetchUserName(userId: tutorId) { [weak self] name in
                    guard let self = self else { return }
                    self.tutorNames[tutorId] = name
                    DispatchQueue.main.async {
                        if let messageIndex = self.messages.firstIndex(where: { $0.tutorId == tutorId }) {
                            self.messages[messageIndex].sender = name
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if let messageIndex = self.messages.firstIndex(where: { $0.tutorId == tutorId }) {
                        self.messages[messageIndex].sender = self.tutorNames[tutorId]!
                    }
                }
            }
        }
    }
    
    private func fetchUserName(userId: String, completion: @escaping (String) -> Void) {
        firebase.firestore.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("Error fetching user name: \(error.localizedDescription)")
                completion("Unknown User")
                return
            }
            
            if let data = snapshot?.data(),
               let name = data["name"] as? String {
                completion(name)
            } else {
                completion("Unknown User")
            }
        }
    }
    
    @MainActor
    func refreshMessages() async {
        // Messages will automatically update through the listener
    }
}

// MARK: - Message Row
struct MessageRow: View {
    let message: Message
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(message.sender)
                .font(.headline)
            Text(message.lastMessage)
                .font(.subheadline)
                .foregroundColor(.gray)
            Text(message.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat View
struct ChatView: View {
    let conversation: [ChatMessage]
    let tutorName: String
    let tutorId: String
    @State private var messageText = ""
    @State private var showingTutorProfile = false
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        GeometryReader { geometry in  // Add GeometryReader to fix layout issues
            VStack(spacing: 0) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(conversation) { message in
                                ChatBubble(message: message)
                                    .padding(.horizontal)
                                    .id(message.id)  // Add id for scrolling
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(height: geometry.size.height - 60)  // Fixed height for ScrollView
                }
                
                // Message input area
                HStack(spacing: 8) {
                    TextField("Message", text: $messageText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(height: 40)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.blue)
                            .frame(width: 40, height: 40)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
        .navigationBarItems(trailing:
            NavigationLink(destination: TutorDetailView(tutorId: tutorId)) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.blue)
            }
        )
        .navigationTitle(tutorName)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        viewModel.sendMessage(to: tutorId, content: messageText)
        messageText = ""
    }
}

// Update ChatBubble to have fixed dimensions
struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(spacing: 0) {
            if message.isFromCurrentUser {
                Spacer(minLength: 40)
            }
            
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(message.isFromCurrentUser ? Color.blue : Color(.systemGray6))
                .foregroundColor(message.isFromCurrentUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: message.isFromCurrentUser ? .trailing : .leading)
            
            if !message.isFromCurrentUser {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 8)
    }
}
