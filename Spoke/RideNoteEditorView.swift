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
                    Text("Note")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isNoteFocused = false
                        }

                    TextEditor(text: $noteText)
                        .focused($isNoteFocused)
                        .font(.body)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .padding(.trailing, isNoteFocused && !noteText.isEmpty ? 30 : 0)
                        .overlay(alignment: .topTrailing) {
                            if isNoteFocused && !noteText.isEmpty {
                                Button {
                                    noteText = ""
                                    isNoteFocused = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear note")
                                .padding(8)
                            }
                        }
                        .accessibilityLabel("Note")
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .navigationTitle("Ride Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            }
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
