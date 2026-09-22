import Foundation

enum ChatRole: Equatable {
    case technician
    case assistant
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let text: String
    let details: String?
    let date: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        details: String? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.details = details
        self.date = date
    }
}
