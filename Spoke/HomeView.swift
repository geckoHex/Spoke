//
//  HomeView.swift
//  Spoke
//

import SwiftUI

struct HomeView: View {
    let settings: AppSettings?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(alignment: .leading) {
                        Text(greeting(at: context.date))
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
            }
        }
    }

    private func greeting(at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let salutation = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }

        let trimmedName = settings?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "User"
        return "\(salutation), \(name)"
    }
}

#Preview {
    HomeView(settings: AppSettings())
        .preferredColorScheme(.dark)
}
