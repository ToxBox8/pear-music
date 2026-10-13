import Foundation
import SwiftUI

/// Temporizador para dormir: para la música a los N minutos (bajando el volumen los últimos segundos) o al acabar
/// la canción. Mismas opciones y textos que `SleepTimer` en Android.
@MainActor
final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()

    enum State: Equatable {
        case off
        /// `endsAt` en tiempo del sistema que no cambia con la hora del móvil (`ProcessInfo.systemUptime`).
        case at(endsAt: TimeInterval, minutes: Int)
        case endOfSong
    }

    /// Minutos que se ofrecen en el menú.
    static let presets = [5, 15, 30, 45, 60, 90]
    /// Segundos finales en los que el volumen baja hasta 0.
    static let fadeSeconds: Double = 12

    @Published private(set) var state: State = .off
    weak var player: Player?
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private var timer: Timer?

    func start(minutes: Int) {
        reset()
        state = .at(endsAt: now() + Double(minutes) * 60, minutes: minutes)
        schedule(1)
    }

    func endOfSong() {
        reset()
        state = .endOfSong
    }

    func cancel() {
        reset()
        state = .off
    }

    /// Lo llama `Player` al acabar una canción: true si el temporizador la para ahí.
    func stopsAtEndOfSong() -> Bool {
        guard state == .endOfSong else { return false }
        state = .off
        return true
    }

    /// Segundos que quedan, o nil si no hay cuenta atrás.
    func remaining(_ s: State? = nil) -> TimeInterval? {
        if case let .at(endsAt, _) = s ?? state { return max(0, endsAt - now()) }
        return nil
    }

    /// Volumen para los segundos que quedan: 1 hasta los últimos `fadeSeconds` y luego baja hasta 0.
    static func volume(for remaining: TimeInterval) -> Float { Float(min(1, max(0, remaining / fadeSeconds))) }

    /// «Se para en 12 min», «Se para en 45 s», «Se para al acabar la canción».
    func label(_ s: State? = nil) -> String? {
        switch s ?? state {
        case .off: return nil
        case .endOfSong: return "Se para al acabar la canción"
        case .at:
            let secs = Int((remaining(s) ?? 0).rounded(.up))
            return secs >= 60 ? "Se para en \((secs + 59) / 60) min" : "Se para en \(secs) s"
        }
    }

    var minutes: Int? { if case let .at(_, m) = state { return m }; return nil }

    private func reset() {
        timer?.invalidate()
        timer = nil
        player?.setVolume(1)
    }

    private func schedule(_ interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard case let .at(endsAt, m) = state else { return }
        let left = max(0, endsAt - now())
        if left <= 0 {
            player?.pause()
            player?.setVolume(1)
            state = .off
            return
        }
        player?.setVolume(SleepTimer.volume(for: left))
        state = .at(endsAt: endsAt, minutes: m) // se reemite para que la etiqueta avance
        schedule(left <= SleepTimer.fadeSeconds ? 0.2 : 1)
    }
}

/// Luna del temporizador: en acento mientras cuenta; el menú elige minutos, «al acabar la canción» o apagarlo.
struct SleepTimerButton: View {
    @ObservedObject private var timer = SleepTimer.shared

    var body: some View {
        Menu {
            if let l = timer.label() { Text(l) }
            ForEach(SleepTimer.presets, id: \.self) { m in
                Button { timer.start(minutes: m) } label: {
                    if timer.minutes == m { Label("\(m) minutos", systemImage: "checkmark") } else { Text("\(m) minutos") }
                }
            }
            Button { timer.endOfSong() } label: {
                Label("Al acabar la canción", systemImage: timer.state == .endOfSong ? "checkmark" : "music.note")
            }
            if timer.state != .off {
                Divider()
                Button(role: .destructive) { timer.cancel() } label: { Label("Desactivar temporizador", systemImage: "xmark") }
            }
        } label: {
            Image(systemName: timer.state == .off ? "moon.zzz" : "moon.zzz.fill")
                .font(.title3)
                .foregroundStyle(timer.state == .off ? Color.primary : Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(timer.label().map { "Temporizador: \($0)" } ?? "Temporizador para dormir")
    }
}

/// «Se para en 12 min» debajo del artista mientras el temporizador cuenta.
struct SleepTimerLabel: View {
    @ObservedObject private var timer = SleepTimer.shared

    var body: some View {
        if let l = timer.label() {
            Label(l, systemImage: "moon.zzz.fill")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
        }
    }
}
