import SwiftUI

struct MessagesListView: View {
    let messages: [ChatMessage]
    @State private var newMessage = ""
    @StateObject private var viewModel: ChatViewModel
    
    init(messages: [ChatMessage], tutorId: String) {
        self.messages = messages
        _viewModel = StateObject(wrappedValue: ChatViewModel(tutorId: tutorId))
    }
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            
            HStack {
                TextField("Message", text: $newMessage)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: {
                    if !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.sendMessage(content: newMessage)
                        newMessage = ""
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isFromCurrentUser {
                Spacer()
            }
            
            Text(message.content)
                .padding(12)
                .background(message.isFromCurrentUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isFromCurrentUser ? .white : .primary)
                .cornerRadius(16)
            
            if !message.isFromCurrentUser {
                Spacer()
            }
        }
    }
} 