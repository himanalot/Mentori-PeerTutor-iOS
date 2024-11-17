import Foundation
import SwiftUI

struct Course: Identifiable, Hashable, Codable {
    var id: UUID
    let name: String
    let category: CourseCategory
    
    init(id: UUID = UUID(), name: String, category: CourseCategory) {
        self.id = id
        self.name = name
        self.category = category
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: Course, rhs: Course) -> Bool {
        lhs.name == rhs.name
    }
}

enum CourseCategory: String, CaseIterable, Codable {
    case english = "English"
    case mathematics = "Mathematics"
    case history = "History"
    case science = "Science"
    case languages = "Languages"
    case computerScience = "Computer Science"
    case arts = "Arts"
    case other = "Other"
}

struct Courses {
    static let allCourses: [Course] = [
        // English
        Course(name: "Intro to Literary Genres", category: .english),
        Course(name: "American Literature", category: .english),
        Course(name: "British Literature", category: .english),
        Course(name: "AP English Language", category: .english),
        Course(name: "AP English Literature", category: .english),
        Course(name: "Creative Writing", category: .english),
        Course(name: "Literature Seminars", category: .english),
        Course(name: "Fiction of James Joyce", category: .english),
        Course(name: "Literature of Civil Rights", category: .english),
        
        // Mathematics
        Course(name: "Algebra I", category: .mathematics),
        Course(name: "Geometry", category: .mathematics),
        Course(name: "Advanced Geometry", category: .mathematics),
        Course(name: "Algebra II", category: .mathematics),
        Course(name: "Advanced Algebra II", category: .mathematics),
        Course(name: "Intermediate Algebra/Trigonometry", category: .mathematics),
        Course(name: "Precalculus", category: .mathematics),
        Course(name: "AP Calculus AB", category: .mathematics),
        Course(name: "AP Calculus BC", category: .mathematics),
        Course(name: "Multivariable Calculus", category: .mathematics),
        Course(name: "Statistics/Probability", category: .mathematics),
        Course(name: "AP Statistics", category: .mathematics),
        Course(name: "Differential Equations", category: .mathematics),
        Course(name: "Linear Algebra", category: .mathematics),
        Course(name: "Advanced Applied Math Through Finance", category: .mathematics),
        
        // History
        Course(name: "World History", category: .history),
        Course(name: "U.S. History", category: .history),
        Course(name: "AP U.S. History", category: .history),
        Course(name: "Economics", category: .history),
        Course(name: "AP Microeconomics", category: .history),
        Course(name: "AP Macroeconomics", category: .history),
        Course(name: "U.S. Government", category: .history),
        Course(name: "AP Art History", category: .history),
        Course(name: "AP European History", category: .history),
        Course(name: "AP World History", category: .history),
        
        // Science
        Course(name: "Foundational Chemistry", category: .science),
        Course(name: "Chemistry", category: .science),
        Course(name: "Advanced Chemistry", category: .science),
        Course(name: "Biology", category: .science),
        Course(name: "Advanced Biology", category: .science),
        Course(name: "AP Biology", category: .science),
        Course(name: "DNA Science", category: .science),
        Course(name: "Neurological Science", category: .science),
        Course(name: "Horticulture", category: .science),
        Course(name: "AP Chemistry", category: .science),
        Course(name: "Pharmacology", category: .science),
        Course(name: "Biochemistry", category: .science),
        Course(name: "Organic Chemistry", category: .science),
        Course(name: "AP Psychology", category: .science),
        Course(name: "AP Environmental Science", category: .science),
        Course(name: "AP Physics C: Mechanics", category: .science),
        Course(name: "AP Physics C: Electricity & Magnetism", category: .science),
        Course(name: "Physics", category: .science),
        Course(name: "Astronomy", category: .science),
        Course(name: "Meteorology", category: .science),
        Course(name: "Cancer Studies", category: .science),
        Course(name: "Environmental Bioethics", category: .science),
        
        // Languages
        Course(name: "Spanish I", category: .languages),
        Course(name: "Spanish II", category: .languages),
        Course(name: "Spanish III", category: .languages),
        Course(name: "Spanish IV", category: .languages),
        Course(name: "AP Spanish Language", category: .languages),
        Course(name: "French I", category: .languages),
        Course(name: "French II", category: .languages),
        Course(name: "French III", category: .languages),
        Course(name: "French IV", category: .languages),
        Course(name: "AP French Language", category: .languages),
        Course(name: "Latin I", category: .languages),
        Course(name: "Latin II", category: .languages),
        Course(name: "Latin III", category: .languages),
        Course(name: "AP Latin", category: .languages),
        Course(name: "American Sign Language", category: .languages),
        Course(name: "Ancient Greek", category: .languages),
        Course(name: "Arabic I", category: .languages),
        Course(name: "Arabic II", category: .languages),
        
        // Computer Science
        Course(name: "Beginning Computer Science", category: .computerScience),
        Course(name: "Introduction to Web Design", category: .computerScience),
        Course(name: "AP Computer Science Principles", category: .computerScience),
        Course(name: "AP Computer Science A", category: .computerScience),
        Course(name: "Cybersecurity", category: .computerScience),
        
        // Arts
        Course(name: "Advanced Acting Ensemble", category: .arts),
        Course(name: "AP Studio Art", category: .arts),
        Course(name: "AP Music Theory", category: .arts),
        
        // Other
        Course(name: "Critical Thinking", category: .other),
        Course(name: "Ethics", category: .other),
        Course(name: "Philosophy", category: .other)
    ]
    
    static func filteredCourses(searchText: String) -> [Course] {
        if searchText.isEmpty {
            return allCourses
        }
        return allCourses.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }
} 