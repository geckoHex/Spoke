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
                Color(uiColor: .secondarySystemBackground)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isNoteFocused = false
                    }

                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $noteText)
                        .focused($isNoteFocused)
                        .font(.body)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Note")
                }
                .padding(.horizontal, 20)
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
            .toolbarBackground(Color(uiColor: .secondarySystemBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
        .presentationBackground(Color(uiColor: .secondarySystemBackground))
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
