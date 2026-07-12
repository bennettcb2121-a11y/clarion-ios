import SwiftUI

/// Customize the vitals dashboard: drag to reorder, remove, add from the catalog. Persists to
/// the same profile field the web Customize mode uses, so app + site share one dashboard.
struct CustomizeSheet: View {
    @ObservedObject var store: VitalsStore
    @Environment(\.dismiss) private var dismiss

    @State private var keys: [String] = []

    private var addable: [VitalsMetric] {
        VitalsMetric.allKeys.filter { !keys.contains($0) }.compactMap { VitalsMetric.catalog[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(keys, id: \.self) { key in
                        if let m = VitalsMetric.catalog[key] {
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(Color.ink4)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.title).font(.clarionDisplay(15)).foregroundStyle(Color.ink)
                                    Text(m.caption).font(.clarionBody(12)).foregroundStyle(Color.ink3)
                                }
                                Spacer()
                                Button {
                                    Haptics.tap()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        keys.removeAll { $0 == key }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.clay.opacity(0.85))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onMove { from, to in
                        Haptics.selection()
                        keys.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Your dashboard — drag to reorder")
                }

                if !addable.isEmpty {
                    Section {
                        ForEach(addable) { m in
                            HStack(spacing: 12) {
                                Button {
                                    Haptics.tap()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        keys.append(m.id)
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.forest)
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.title).font(.clarionDisplay(15)).foregroundStyle(Color.ink)
                                    Text(m.caption).font(.clarionBody(12)).foregroundStyle(Color.ink3)
                                }
                            }
                        }
                    } header: {
                        Text("Add widgets")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.success()
                        let saved = keys
                        Task { await store.saveWidgets(saved) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        Haptics.warning()
                        let cleared: [String] = []
                        Task {
                            await store.saveWidgets(cleared)
                            await store.load()
                        }
                        dismiss()
                    }
                    .foregroundStyle(Color.clay)
                }
            }
        }
        .onAppear { keys = store.widgetKeys }
        .presentationDetents([.large])
    }
}
