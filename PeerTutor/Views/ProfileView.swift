import SwiftUI
import FirebaseFirestore
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingEditProfile = false
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        if let imageData = viewModel.profileImage,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.gray)
                        }
                        
                        Button("Change Photo") {
                            showingImagePicker = true
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Text("Name: \(viewModel.name)")
                    Text("Email: \(viewModel.email)")
                }
                
                Section(header: Text("Tutoring Profile")) {
                    Button("Edit Profile") {
                        showingEditProfile = true
                    }
                    
                    ForEach(viewModel.subjects, id: \.self) { subject in
                        Text(subject)
                    }
                    
                    Text("Availability: \(viewModel.availability)")
                    Text("Bio: \(viewModel.bio)")
                }
                
                Section(header: Text("Reviews")) {
                    if viewModel.reviewsWithNames.isEmpty {
                        Text("No reviews yet")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(viewModel.reviewsWithNames) { review in
                            ReviewRow(review: review)
                        }
                    }
                }
                
                Section {
                    Button("Sign Out") {
                        viewModel.signOut()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingEditProfile) {
                TutorProfileEditView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $inputImage)
            }
            .onChange(of: inputImage) { _ in
                viewModel.updateProfileImage(inputImage)
            }
        }
    }
}

class ProfileViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var subjects: [String] = []
    @Published var availability: String = ""
    @Published var bio: String = ""
    @Published var reviews: [Review] = []
    @Published var profileImage: Data?
    @Published private var studentNames: [String: String] = [:]
    
    private let firebase = FirebaseManager.shared
    
    init() {
        // Load user data from Firebase
        if let currentUser = firebase.currentUser {
            self.name = currentUser.name
            self.email = currentUser.email
            self.subjects = currentUser.subjects.map { $0.name }
            self.availability = formatAvailability(currentUser.availability)
            self.bio = currentUser.bio
            fetchReviews(for: currentUser.id)
        }
        
        // Listen for user updates
        firebase.auth.addStateDidChangeListener { [weak self] _, user in
            if let firebaseUser = user {
                self?.fetchUserData(userId: firebaseUser.uid)
            }
        }
    }
    
    private func formatAvailability(_ timeSlots: [TimeSlot]) -> String {
        return timeSlots.map { slot in
            "\(slot.dayOfWeek): \(slot.startTime.formatted(date: .omitted, time: .shortened)) - \(slot.endTime.formatted(date: .omitted, time: .shortened))"
        }.joined(separator: "\n")
    }
    
    private func fetchUserData(userId: String) {
        firebase.firestore.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            if let data = snapshot?.data(),
               let user = try? Firestore.Decoder().decode(User.self, from: data) {
                DispatchQueue.main.async {
                    self?.name = user.name
                    self?.email = user.email
                    self?.subjects = user.subjects.map { $0.name }
                    self?.availability = self?.formatAvailability(user.availability) ?? ""
                    self?.bio = user.bio
                    if let userId = user.id {
                        self?.fetchReviews(for: userId)
                    }
                }
            }
        }
    }
    
    private func fetchReviews(for userId: String?) {
        guard let userId = userId else { return }
        
        firebase.firestore.collection("reviews")
            .whereField("tutorId", isEqualTo: userId)
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching reviews: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    self?.reviews = documents.compactMap { document in
                        let data = document.data()
                        return Review(
                            id: document.documentID,
                            rating: data["rating"] as? Int ?? 0,
                            comment: data["comment"] as? String ?? "",
                            date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
                            studentId: data["studentId"] as? String ?? ""
                        )
                    }
                    
                    // Fetch student names for reviews
                    self?.fetchStudentNames(for: self?.reviews ?? [])
                }
            }
    }
    
    private func fetchStudentNames(for reviews: [Review]) {
        let studentIds = Set(reviews.map { $0.studentId })
        
        for studentId in studentIds {
            firebase.firestore.collection("users").document(studentId).getDocument { [weak self] snapshot, error in
                if let data = snapshot?.data(),
                   let name = data["name"] as? String {
                    DispatchQueue.main.async {
                        self?.studentNames[studentId] = name
                    }
                }
            }
        }
    }
    
    func updateProfileImage(_ image: UIImage?) {
        guard let image = image,
              let data = image.jpegData(compressionQuality: 0.8),
              let userId = firebase.auth.currentUser?.uid else { return }
        
        let storageRef = firebase.storage.reference().child("profileImages/\(userId).jpg")
        
        storageRef.putData(data, metadata: nil) { [weak self] _, error in
            if error == nil {
                storageRef.downloadURL { url, _ in
                    if let downloadURL = url {
                        self?.firebase.firestore.collection("users").document(userId).updateData([
                            "profileImageUrl": downloadURL.absoluteString
                        ])
                        DispatchQueue.main.async {
                            self?.profileImage = data
                        }
                    }
                }
            }
        }
    }
    
    func signOut() {
        do {
            try firebase.auth.signOut()
            // Clear local user data
            name = ""
            email = ""
            subjects = []
            availability = ""
            bio = ""
            reviews = []
            profileImage = nil
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    func updateTutorProfile(subjects: [String], timeSlots: [TimeSlot], bio: String) {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let subjectObjects = subjects.map { Subject(name: $0, level: "Regular") }
        
        // Update the user document directly
        do {
            try firebase.firestore
                .collection("users")
                .document(userId)
                .updateData([
                    "subjects": subjectObjects.map { ["name": $0.name, "level": $0.level] },
                    "availability": timeSlots.map { [
                        "dayOfWeek": $0.dayOfWeek,
                        "startTime": Timestamp(date: $0.startTime),
                        "endTime": Timestamp(date: $0.endTime)
                    ] },
                    "bio": bio
                ])
            
            // Update local state
            self.subjects = subjects
            self.availability = timeSlots.map { slot in
                "\(slot.dayOfWeek): \(slot.startTime.formatted(date: .omitted, time: .shortened)) - \(slot.endTime.formatted(date: .omitted, time: .shortened))"
            }.joined(separator: "\n")
            self.bio = bio
            
            // Update FirebaseManager's currentUser
            if var currentUser = firebase.currentUser {
                currentUser.subjects = subjectObjects
                currentUser.availability = timeSlots
                currentUser.bio = bio
                firebase.currentUser = currentUser
            }
        } catch {
            print("Error updating user profile: \(error.localizedDescription)")
        }
    }
    
    private func calculateAverageRating() -> Double {
        guard !reviews.isEmpty else { return 0 }
        let total = reviews.reduce(0) { $0 + $1.rating }
        return Double(total) / Double(reviews.count)
    }
    
    func submitReview(sessionId: String, rating: Int, comment: String) {
        guard let userId = firebase.auth.currentUser?.uid else { return }
        
        let reviewData: [String: Any] = [
            "sessionId": sessionId,
            "tutorId": userId,
            "rating": rating,
            "comment": comment,
            "date": Timestamp(date: Date()),
            "studentId": userId
        ]
        
        firebase.firestore.collection("reviews").addDocument(data: reviewData) { [weak self] error in
            if error == nil {
                // Refresh reviews after submitting
                self?.fetchReviews(for: userId)
            }
        }
    }
    
    var reviewsWithNames: [ReviewWithName] {
        reviews.map { review in
            ReviewWithName(
                review: review,
                studentName: studentNames[review.studentId] ?? "Anonymous Student"
            )
        }
    }
}

let availableSubjects = [
    "Math": ["Algebra I", "Algebra II", "Geometry", "Pre-Calculus", "AP Calculus AB", "AP Calculus BC"],
    "Science": ["Biology", "Chemistry", "Physics", "AP Biology", "AP Chemistry", "AP Physics"],
    "English": ["English 9", "English 10", "English 11", "AP Literature", "AP Language"],
    "History": ["World History", "US History", "AP World History", "AP US History"],
    "Languages": ["Spanish I", "Spanish II", "French I", "French II", "Mandarin I"],
    "Computer Science": ["Intro to Programming", "AP Computer Science A", "AP Computer Science Principles"]
]

struct Review: Identifiable {
    let id: String
    let rating: Int
    let comment: String
    let date: Date
    let studentId: String
}

struct ReviewWithName: Identifiable {
    var id: String { review.id }
    let review: Review
    let studentName: String
}

struct ReviewRow: View {
    let review: ReviewWithName
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= review.review.rating ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
                Spacer()
                Text("by \(review.studentName)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Text(review.review.comment)
                .font(.subheadline)
            Text(review.review.date, style: .date)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

struct DayAvailability: Identifiable {
    let id = UUID()
    var dayOfWeek: Int
    var startTime: Date
    var endTime: Date
    
    var dayName: String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayOfWeek - 1]
    }
}

struct TutorProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    @State private var subjects: [String] = []
    @State private var availability: [DayAvailability] = []
    @State private var bio: String = ""
    @State private var showingSubjectPicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Subjects")) {
                    ForEach(subjects, id: \.self) { subject in
                        Text(subject)
                    }
                    Button("Add Subject") {
                        showingSubjectPicker = true
                    }
                }
                
                Section(header: Text("Availability")) {
                    ForEach($availability) { $day in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(day.dayName)
                                    .font(.headline)
                                
                                Spacer()
                                
                                Button(role: .destructive) {
                                    availability.removeAll { $0.id == day.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                            
                            DatePicker("Start Time", selection: $day.startTime, displayedComponents: .hourAndMinute)
                            
                            DatePicker("End Time", selection: $day.endTime, displayedComponents: .hourAndMinute)
                                .onChange(of: day.endTime) { newValue in
                                    if newValue < day.startTime {
                                        day.endTime = day.startTime.addingTimeInterval(3600) // Add 1 hour
                                    }
                                }
                        }
                        .padding(.vertical, 5)
                    }
                    
                    if availability.count < 7 {
                        Button("Add Day") {
                            let usedDays = Set(availability.map { $0.dayOfWeek })
                            let availableDays = Set(1...7).subtracting(usedDays)
                            if let newDay = availableDays.min() {
                                let startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
                                let endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
                                
                                availability.append(DayAvailability(
                                    dayOfWeek: newDay,
                                    startTime: startTime,
                                    endTime: endTime
                                ))
                                // Sort availability by day of week
                                availability.sort { $0.dayOfWeek < $1.dayOfWeek }
                            }
                        }
                    }
                }
                
                Section(header: Text("Bio")) {
                    TextEditor(text: $bio)
                        .frame(height: 150)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") {
                    // Validate time slots
                    let validTimeSlots = availability.map { day in
                        TimeSlot(
                            dayOfWeek: day.dayOfWeek,
                            startTime: day.startTime,
                            endTime: day.endTime
                        )
                    }
                    
                    viewModel.updateTutorProfile(
                        subjects: subjects,
                        timeSlots: validTimeSlots,
                        bio: bio
                    )
                    dismiss()
                }
            )
            .sheet(isPresented: $showingSubjectPicker) {
                SubjectPickerView(selectedSubjects: $subjects, availableSubjects: availableSubjects)
            }
            .onAppear {
                // Load existing data
                subjects = viewModel.subjects
                bio = viewModel.bio
                
                // Convert existing availability string to DayAvailability array
                if !viewModel.availability.isEmpty {
                    let lines = viewModel.availability.split(separator: "\n")
                    availability = lines.compactMap { line -> DayAvailability? in
                        let parts = line.split(separator: ":")
                        guard let dayOfWeek = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
                        
                        // Default times if can't parse
                        let startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
                        let endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
                        
                        return DayAvailability(
                            dayOfWeek: dayOfWeek,
                            startTime: startTime,
                            endTime: endTime
                        )
                    }
                    // Sort availability by day of week
                    availability.sort { $0.dayOfWeek < $1.dayOfWeek }
                }
            }
        }
    }
}

struct SubjectPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSubjects: [String]
    let availableSubjects: [String: [String]]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(availableSubjects.keys.sorted()), id: \.self) { subject in
                    Section(header: Text(subject)) {
                        ForEach(availableSubjects[subject]!, id: \.self) { className in
                            Toggle(isOn: Binding(
                                get: { selectedSubjects.contains(className) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedSubjects.append(className)
                                    } else {
                                        selectedSubjects.removeAll { $0 == className }
                                    }
                                }
                            )) {
                                Text(className)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Subjects")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
