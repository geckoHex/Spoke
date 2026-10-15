//
//  SettingsView.swift
//  Spoke
//

import SwiftUI
import SwiftData

private enum SettingsField: Hashable {
    case name
}

struct SettingsView: View {
    let settings: AppSettings?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(SpokeStyle.pageTitle)
                    .tracking(-0.8)
                    .foregroundStyle(SpokeStyle.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settingsTitle")
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Group {
                    if let settings {
                        SettingsForm(settings: settings)
                    } else {
                        SpokeStyle.background
                            .ignoresSafeArea()
                    }
                }
            }
            .background(SpokeStyle.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Environment(SpotifyAuthenticationStore.self) private var spotifyAuthentication
    @FocusState private var focusedField: SettingsField?
    @State private var inputFrames: [SettingsField: CGRect] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Name")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
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
                                    .foregroundStyle(SpokeStyle.secondaryText)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear name")
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(SpokeStyle.surface)
                    .inputFramePreference(for: .name)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("On the bike")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 8)
                    Toggle("Keep screen on during rides", isOn: $settings.keepScreenOn)
                        .frame(minHeight: 56)
                    Divider().overlay(SpokeStyle.separator)
                    Toggle("Sound effects", isOn: $settings.soundEffectsEnabled)
                        .frame(minHeight: 56)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Developer")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Toggle("Enable Developer Mode", isOn: $settings.developerModeEnabled)
                        .frame(minHeight: 56)
                    if settings.developerModeEnabled {
                        Text("Speed is simulated. Hold the speedometer to increase it; release to slow down.")
                            .font(.footnote)
                            .foregroundStyle(SpokeStyle.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Spotify")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if spotifyAuthentication.sessionID != nil {
                        Label("Connected to Spotify", systemImage: "checkmark")
                            .foregroundStyle(SpokeStyle.text)

                        Button("Disconnect Spotify", role: .destructive) {
                            Task { await spotifyAuthentication.signOut() }
                        }
                        .buttonStyle(SpokeSecondaryButtonStyle())
                    } else {
                        Button {
                            focusedField = nil
                            Task { await spotifyAuthentication.signIn() }
                        } label: {
                            HStack(spacing: 10) {
                                if spotifyAuthentication.isConnecting {
                                    ProgressView()
                                        .tint(SpokeStyle.onPrimaryAction)
                                }
                                Text(spotifyAuthentication.isConnecting ? "Signing in…" : "Sign in with Spotify")
                            }
                        }
                        .buttonStyle(SpokePrimaryButtonStyle())
                        .disabled(spotifyAuthentication.isConnecting)
                        .accessibilityIdentifier("spotifySignIn")
                    }
                    Text(spotifyAuthentication.errorMessage ?? "See what’s playing and save your ride’s soundtrack.")
                        .font(.footnote)
                        .foregroundStyle(spotifyAuthentication.errorMessage == nil ? SpokeStyle.secondaryText : SpokeStyle.danger)
                }
            }
            .padding(.horizontal, SpokeStyle.pageInset)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .foregroundStyle(SpokeStyle.text)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(SpokeStyle.background)
        .tint(SpokeStyle.primaryAction)
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 112 / 255)))
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
        .environment(SpotifyAuthenticationStore())
        .preferredColorScheme(.dark)
}
