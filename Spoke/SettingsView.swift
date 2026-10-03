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
                    .font(.largeTitle.bold())
                    .foregroundStyle(SpokeStyle.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settingsTitle")
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.top, 20)
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
    @EnvironmentObject private var spotifyAuthentication: SpotifyAuthenticationStore
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
                                .foregroundStyle(SpokeStyle.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear name")
                    }
                }
                .inputFramePreference(for: .name)
            }
            .listRowBackground(SpokeStyle.surface)

            Section("On the bike") {
                Toggle("Keep screen on", isOn: $settings.keepScreenOn)
            }
            .listRowBackground(SpokeStyle.surface)

            Section("Developer") {
                Toggle("Enable Developer Mode", isOn: $settings.developerModeEnabled)
            }
            .listRowBackground(SpokeStyle.surface)

            Section {
                if spotifyAuthentication.sessionID != nil {
                    Label("Connected to Spotify", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(SpokeStyle.accent)

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
                                    .tint(SpokeStyle.background)
                            }
                            Text(spotifyAuthentication.isConnecting ? "Signing in…" : "Sign in with Spotify")
                        }
                    }
                    .buttonStyle(SpokePrimaryButtonStyle())
                    .disabled(spotifyAuthentication.isConnecting)
                    .accessibilityIdentifier("spotifySignIn")
                }
            } header: {
                Text("Spotify")
            } footer: {
                Text(spotifyAuthentication.errorMessage ?? "See what’s playing and save your ride’s soundtrack.")
                    .foregroundStyle(spotifyAuthentication.errorMessage == nil ? SpokeStyle.secondaryText : SpokeStyle.danger)
            }
            .listRowBackground(SpokeStyle.surface)
        }
        .textCase(nil)
        .foregroundStyle(SpokeStyle.text)
        .environment(\.defaultMinListRowHeight, 56)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(SpokeStyle.background)
        .tint(SpokeStyle.accent)
        .toggleStyle(.switch)
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
        .environmentObject(SpotifyAuthenticationStore())
        .preferredColorScheme(.dark)
}
