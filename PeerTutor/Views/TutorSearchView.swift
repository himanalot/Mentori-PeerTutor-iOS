import SwiftUI
import FirebaseFirestore

// Assuming User, FirebaseManager, TutoringRequest, TutoringSession, ChatView, and other dependencies are defined elsewhere

class TutorSearchViewModel: ObservableObject {
    @Published var tutors: [User] = []
    private let firebase = FirebaseManager.shared
    
    init() {
        listenForTutors()
    }
    
    private func listenForTutors() {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        firebase.firestore.collection("users")
            .whereField("id", isNotEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching tutors: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                self?.tutors = documents.compactMap { document in
                    try? document.data(as: User.self)
                }
            }
    }
    
    @MainActor
    func refreshTutors() async {
        guard let currentUserId = firebase.auth.currentUser?.uid else { return }
        
        let snapshot = try? await firebase.firestore.collection("users")
            .whereField("id", isNotEqualTo: currentUserId)
            .getDocuments()
        
        if let documents = snapshot?.documents {
            self.tutors = documents.compactMap { document in
                try? document.data(as: User.self)
            }
        }
    }
}

class TutorCalendarViewModel: ObservableObject {
    @Published var bookedSessions: [TutoringSession] = []
    private let firebase = FirebaseManager.shared
    
    func loadBookedSessions(for tutorId: String) {
        firebase.firestore.collection("sessions")
            .whereField("tutorId", isEqualTo: tutorId)
            .whereField("status", isEqualTo: TutoringSession.SessionStatus.scheduled.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.bookedSessions = documents.compactMap { document in
                    try? document.data(as: TutoringSession.self)
                }
            }
    }
}

struct TutorSearchView: View {
    @StateObject private var viewModel = TutorSearchViewModel()
    @State private var searchText = ""
    
    var filteredTutors: [User] {
        if searchText.isEmpty {
            return viewModel.tutors
        }
        return viewModel.tutors.filter { tutor in
            tutor.name.localizedCaseInsensitiveContains(searchText) ||
            tutor.subjects.map { $0.name }.joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredTutors) { tutor in
                    if let tutorId = tutor.id {
                        NavigationLink(destination: TutorDetailView(tutorId: tutorId)) {
                            TutorRowView(tutor: tutor)
                        }
                    }
                }
            }
            .navigationTitle("Find a Tutor")
            .searchable(text: $searchText, prompt: "Search by subject or name")
            .refreshable {
                await viewModel.refreshTutors()
            }
        }
    }
}

struct TutorDetailView: View {
    let tutorId: String
    @State private var tutor: User?
    @State private var showingMessageSheet = false
    @State private var showingScheduleSheet = false
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    private let firebase = FirebaseManager.shared
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let tutor = tutor {
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Header
                        VStack(spacing: 16) {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Text(tutor.name.prefix(1).uppercased())
                                        .font(.title.bold())
                                        .foregroundColor(.gray)
                                )
                            
                            VStack(spacing: 8) {
                                Text(tutor.name)
                                    .font(.title2.bold())
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", tutor.displayRating))
                                    Text("(\(tutor.displayReviews) reviews)")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(.top)
                        
                        // Bio Section
                        if !tutor.bio.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("About", systemImage: "person.text.rectangle.fill")
                                    .font(.headline)
                                Text(tutor.bio)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.05), radius: 8)
                        }
                        
                        // Subjects Grid
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Subjects", systemImage: "book.fill")
                                .font(.headline)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(tutor.subjects, id: \.name) { subject in
                                    Text(subject.name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 8)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button(action: {
                                showingMessageSheet = true
                            }) {
                                Label("Message", systemImage: "message")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .sheet(isPresented: $showingMessageSheet) {
                                NavigationView {
                                    ChatView(
                                        conversation: [],
                                        tutorName: tutor.name,
                                        tutorId: tutorId
                                    )
                                }
                            }
                            
                            Button(action: { showingScheduleSheet = true }) {
                                HStack {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Schedule Session")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .sheet(isPresented: $showingScheduleSheet) {
                                ScheduleSessionView(tutor: tutor)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                }
            } else {
                Text("Could not load tutor profile")
            }
        }
        .onAppear {
            loadTutor()
        }
    }
    
    private func loadTutor() {
        isLoading = true
        firebase.firestore.collection("users").document(tutorId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading tutor: \(error.localizedDescription)")
                    self.isLoading = false
                    return
                }
                
                if let snapshot = snapshot {
                    do {
                        self.tutor = try snapshot.data(as: User.self)
                    } catch {
                        print("Error decoding tutor: \(error.localizedDescription)")
                    }
                }
                self.isLoading = false
            }
        }
    }
}

struct TutorRowView: View {
    let tutor: User
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(tutor.name.prefix(1).uppercased())
                        .font(.title3.bold())
                        .foregroundColor(.gray)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tutor.name)
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", tutor.displayRating))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text(tutor.subjects.prefix(2).map { $0.name }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if tutor.subjects.count > 2 {
                        Text(" +\(tutor.subjects.count - 2) more")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ScheduleSessionView: View {
    @Environment(\.dismiss) private var dismiss
    let tutor: User
    @State private var selectedDate = Date()
    @State private var selectedStartTime = Date()
    @State private var selectedEndTime = Date()
    @State private var selectedSubject = ""
    @State private var note = ""
    @State private var showingConfirmation = false
    @State private var isRequest = false
    @State private var isOutsideAvailability = false
    @State private var isNewSubject = false
    @State private var isCustomSubject = false
    @State private var customSubject = ""
    @State private var showingOverlapAlert = false
    @State private var showingCalendarView = false
    
    private let firebase = FirebaseManager.shared
    
    private var isValidTimeRange: Bool {
        // Check if selected time is in the past
        let calendar = Calendar.current
        let sessionDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: selectedStartTime),
                                         minute: calendar.component(.minute, from: selectedStartTime),
                                         second: 0,
                                         of: selectedDate) ?? selectedDate
        
        return selectedEndTime > selectedStartTime && sessionDateTime > Date()
    }
    
    private var availableTimeSlot: TimeSlot? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        
        return tutor.availability.first { slot in
            slot.dayOfWeek == weekday
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tutor's Availability")) {
                    AvailabilityView(availability: tutor.availability.map { TimeSlot(
                        dayOfWeek: $0.dayOfWeek,
                        startTime: $0.startTime,
                        endTime: $0.endTime
                    )}, isCompact: true)
                    
                    Text("Times outside these hours will be sent as requests for approval")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    Button(action: { showingCalendarView = true }) {
                        Label("View Tutor's Calendar", systemImage: "calendar")
                    }
                    .sheet(isPresented: $showingCalendarView) {
                        TutorCalendarView(tutor: tutor)
                    }
                }
                
                Section(header: Text("Session Details")) {
                    Toggle("Request Different Subject", isOn: $isCustomSubject)
                    
                    if isCustomSubject {
                        TextField("Enter Subject", text: $customSubject)
                    } else {
                        Picker("Subject", selection: $selectedSubject) {
                            ForEach(tutor.subjects, id: \.name) { subject in
                                Text(subject.name).tag(subject.name)
                            }
                        }
                    }
                    
                    DatePicker("Date",
                             selection: $selectedDate,
                             in: Date()...,
                             displayedComponents: .date)
                    
                    DatePicker("Start Time",
                             selection: $selectedStartTime,
                             displayedComponents: .hourAndMinute)
                    
                    DatePicker("End Time",
                             selection: $selectedEndTime,
                             displayedComponents: .hourAndMinute)
                    
                    if !isValidTimeRange {
                        if selectedEndTime < selectedStartTime {
                            Text("End time must be after start time")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section(header: Text("Additional Notes")) {
                    TextEditor(text: $note)
                        .frame(height: 100)
                }
                
                Section {
                    Button(isOutsideAvailability || isCustomSubject ? "Send Request" : "Schedule Session") {
                        scheduleSession()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!isValidTimeRange && !isCustomSubject)
                }
            }
            .navigationTitle("Schedule Session")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .alert("Success", isPresented: $showingConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                if isRequest {
                    Text("Your tutoring request has been sent to the tutor.")
                } else {
                    Text("Your tutoring session has been scheduled successfully.")
                }
            }
            .alert("Time Conflict", isPresented: $showingOverlapAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The tutor is already booked for this time slot. Please select a different time.")
            }
            .onAppear {
                // Set initial times
                let calendar = Calendar.current
                if let slot = availableTimeSlot {
                    selectedStartTime = slot.startTime
                    selectedEndTime = slot.startTime.addingTimeInterval(3600)
                } else {
                    // Default to 9 AM - 10 AM if no availability
                    selectedStartTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                    selectedEndTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                }
                
                // Set initial subject
                if let firstSubject = tutor.subjects.first {
                    selectedSubject = firstSubject.name
                }
            }
            .onChange(of: selectedDate) { _ in
                checkAvailability()
            }
            .onChange(of: selectedStartTime) { _ in
                checkAvailability()
            }
            .onChange(of: selectedEndTime) { _ in
                checkAvailability()
            }
            .onChange(of: isCustomSubject) { newValue in
                isNewSubject = newValue
            }
        }
    }
    
    private func calculateDuration() -> Int {
        let calendar = Calendar.current
        
        // Combine selected date with selected times
        let startDate = calendar.date(bySettingHour: calendar.component(.hour, from: selectedStartTime),
                                      minute: calendar.component(.minute, from: selectedStartTime),
                                      second: 0,
                                      of: selectedDate) ?? selectedDate
        
        let endDate = calendar.date(bySettingHour: calendar.component(.hour, from: selectedEndTime),
                                    minute: calendar.component(.minute, from: selectedEndTime),
                                    second: 0,
                                    of: selectedDate) ?? selectedDate
        
        let duration = calendar.dateComponents([.minute], from: startDate, to: endDate).minute ?? 0
        return duration > 0 ? duration : duration + (24 * 60) // Handle overnight sessions
    }
    
    private func scheduleSession() {
        guard let currentUserId = firebase.auth.currentUser?.uid,
              let tutorId = tutor.id else { return }
        
        let calendar = Calendar.current
        let sessionDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: selectedStartTime),
                                           minute: calendar.component(.minute, from: selectedStartTime),
                                           second: 0,
                                           of: selectedDate) ?? selectedDate
        
        let sessionEndDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: selectedEndTime),
                                             minute: calendar.component(.minute, from: selectedEndTime),
                                             second: 0,
                                             of: selectedDate) ?? selectedDate
        
        // Check for overlapping sessions
        firebase.firestore.collection("sessions")
            .whereField("tutorId", isEqualTo: tutorId)
            .whereField("status", isEqualTo: TutoringSession.SessionStatus.scheduled.rawValue)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking for overlapping sessions: \(error.localizedDescription)")
                    return
                }
                
                if let documents = snapshot?.documents {
                    for document in documents {
                        if let session = try? document.data(as: TutoringSession.self) {
                            let sessionEnd = session.dateTime.addingTimeInterval(TimeInterval(session.duration * 60))
                            
                            // Check if new session overlaps with existing session
                            if (sessionDateTime < sessionEnd && sessionEndDateTime > session.dateTime) {
                                self.showingOverlapAlert = true
                                return
                            }
                        }
                    }
                }
                
                // No overlap found, proceed with original scheduling logic
                self.proceedWithScheduling(tutorId: tutorId, currentUserId: currentUserId, sessionDateTime: sessionDateTime)
            }
    }
    
    private func proceedWithScheduling(tutorId: String, currentUserId: String, sessionDateTime: Date) {
        // Get the actual subject (either custom or selected)
        let actualSubject = isCustomSubject ? customSubject : selectedSubject
        
        if isOutsideAvailability || isNewSubject {
            // Create a request
            let request = TutoringRequest(
                tutorId: tutorId,
                studentId: currentUserId,
                subject: actualSubject,
                dateTime: sessionDateTime,
                duration: calculateDuration(),
                notes: note.isEmpty ? nil : note,
                status: .pending,
                isOutsideAvailability: isOutsideAvailability,
                isNewSubject: isNewSubject,
                createdAt: Date()
            )
            
            do {
                try firebase.firestore.collection("requests").addDocument(from: request)
                showingConfirmation = true
                isRequest = true
            } catch {
                print("Error creating request: \(error.localizedDescription)")
            }
        } else {
            // Create regular session
            let newSession = TutoringSession(
                tutorId: tutorId,
                studentId: currentUserId,
                subject: selectedSubject,
                dateTime: sessionDateTime,
                duration: calculateDuration(),
                status: .scheduled,
                notes: note.isEmpty ? nil : note
            )
            
            do {
                try firebase.firestore.collection("sessions").addDocument(from: newSession)
                showingConfirmation = true
            } catch {
                print("Error scheduling session: \(error.localizedDescription)")
            }
        }
    }
    
    private func checkAvailability() {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        let startComponents = calendar.dateComponents([.hour, .minute], from: selectedStartTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: selectedEndTime)
        
        // Convert selected times to minutes since midnight for easier comparison
        let selectedStartMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let selectedEndMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        
        // Check if time slot is within tutor's availability
        isOutsideAvailability = !tutor.availability.contains { slot in
            guard slot.dayOfWeek == weekday else { return false }
            
            let slotStartComponents = calendar.dateComponents([.hour, .minute], from: slot.startTime)
            let slotEndComponents = calendar.dateComponents([.hour, .minute], from: slot.endTime)
            
            let slotStartMinutes = (slotStartComponents.hour ?? 0) * 60 + (slotStartComponents.minute ?? 0)
            let slotEndMinutes = (slotEndComponents.hour ?? 0) * 60 + (slotEndComponents.minute ?? 0)
            
            return selectedStartMinutes >= slotStartMinutes && selectedEndMinutes <= slotEndMinutes
        }
    }
}

struct TutorProfileView: View {
    let tutor: User
    @State private var showingMessageSheet = false
    @State private var showingScheduleSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Profile Header
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(tutor.name.prefix(1).uppercased())
                                .font(.title.bold())
                                .foregroundColor(.gray)
                        )
                    
                    VStack(spacing: 8) {
                        Text(tutor.name)
                            .font(.title2.bold())
                        
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", tutor.displayRating))
                            Text("(\(tutor.displayReviews) reviews)")
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.top)
                
                // Bio Section
                if !tutor.bio.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("About", systemImage: "person.text.rectangle.fill")
                            .font(.headline)
                        Text(tutor.bio)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8)
                }
                
                // Add Availability View here
                if !tutor.availability.isEmpty {
                    AvailabilityView(availability: tutor.availability.map { TimeSlot(
                        dayOfWeek: $0.dayOfWeek,
                        startTime: $0.startTime,
                        endTime: $0.endTime
                    )})
                }
                
                // Subjects Grid
                VStack(alignment: .leading, spacing: 12) {
                    Label("Subjects", systemImage: "book.fill")
                        .font(.headline)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(tutor.subjects, id: \.name) { subject in
                            Text(subject.name)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 8)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        showingMessageSheet = true
                    }) {
                        Label("Message", systemImage: "message")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .sheet(isPresented: $showingMessageSheet) {
                        NavigationView {
                            ChatView(
                                conversation: [],
                                tutorName: tutor.name,
                                tutorId: tutor.id ?? ""
                            )
                        }
                    }
                    
                    Button(action: { showingScheduleSheet = true }) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text("Schedule Session")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showingScheduleSheet) {
                        ScheduleSessionView(tutor: tutor)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

struct TutorCalendarView: View {
    let tutor: User
    @StateObject private var viewModel = TutorCalendarViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Booked Sessions:")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(viewModel.bookedSessions.sorted(by: { $0.dateTime < $1.dateTime })) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session.subject)
                                .font(.headline)
                            
                            HStack {
                                Image(systemName: "clock")
                                Text(session.dateTime.formatted(date: .numeric, time: .shortened))
                                Text("•")
                                Text("\(session.duration) min")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .padding(.horizontal)
                    }
                    
                    if viewModel.bookedSessions.isEmpty {
                        ContentUnavailableView(
                            "No Booked Sessions",
                            systemImage: "calendar",
                            description: Text("The tutor has no scheduled sessions")
                        )
                        .padding(.top)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Tutor's Calendar")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
        .onAppear {
            viewModel.loadBookedSessions(for: tutor.id ?? "")
        }
    }
}

