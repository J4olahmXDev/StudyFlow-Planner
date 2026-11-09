#if os(iOS) || os(watchOS)
import Foundation
import Combine
import WatchConnectivity

struct WatchPlan: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let location: String
    }

    struct Day: Codable, Equatable, Sendable {
        let date: Date
        let entries: [Entry]
    }

    let days: [Day]
    let deadlines: [Entry]
    let widget: WidgetSnapshot?
}

@MainActor
final class WatchSync: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var plan: WatchPlan?
    private var session: WCSession?
    #if os(iOS)
    private var pending: WatchPlan?
    private var delivered: WatchPlan?
    #endif

    func start() {
        guard session == nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        #if os(watchOS)
        receive(session.receivedApplicationContext)
        #else
        Task { @MainActor in self.sendPending() }
        #endif
    }

    #if os(iOS)
    func publish(_ database: Database, widget: WidgetSnapshot, today: Date = .now) {
        start()
        guard session != nil else { return }

        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: today)
        let days = (0..<3).compactMap { offset -> WatchPlan.Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: midnight) else { return nil }
            let entries = database.agenda(on: date).filter { $0.eventID != nil || $0.taskID == nil }
                .prefix(24).map {
                    WatchPlan.Entry(id: $0.id, title: String($0.title.prefix(100)), start: $0.start,
                                    end: $0.end, location: String($0.detail.prefix(100)))
                }
            return WatchPlan.Day(date: date, entries: entries)
        }
        let deadlines = database.tasks.filter { $0.status != .done }
            .sorted { $0.due < $1.due }.prefix(8).map {
                WatchPlan.Entry(id: $0.id.uuidString, title: String($0.title.prefix(100)), start: $0.due,
                                end: $0.due, location: "")
            }

        pending = WatchPlan(days: days, deadlines: deadlines, widget: widget)
        sendPending()
    }

    private func sendPending() {
        guard let session, session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled, let pending, delivered != pending else { return }
        do {
            try session.updateApplicationContext(["plan": JSONEncoder().encode(pending)])
            delivered = pending
        } catch {
            // Keep the latest snapshot pending for the next update.
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.delivered = nil
            session.activate()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.delivered = nil
            self.sendPending()
        }
    }
    #else
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    nonisolated private func receive(_ context: [String: Any]) {
        guard let data = context["plan"] as? Data,
              let plan = try? JSONDecoder().decode(WatchPlan.self, from: data) else { return }
        Task { @MainActor in
            self.plan = plan
            if let widget = plan.widget { WidgetSnapshot.publish(widget) }
        }
    }
    #endif
}
#endif
