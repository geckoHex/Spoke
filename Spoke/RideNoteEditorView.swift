//
//  RideNoteEditorView.swift
//  Spoke
//

import SwiftData
import SwiftUI
import UIKit

struct RideNoteEditorView: View {
    let ride: TrackedRide

    @Environment(\.modelContext) private var modelContext
    @State private var isNoteFocused = false
    @State private var noteText: String

    init(ride: TrackedRide) {
        self.ride = ride
        _noteText = State(initialValue: ride.note ?? "")
    }

    var body: some View {
        SpokeSheet(title: "Ride Notes") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Note")
                    .font(.subheadline)
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { isNoteFocused = false }

                HStack(alignment: .top, spacing: 4) {
                    NoteTextView(text: $noteText, isFocused: $isNoteFocused)
                        .frame(maxWidth: .infinity)

                    if isNoteFocused && !noteText.isEmpty {
                        Button {
                            noteText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(SpokeStyle.secondaryText)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear note")
                    }
                }
                .padding(8)
                .frame(minHeight: 52)
                .background(SpokeStyle.elevatedSurface, in: .rect(cornerRadius: 12))
            }
            .padding(.horizontal, SpokeStyle.pageInset)
            .padding(.vertical, 12)
            .background {
                SpokeStyle.surface
                    .onTapGesture { isNoteFocused = false }
            }
        }
        .background {
            SpokeStyle.surface
                .onTapGesture { isNoteFocused = false }
        }
        .onChange(of: noteText) {
            ride.updateNote(to: noteText)
            try? modelContext.save()
        }
    }
}

private struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textColor = UIColor(SpokeStyle.text)
        view.tintColor = UIColor(SpokeStyle.accent)
        view.returnKeyType = .done
        view.keyboardDismissMode = .interactive
        view.isScrollEnabled = false
        view.accessibilityLabel = "Note"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        if !isFocused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextView

        init(parent: NoteTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isFocused = false }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n" else { return true }
            textView.resignFirstResponder()
            return false
        }
    }
}

#Preview {
    RideNoteEditorView(ride: TrackedRide())
        .modelContainer(for: TrackedRide.self, inMemory: true)
}
