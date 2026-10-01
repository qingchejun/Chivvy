import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    let timeString: String
    let caption: String
    let timerState: TimerState
    let completionCount: Int

    @State private var isPulse = false
    @State private var completionFlash = false

    private var ringColor: Color {
        if completionFlash { return Theme.success }
        switch timerState {
        case .running, .paused: return Theme.brand
        case .idle: return Theme.brand.opacity(0.35)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.fillStrong, lineWidth: 9)

            Circle()
                .trim(from: 0, to: completionFlash ? 1.0 : progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
                .opacity(timerState == .paused ? (isPulse ? 0.35 : 1.0) : 1.0)

            VStack(spacing: Theme.Space.xs) {
                Text(timeString)
                    .font(Theme.Font.display)
                    .tracking(-1)
                    .opacity(timerState == .paused ? (isPulse ? 0.4 : 1.0) : 1.0)
                    .scaleEffect(completionFlash ? 1.06 : 1.0)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            }
        }
        .frame(width: 196, height: 196)
        .onAppear {
            if timerState == .paused { startPulse() }
        }
        .onChange(of: timerState) { newState in
            if newState == .paused {
                startPulse()
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

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPulse = true
        }
    }
}
