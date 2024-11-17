import SwiftUI
import FirebaseFirestore

struct CourseSelectionView: View {
    @Binding var selectedCourses: Set<Course>
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: CourseCategory?
    
    private var filteredCourses: [Course] {
        let courses = Courses.filteredCourses(searchText: searchText)
        if let category = selectedCategory {
            return courses.filter { $0.category == category }
        }
        return courses
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                SearchBar(text: $searchText)
                    .padding()
                
                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(CourseCategory.allCases, id: \.self) { category in
                            CategoryChip(
                                category: category,
                                isSelected: selectedCategory == category,
                                action: {
                                    if selectedCategory == category {
                                        selectedCategory = nil
                                    } else {
                                        selectedCategory = category
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                List {
                    ForEach(filteredCourses) { course in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(course.name)
                                Text(course.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if selectedCourses.contains(course) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedCourses.contains(course) {
                                selectedCourses.remove(course)
                            } else {
                                selectedCourses.insert(course)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Courses")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search courses...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct CategoryChip: View {
    let category: CourseCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(category.rawValue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

#Preview {
    CourseSelectionView(selectedCourses: .constant(Set<Course>()))
} 