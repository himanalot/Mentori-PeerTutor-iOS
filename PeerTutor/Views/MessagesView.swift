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

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let sender: String
    let content: String
    let timestamp: Date
    let isFromCurrentUser: Bool
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.sender == rhs.sender &&
        lhs.content == rhs.content &&
        lhs.timestamp == rhs.timestamp &&
        lhs.isFromCurrentUser == rhs.isFromCurrentUser
    }
}

// MARK: - Messages View
struct MessagesView: View {
    @StateObject private var viewModel = MessagesViewModel()
    @State private var showingNewMessage = false
    @State private var selectedMessage: Message?
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "message.fill",
                        description: Text("You don't have any active conversations")
                    )
                } else {
                    List {
                        ForEach(viewModel.messages) { message in
                            Button {
                                selectedMessage = message
                            } label: {
                                MessageRow(message: message)
                            }
                        }
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
                .environmentObject(viewModel)
            }
            .sheet(item: $selectedMessage) { message in
                NavigationView {
                    ChatView(
                        conversation: message.conversation,
                        tutorName: message.sender,
                        tutorId: message.tutorId
                    )
                }
            }
            .refreshable {
                await viewModel.refreshMessages()
            }
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    let conversation: [ChatMessage]
    let tutorName: String
    let tutorId: String
    @State private var messageText = ""
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var isSendingMessage = false
    
    init(conversation: [ChatMessage], tutorName: String, tutorId: String) {
        self.conversation = conversation
        self.tutorName = tutorName
        self.tutorId = tutorId
        _viewModel = StateObject(wrappedValue: ChatViewModel(tutorId: tutorId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .padding(.horizontal)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages) { _, messages in
                    if let lastMessage = messages.last {
                        withAnimation {
                            scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Message input area
            HStack(alignment: .center, spacing: 8) {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 8)
                
                if !messageText.isEmpty {
                    Button {
                        let message = messageText
                        messageText = ""
                        viewModel.sendMessage(content: message)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
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
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
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

// MARK: - Chat Bubble
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

// MARK: - Messages ViewModel
class MessagesViewModel: ObservableObject {
    @Published var messages: [Message] = []
    private let firebase = FirebaseManager.shared
    private var tutorNames: [String: String] = [:]
    
    init() {
        listenForMessages()
    }
    
    func startNewChat(with tutor: User) {
        guard let tutorId = tutor.id else { return }
        messages.append(Message(
            sender: tutor.name,
            lastMessage: "Start a conversation",
            timestamp: Date(),
            conversation: [],
            tutorId: tutorId
        ))
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
                guard let documents = snapshot?.documents else { return }
                
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
                if let messageIndex = messages.firstIndex(where: { $0.tutorId == tutorId }) {
                    messages[messageIndex].sender = tutorNames[tutorId]!
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

// MARK: - New Message View
struct NewMessageView: View {
    @Binding var isPresented: Bool
    let onSelectTutor: (User) -> Void
    @StateObject private var tutorSearchViewModel = TutorSearchViewModel()
    @State private var searchText = ""
    @EnvironmentObject private var messagesViewModel: MessagesViewModel
    
    var filteredTutors: [User] {
        // Get set of tutor IDs that already have conversations
        let existingTutorIds = Set(messagesViewModel.messages.map { $0.tutorId })
        
        // Filter tutors
        let availableTutors = tutorSearchViewModel.tutors.filter { tutor in
            guard let tutorId = tutor.id else { return false }
            return !existingTutorIds.contains(tutorId)
        }
        
        if searchText.isEmpty {
            return availableTutors
        }
        
        return availableTutors.filter { tutor in
            tutor.name.localizedCaseInsensitiveContains(searchText) ||
            tutor.subjects.map { $0.name }.joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if filteredTutors.isEmpty {
                    VStack(spacing: 16) {
                        Text("No New Tutors Available")
                            .font(.headline)
                        Text("You already have conversations with all available tutors")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
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
