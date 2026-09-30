import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    let timeString: String
    let timerState: TimerState
    let completionCount: Int

    @State private var isPulse = false
    @State private var completionFlash = false

    private var ringColor: Color {
        switch timerState {
        case .running:
            return .accentColor
        case .paused:
            return .orange
        case .idle:
            return completionFlash ? .green : .gray
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 12)

            Circle()
                .trim(from: 0, to: completionFlash ? 1.0 : progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
                .opacity(timerState == .paused ? (isPulse ? 0.4 : 1.0) : 1.0)

            Text(timeString)
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .opacity(timerState == .paused ? (isPulse ? 0.4 : 1.0) : 1.0)
                .scaleEffect(completionFlash ? 1.08 : 1.0)
        }
        .frame(width: 200, height: 200)
        .onChange(of: timerState) { newState in
            if newState == .paused {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulse = true
                }
            } else {
                withAnimation(.default) {
                    isPulse = false
                }
            }
        }
        .onChange(of: completionCount) { _ in
            if !completionFlash {
                withAnimation(.easeOut(duration: 0.3)) {
                    completionFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeIn(duration: 0.5)) {
                        completionFlash = false
                    }
                }
            }
        }
    }
}
