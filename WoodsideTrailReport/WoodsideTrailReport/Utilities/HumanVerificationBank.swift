import Foundation

struct VerificationQuestion: Identifiable {
    let id = UUID()
    let question: String
    let acceptedAnswers: [String]

    func isCorrect(_ input: String) -> Bool {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return acceptedAnswers.map { $0.lowercased() }.contains(trimmed)
    }
}

enum HumanVerificationBank {
    static let questions: [VerificationQuestion] = [
        .init(question: "What color is the sky on a clear day?",
              acceptedAnswers: ["blue", "light blue", "sky blue"]),
        .init(question: "How many legs does a dog have?",
              acceptedAnswers: ["4", "four"]),
        .init(question: "What do you call frozen water?",
              acceptedAnswers: ["ice"]),
        .init(question: "What is 2 + 2?",
              acceptedAnswers: ["4", "four"]),
        .init(question: "What season comes after summer?",
              acceptedAnswers: ["fall", "autumn"]),
        .init(question: "How many days are in a week?",
              acceptedAnswers: ["7", "seven"]),
        .init(question: "What color is grass?",
              acceptedAnswers: ["green"]),
        .init(question: "What planet do we live on?",
              acceptedAnswers: ["earth", "the earth"]),
        .init(question: "How many hours are in a day?",
              acceptedAnswers: ["24", "twenty-four", "twenty four"]),
        .init(question: "What do bees make?",
              acceptedAnswers: ["honey"]),
        .init(question: "How many sides does a triangle have?",
              acceptedAnswers: ["3", "three"]),
        .init(question: "What is the opposite of cold?",
              acceptedAnswers: ["hot", "warm"]),
        .init(question: "How many months are in a year?",
              acceptedAnswers: ["12", "twelve"]),
        .init(question: "What animal says meow?",
              acceptedAnswers: ["cat", "a cat", "kitten"]),
        .init(question: "What color is a stop sign?",
              acceptedAnswers: ["red"]),
    ]

    static func random() -> VerificationQuestion {
        questions.randomElement()!
    }
}
