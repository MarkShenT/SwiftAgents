import Foundation

public enum AgentRole: Sendable {
    case security, performance, style, synthesizer

    var label: String {
        switch self {
        case .security:    return "[Security]"
        case .performance: return "[Performance]"
        case .style:       return "[Style]"
        case .synthesizer: return "[Summary]"
        }
    }

    var emoji: String {
        switch self {
        case .security:    return "🔴"
        case .performance: return "🟡"
        case .style:       return "🔵"
        case .synthesizer: return "🟢"
        }
    }

    var color: String {
        switch self {
        case .security:    return StreamRenderer.ANSICode.red
        case .performance: return StreamRenderer.ANSICode.yellow
        case .style:       return StreamRenderer.ANSICode.blue
        case .synthesizer: return StreamRenderer.ANSICode.green
        }
    }
}

public enum StreamRenderer {
    public enum ANSICode {
        public static let red    = "\u{001B}[31m"
        public static let yellow = "\u{001B}[33m"
        public static let blue   = "\u{001B}[34m"
        public static let green  = "\u{001B}[32m"
        public static let reset  = "\u{001B}[0m"
        public static let bold   = "\u{001B}[1m"
    }

    public static func format(_ text: String, agent: AgentRole) -> String {
        "\(agent.color)\(ANSICode.bold)\(agent.label)\(ANSICode.reset) \(agent.emoji)  \(text)"
    }

    public static func printToken(_ text: String, agent: AgentRole) {
        let formatted = "\(agent.color)\(text)\(ANSICode.reset)"
        print(formatted, terminator: "")
        fflush(stdout)
    }

    public static func printLine(_ text: String, agent: AgentRole) {
        print("\(agent.color)\(ANSICode.bold)\(agent.label)\(ANSICode.reset) \(agent.emoji)  \(text)")
    }

    public static func printDivider(_ title: String) {
        print("\n\(ANSICode.bold)── \(title) ──\(ANSICode.reset)\n")
    }
}
