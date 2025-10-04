import SwiftUI
import AppKit

struct SettingsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 18) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Divider()

            // Paste modifiers
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste hotkey modifiers (used with 1–9 and 0 for Clear All)")
                    .font(.headline)
                ModRow(title: "Paste", mods: $settings.pasteMods)
                Text("Example: If you choose ⌘ + ⌥, then ⌘⌥1…9 paste registers; ⌘⌥0 clears all.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Save modifiers
            VStack(alignment: .leading, spacing: 8) {
                Text("Save hotkey modifiers (used with 1–9 to save selection)")
                    .font(.headline)
                ModRow(title: "Save", mods: $settings.saveMods)
                Text("Example: If you choose ⌘ + ⌥ + ⇧, then ⇧⌘⌥1…9 save the current selection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reset Defaults") { settings.resetDefaults() }
                Spacer()
                Button("Quit KeyboardRegisters") { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 320)
    }
}

private struct ModRow: View {
    let title: String
    @Binding var mods: SettingsStore.Mods

    var body: some View {
        HStack(spacing: 16) {
            Toggle("⌘", isOn: $mods.cmd).toggleStyle(.switch).frame(width: 60, alignment: .leading)
            Toggle("⌥", isOn: $mods.opt).toggleStyle(.switch).frame(width: 60, alignment: .leading)
            Toggle("⇧", isOn: $mods.shift).toggleStyle(.switch).frame(width: 60, alignment: .leading)
            Toggle("^",  isOn: $mods.ctrl).toggleStyle(.switch).frame(width: 60, alignment: .leading)
            Spacer()
        }
    }
}
