#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct ShareSheet: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let showDemo: Bool
    @State private var selection = ShareSelection()
    @State private var pendingRevoke: PublishedShare?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("แชร์จาก StudyFlow").font(.title2.bold())
                if showDemo {
                    Text("ปิดโหมดตัวอย่างเพื่อเลือกแชร์ข้อมูลจริง").foregroundStyle(.secondary)
                } else if store.cloudConfiguration == nil {
                    Text("ตั้งค่าคลาวด์ครั้งแรกเพื่อสร้างโค้ดแชร์").foregroundStyle(.secondary)
                    CloudSettings(showDemo: false)
                } else {
                    Text("เทอมที่จะแชร์ · \(termName(store.activeTermID))").font(.headline)
                    Text("เลือกข้อมูลที่เครื่องอื่นจะดูได้ การเปลี่ยนแปลงจะส่งตามเมื่อเปิด StudyFlow บนอุปกรณ์ที่แชร์และออนไลน์")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle("ตารางเรียนและวิชา", isOn: $selection.timetable)
                        Toggle("งาน รวมโน้ตและงานย่อยในงาน", isOn: $selection.tasks)
                        Toggle("กิจกรรม", isOn: $selection.events)
                    }
                    Button("สร้างโค้ดและรหัส") { Task { await store.createShare(selection: selection) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(selection.isEmpty || store.sharing)
                    if !store.shares.isEmpty { Divider() }
                    ForEach(store.shares.reversed()) { share in shareRow(share) }
                    if store.sharing || !store.shareStatus.isEmpty {
                        Text(store.sharing ? "กำลังอัปเดตชุดแชร์…" : store.shareStatus)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("เสร็จสิ้น") { dismiss() }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
        }
        .frame(minHeight: 320, maxHeight: 520)
        #if os(macOS)
        .frame(width: 435)
        #endif
        .confirmationDialog("หยุดแชร์ชุดนี้?", isPresented: Binding(
            get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }
        ), presenting: pendingRevoke) { share in
            Button("หยุดแชร์", role: .destructive) { Task { await store.revokeShare(share) } }
        }
    }

    private func termName(_ id: UUID?) -> String {
        store.termOptions.first { $0.id == (id ?? AcademicTerm.legacyID) }?.name ?? "เทอมเดิม"
    }

    private func shareRow(_ share: PublishedShare) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text([share.selection.timetable ? "ตารางเรียน" : nil, share.selection.tasks ? "งาน" : nil,
                  share.selection.events ? "กิจกรรม" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline.weight(.semibold))
            Text(termName(share.termID)).font(.caption).foregroundStyle(.secondary)
            if share.published {
                HStack {
                    Text("โค้ด \\(share.credentials.code)")
                    Spacer()
                    Text("รหัส \\(share.credentials.password)")
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            } else {
                Text("รออัปเดตชุดแชร์").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if share.published {
                    Button("คัดลอกโค้ด") { copy(share.credentials.code) }
                    Button("คัดลอกรหัส") { copy(share.credentials.password) }
                }
                Button("หยุดแชร์…") { pendingRevoke = share }.disabled(store.sharing)
            }
        }
        .padding(.vertical, 4)
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
#endif
