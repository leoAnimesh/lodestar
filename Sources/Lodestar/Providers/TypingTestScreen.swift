import SwiftUI
import LodestarCore

/// A screen that draws its own content instead of a list; the search field
/// stays as its input.
protocol CustomViewScreen: ListScreen {
    func contentView(query: String) -> AnyView
}

/// Typing practice: the search field is the input, the text to copy is drawn
/// below with typed characters colored. Return restarts with new words.
final class TypingTestScreen: CustomViewScreen {
    let title = "Typing Test"
    let placeholder = "Start typing…"
    weak var host: ScreenHost?
    let presentation = ScreenPresentation.custom

    private let test = TypingTest(TypingTest.randomText())
    private var startedAt: Date?
    private var finishedAt: Date?

    func search(_ query: String) -> [LauncherItem] {
        if query.isEmpty { startedAt = nil; finishedAt = nil }
        else if startedAt == nil { startedAt = Date() }
        if test.isDone(typed: query) { finishedAt = finishedAt ?? Date() } else { finishedAt = nil }
        // Not drawn; gives Return (and the footer) a Restart action.
        return [LauncherItem(id: "typing:restart", title: "Restart", icon: .symbol("arrow.clockwise"),
                             actions: [LauncherAction("New Test", symbol: "arrow.clockwise") { .replace(TypingTestScreen()) }],
                             tracksUsage: false)]
    }

    func contentView(query: String) -> AnyView {
        let elapsed = startedAt.map { (finishedAt ?? Date()).timeIntervalSince($0) } ?? 0
        let typedCount = min(query.count, test.target.count)
        let wpm = test.wpm(typed: query, elapsed: elapsed)
        let accuracy = test.accuracy(typed: query)
        let progress = Double(typedCount) / Double(max(test.target.count, 1))
        return AnyView(ZStack(alignment: .top) {
            if finishedAt != nil {
                results(query: query, wpm: wpm, accuracy: accuracy, seconds: Int(elapsed))
            } else {
                typing(query: query, typedCount: typedCount, wpm: wpm, accuracy: accuracy, seconds: Int(elapsed))
            }
            // Progress as a hairline along the top edge.
            GeometryReader { geo in
                Capsule().fill(Color.accentColor).frame(width: geo.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .animation(.easeOut(duration: 0.15), value: progress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    private func typing(query: String, typedCount: Int, wpm: Int, accuracy: Int, seconds: Int) -> some View {
        var text = AttributedString()
        for (i, (ch, state)) in zip(test.target, test.states(typed: query)).enumerated() {
            // Wrong spaces would be invisible; show them as a dot.
            var piece = AttributedString(state == .wrong && ch == " " ? "·" : String(ch))
            piece.foregroundColor = state == .correct ? .primary : state == .wrong ? .red : .secondary.opacity(0.55)
            if state == .wrong { piece.backgroundColor = .red.opacity(0.15) }
            if i == typedCount { piece.backgroundColor = .accentColor.opacity(0.35) } // caret
            text += piece
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 22) {
                Spacer()
                if query.isEmpty {
                    Text("The timer starts with your first key").foregroundStyle(.secondary)
                } else {
                    liveStat(wpm, "wpm")
                    liveStat(accuracy, "% accuracy")
                    liveStat(seconds, "s")
                }
            }
            .font(.system(size: 13))
            .frame(height: 26)
            .padding(.top, 20).padding(.trailing, 24)
            Text(text)
                .font(.system(size: 25, weight: .regular, design: .monospaced))
                .lineSpacing(12)
                .accessibilityLabel(String(test.target))
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 26)
        }
    }

    private func liveStat(_ value: Int, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(value)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func results(query: String, wpm: Int, accuracy: Int, seconds: Int) -> some View {
        let states = test.states(typed: query)
        let mistakes = states.filter { $0 == .wrong }.count
        return VStack(spacing: 0) {
            Spacer()
            Text("\(wpm)").font(.system(size: 80, weight: .bold, design: .rounded)).monospacedDigit()
            Text("words per minute").font(.system(size: 14)).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                resultStat("\(accuracy)%", "Accuracy")
                Divider().frame(height: 30)
                resultStat("\(seconds)s", "Time")
                Divider().frame(height: 30)
                resultStat("\(mistakes)", mistakes == 1 ? "Mistake" : "Mistakes")
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .padding(.top, 22)
            // Show where the mistakes were; nothing to show on a clean run.
            if mistakes > 0 {
                recap(states).padding(.top, 20)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func resultStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    /// The text again, small and dim, with the wrong characters marked.
    private func recap(_ states: [TypingTest.CharState]) -> some View {
        var text = AttributedString()
        for (ch, state) in zip(test.target, states) {
            var piece = AttributedString(state == .wrong && ch == " " ? "·" : String(ch))
            piece.foregroundColor = state == .wrong ? .red : .secondary.opacity(0.6)
            if state == .wrong { piece.backgroundColor = .red.opacity(0.15) }
            text += piece
        }
        return Text(text).font(.system(size: 13, design: .monospaced)).lineSpacing(4)
            .frame(maxWidth: 520, alignment: .leading)
            .accessibilityLabel("Mistakes marked in the text")
    }
}
