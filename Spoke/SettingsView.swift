//
//  SettingsView.swift
//  Spoke
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    let settings: AppSettings?

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    SettingsForm(settings: settings)
                } else {
                    Color.black
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct SettingsForm: View {
    private enum Field: Hashable {
        case name
    }

    @Bindable var settings: AppSettings
    @FocusState private var focusedField: Field?
    @State private var nameInputFrame = CGRect.zero

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    HStack(spacing: 8) {
                        TextField("First name", text: $settings.name)
                            .focused($focusedField, equals: .name)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }

                        if !settings.name.isEmpty {
                            Button {
                                settings.name = ""
                                focusedField = .name
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear name")
                        }
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: NameInputFramePreferenceKey.self,
                                value: geometry.frame(in: .named("settingsForm"))
                            )
                        }
                    }
                }

                Toggle("Keep screen on", isOn: $settings.keepScreenOn)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black)
        .tint(.blue)
        .coordinateSpace(name: "settingsForm")
        .onPreferenceChange(NameInputFramePreferenceKey.self) {
            nameInputFrame = $0
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("settingsForm"))
                .onEnded { value in
                    guard !nameInputFrame.contains(value.location) else { return }
                    focusedField = nil
                }
        )
    }
}

private struct NameInputFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

#Preview {
    SettingsView(settings: AppSettings())
        .preferredColorScheme(.dark)
}
