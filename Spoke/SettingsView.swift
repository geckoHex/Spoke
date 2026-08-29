//
//  SettingsView.swift
//  Spoke
//

import SwiftUI
import SwiftData

private enum SettingsField: Hashable {
    case name
    case spotifyClientID
    case spotifyClientSecret
    case spotifyRefreshToken
}

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
    @Bindable var settings: AppSettings
    @FocusState private var focusedField: SettingsField?
    @State private var inputFrames: [SettingsField: CGRect] = [:]

    var body: some View {
        Form {
            Section("Name") {
                HStack(spacing: 8) {
                    TextField("", text: $settings.name)
                        .focused($focusedField, equals: .name)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                        .accessibilityLabel("Name")

                    if focusedField == .name && !settings.name.isEmpty {
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
                .inputFramePreference(for: .name)
            }

            Section {
                Toggle("Keep screen on", isOn: $settings.keepScreenOn)
                Toggle("Speak Speed", isOn: $settings.speakSpeedEnabled)
            }

            Section("Developer") {
                Toggle("Enable Developer Mode", isOn: $settings.developerModeEnabled)
            }

            Section("Spotify Client ID") {
                HStack(spacing: 8) {
                    TextField("", text: $settings.spotifyClientID)
                        .focused($focusedField, equals: .spotifyClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                        .accessibilityLabel("Spotify client ID")

                    clearButton(
                        for: .spotifyClientID,
                        value: $settings.spotifyClientID,
                        label: "Clear Spotify client ID"
                    )
                }
                .inputFramePreference(for: .spotifyClientID)
            }

            Section("Spotify Client Secret") {
                HStack(spacing: 8) {
                    SecureField("", text: $settings.spotifyClientSecret)
                        .focused($focusedField, equals: .spotifyClientSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                        .privacySensitive()
                        .accessibilityLabel("Spotify client secret")

                    clearButton(
                        for: .spotifyClientSecret,
                        value: $settings.spotifyClientSecret,
                        label: "Clear Spotify client secret"
                    )
                }
                .inputFramePreference(for: .spotifyClientSecret)
            }

            Section("Spotify Refresh Token") {
                HStack(spacing: 8) {
                    SecureField("", text: $settings.spotifyRefreshToken)
                        .focused($focusedField, equals: .spotifyRefreshToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                        .privacySensitive()
                        .accessibilityLabel("Spotify refresh token")

                    clearButton(
                        for: .spotifyRefreshToken,
                        value: $settings.spotifyRefreshToken,
                        label: "Clear Spotify refresh token"
                    )
                }
                .inputFramePreference(for: .spotifyRefreshToken)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black)
        .tint(.blue)
        .coordinateSpace(name: "settingsForm")
        .onPreferenceChange(SettingsInputFramePreferenceKey.self) {
            inputFrames = $0
        }
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("settingsForm"))
                .onEnded { value in
                    guard !inputFrames.values.contains(where: { $0.contains(value.location) })
                    else { return }
                    focusedField = nil
                }
        )
    }

    @ViewBuilder
    private func clearButton(
        for field: SettingsField,
        value: Binding<String>,
        label: String
    ) -> some View {
        if focusedField == field && !value.wrappedValue.isEmpty {
            Button {
                value.wrappedValue = ""
                focusedField = field
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }
}

private struct SettingsInputFramePreferenceKey: PreferenceKey {
    static let defaultValue: [SettingsField: CGRect] = [:]

    static func reduce(
        value: inout [SettingsField: CGRect],
        nextValue: () -> [SettingsField: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    func inputFramePreference(for field: SettingsField) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SettingsInputFramePreferenceKey.self,
                    value: [field: geometry.frame(in: .named("settingsForm"))]
                )
            }
        }
    }
}

#Preview {
    SettingsView(settings: AppSettings())
        .preferredColorScheme(.dark)
}
