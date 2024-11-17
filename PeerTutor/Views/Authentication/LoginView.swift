import SwiftUI
import FirebaseFirestore

class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isAuthenticated: Bool = false
    @Published var name: String = ""
    @Published var confirmPassword: String = ""
    @Published var errorMessage: String = ""
    
    private let firebase = FirebaseManager.shared
    
    init() {
        // Check if user is already signed in
        isAuthenticated = firebase.auth.currentUser != nil
        
        // Listen for auth state changes
        firebase.auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    func login() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        firebase.auth.signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    print("Login error: \(error.localizedDescription)")
                    return
                }
                
                if let userId = result?.user.uid {
                    print("Successfully logged in with ID: \(userId)")
                    self?.isAuthenticated = true
                    // Trigger user fetch in FirebaseManager
                    self?.firebase.fetchUser(userId: userId)
                }
            }
        }
    }
    
    func register() {
        // Basic validation
        guard !email.isEmpty, !password.isEmpty, !name.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }
        
        firebase.auth.createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let userId = result?.user.uid else { return }
                
                // Create the user document
                let newUser = User(
                    id: userId,  // Use the auth UID as the document ID
                    email: self.email,
                    name: self.name,
                    profileImageUrl: nil,
                    subjects: [],
                    availability: [],
                    bio: ""
                )
                
                // Store user data in Firestore using the auth UID as the document ID
                do {
                    try self.firebase.firestore
                        .collection("users")
                        .document(userId)  // Explicitly set document ID
                        .setData(from: newUser)
                    
                    self.isAuthenticated = true
                } catch {
                    self.errorMessage = "Error creating user profile"
                }
            }
        }
    }
    
    func signOut() {
        do {
            try firebase.auth.signOut()
            isAuthenticated = false
            // Reset user data
            email = ""
            password = ""
            name = ""
            confirmPassword = ""
            errorMessage = ""
        } catch {
            errorMessage = "Error signing out"
        }
    }
}

struct RegisterView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("Full Name", text: $viewModel.name)
                        .textContentType(.name)
                    
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("Security")) {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.newPassword)
                    
                    SecureField("Confirm Password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                }
                
                if !viewModel.errorMessage.isEmpty {
                    Section {
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button(action: viewModel.register) {
                        Text("Create Account")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showingRegistration = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("PeerTutor")
                    .font(.largeTitle)
                    .bold()
                
                TextField("Email", text: $viewModel.email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                
                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .textContentType(.password)
                
                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: viewModel.login) {
                    Text("Login")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Button("Create Account") {
                    showingRegistration = true
                }
                .padding()
            }
            .padding()
            .sheet(isPresented: $showingRegistration) {
                RegisterView(viewModel: viewModel)
            }
        }
    }
} 
