import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFirestoreSwift

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    let auth: Auth
    let storage: Storage
    let firestore: Firestore
    
    @Published var currentUser: User?
    @Published var isLoading: Bool = false
    @Published var authInitialized: Bool = false
    
    private init() {
        self.auth = Auth.auth()
        self.storage = Storage.storage()
        self.firestore = Firestore.firestore()
        
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                if let firebaseUser = user {
                    self?.fetchUser(userId: firebaseUser.uid)
                } else {
                    self?.currentUser = nil
                    self?.isLoading = false
                }
                self?.authInitialized = true
            }
        }
    }
    
    func fetchUser(userId: String) {
        isLoading = true
        print("Fetching user with ID: \(userId)")
        
        let userRef = firestore.collection("users").document(userId)
        userRef.getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching user: \(error.localizedDescription)")
                    self?.isLoading = false
                    return
                }
                
                if let snapshot = snapshot, snapshot.exists {
                    do {
                        let user = try snapshot.data(as: User.self)
                        self?.currentUser = user
                        print("Successfully fetched user: \(user.name)")
                    } catch {
                        print("Error decoding user: \(error)")
                        print("Document data: \(snapshot.data() ?? [:])")
                    }
                } else {
                    print("Creating new user document for ID: \(userId)")
                    if let auth = self?.auth.currentUser {
                        let newUser = User(
                            id: userId,
                            email: auth.email ?? "",
                            name: auth.displayName ?? "User",
                            profileImageUrl: nil,
                            subjects: [],
                            availability: [],
                            bio: "",
                            averageRating: 5.0,
                            totalReviews: 0
                        )
                        
                        do {
                            try self?.firestore.collection("users")
                                .document(userId)
                                .setData(from: newUser)
                            
                            self?.currentUser = newUser
                            print("Created new user document for ID: \(userId)")
                        } catch {
                            print("Error creating user document: \(error.localizedDescription)")
                        }
                    }
                }
                
                self?.isLoading = false
            }
        }
    }
    
    func signOut() {
        do {
            try auth.signOut()
            DispatchQueue.main.async {
                self.currentUser = nil
                self.isLoading = false
            }
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    func uploadProfileImage(_ image: UIImage, for userId: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not compress image"])
        }
        
        let storageRef = storage.reference().child("profile_images/\(userId).jpg")
        
        // Upload image data
        _ = try await storageRef.putDataAsync(imageData, metadata: nil)
        
        // Get download URL
        let downloadURL = try await storageRef.downloadURL()
        
        // Update user document with new image URL
        try await firestore.collection("users").document(userId).updateData([
            "profileImageUrl": downloadURL.absoluteString
        ])
        
        // Update current user
        if var updatedUser = currentUser {
            updatedUser.profileImageUrl = downloadURL.absoluteString
            self.currentUser = updatedUser
        }
        
        return downloadURL.absoluteString
    }
    
    func loadProfileImage(from urlString: String?) async -> Data? {
        guard let urlString = urlString,
              let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            print("Error loading profile image: \(error.localizedDescription)")
            return nil
        }
    }
} 
