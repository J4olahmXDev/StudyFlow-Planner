import SwiftUI
#if os(macOS)
import AppKit

final class AppDelegate:NSObject,NSApplicationDelegate {
    var timer:Timer?;var frames=0
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps:true)
        if let i=CommandLine.arguments.firstIndex(of:"--screenshot"),CommandLine.arguments.count>i+1 {
            let path=CommandLine.arguments[i+1]
            timer=Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] timer in
                guard let self else{return};self.frames+=1;guard self.frames>=120 else{return};timer.invalidate()
                guard let window=NSApplication.shared.windows.first(where:{$0.isVisible && $0.contentView != nil}),let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {fputs("Cannot capture window\n",stderr);exit(2)}
                view.cacheDisplay(in:view.bounds,to:bitmap)
                do { guard let data=bitmap.representation(using:.png,properties:[:]) else{exit(3)};try FileManager.default.createDirectory(at:URL(fileURLWithPath:path).deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:URL(fileURLWithPath:path));print("Screenshot saved: \(path)");NSApplication.shared.terminate(nil) } catch {fputs("Screenshot failed: \(error)\n",stderr);exit(4)}
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
#endif
@main struct DaylightApp:App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif
    #if os(iOS) || os(watchOS)
    @StateObject private var watch = WatchSync()
    #endif
    #if !os(watchOS)
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("planner.demoWorkspace") private var showDemo = true
    @StateObject private var store = PlannerStore(fallback: Database(), cloudDefaults: .standard)
    @StateObject private var demo = PlannerStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Daylight/preview.json"),
        remindersEnabled: false,
        legacyName: "ภาคเรียนที่ 1 / \(Calendar(identifier: .buddhist).component(.year, from: .now))"
    )
    private func publishWidget(_ database: Database) {
        let termID = store.activeTermID(in: database)
        let termName = database.terms?.first { $0.id == termID }?.name
            ?? store.termOptions.first { $0.id == termID }?.name ?? "StudyFlow"
        let term = database.inTerm(termID)
        let snapshot = term.widgetSnapshot(term: termName)
        WidgetSnapshot.publish(snapshot)
        #if os(iOS)
        watch.publish(term, widget: snapshot)
        #endif
    }
    #endif
    var body:some Scene {
        WindowGroup {
            #if os(watchOS)
            WatchTodayView().environmentObject(watch)
            #else
            MainView(showDemo: $showDemo)
                .environmentObject(showDemo ? demo : store)
                .id(showDemo)
                #if os(macOS)
                .frame(minWidth:640,minHeight:530)
                #endif
                .onReceive(store.$db) { publishWidget($0) }
                .onChange(of: store.activeTermID) { _, _ in publishWidget(store.db) }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        publishWidget(store.db)
                        await store.syncNow()
                        await store.refreshShares()
                        try? await Task.sleep(for: .seconds(15))
                    }
                }
            #endif
        }
        #if os(macOS)
        .defaultSize(width:1420,height:780)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
