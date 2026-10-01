//
//  RideNoteEditorView.swift
//  Spoke
//

import SwiftData
import SwiftUI
import UIKit

struct RideNoteEditorView: View {
    let ride: TrackedRide

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isNoteFocused: Bool
    @State private var noteText: String

    init(ride: TrackedRide) {
        self.ride = ride
        _noteText = State(initialValue: ride.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpokeStyle.surface
                    .ignoresSafeArea()
                    .onTapGesture {
                        isNoteFocused = false
                    }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Note")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SpokeStyle.secondaryText)

                    HStack(alignment: .top, spacing: 8) {
                        TextEditor(text: $noteText)
                            .focused($isNoteFocused)
                            .font(.body)
                            .foregroundStyle(SpokeStyle.text)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Note")

                        if isNoteFocused && !noteText.isEmpty {
                            Button {
                                noteText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(SpokeStyle.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear note")
                            .padding(.top, 8)
                        }
                    }
                    .padding(12)
                    .background(SpokeStyle.elevatedSurface, in: .rect(cornerRadius: 8))
                }
                .padding(.horizontal, SpokeStyle.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .navigationTitle("Ride Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(SpokeToolbarButtonStyle())
                    .accessibilityLabel("Done")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbarBackground(SpokeStyle.surface, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
        .presentationBackground(SpokeStyle.surface)
        .presentationDragIndicator(.visible)
        .onChange(of: noteText) {
            ride.updateNote(to: noteText)
            try? modelContext.save()
        }
    }
}

#Preview {
    RideNoteEditorView(ride: TrackedRide())
        .modelContainer(for: TrackedRide.self, inMemory: true)
}
