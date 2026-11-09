#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct CloudSettings: View {
    @EnvironmentObject private var store: PlannerStore
    let showDemo: Bool
    @State private var address = ""
    @State private var publishableKey = ""
    @State private var enteredCode = ""
    @State private var editingConfiguration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("ซิงก์ด้วยโค้ด", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            if showDemo {
                Text("ปิดโหมดตัวอย่างเพื่อซิงก์ข้อมูลจริง")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if let code = store.cloudCode {
                    Text("เครื่องอื่นเชื่อมได้ด้วยโค้ดเดียวกัน เก็บโค้ดไว้เป็นส่วนตัว")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("คัดลอกโค้ด") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code.display, forType: .string)
                            #else
                            UIPasteboard.general.string = code.display
                            #endif
                        }
                        Button("ซิงก์ตอนนี้") { Task { await store.syncNow() } }
                        Button("ยกเลิกการเชื่อม") { store.disconnectCloud() }
                    }
                    .disabled(store.syncing)
                } else if store.cloudConfiguration == nil || editingConfiguration {
                    TextField("Supabase Project URL", text: $address)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    TextField("Supabase Publishable Key", text: $publishableKey)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    Button("บันทึกการตั้งค่าคลาวด์") {
                        store.configureCloud(address: address, key: publishableKey)
                        if store.cloudConfiguration != nil { editingConfiguration = false }
                    }
                    .disabled(address.isEmpty || publishableKey.isEmpty)
                } else {
                    Text("สร้างโค้ดเพื่อซิงก์ข้อมูลเครื่องนี้ หรือใช้โค้ดจากเครื่องที่เชื่อมไว้แล้ว")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("โค้ดซิงก์", text: $enteredCode)
                    HStack {
                        Button("ใช้โค้ดนี้") { Task { await store.connectCloud(enteredCode: enteredCode) } }
                            .disabled(enteredCode.isEmpty)
                        if store.db.syncWorkspace == nil {
                            Button("สร้างโค้ดและซิงก์") { Task { await store.connectCloud(enteredCode: nil) } }
                        }
                        Button("ตั้งค่าคลาวด์") {
                            address = store.cloudConfiguration?.url.absoluteString ?? ""
                            publishableKey = store.cloudConfiguration?.publishableKey ?? ""
                            editingConfiguration = true
                        }
                    }
                    .disabled(store.syncing)
                }
                Text(store.syncing ? "กำลังซิงก์…" : store.cloudStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
