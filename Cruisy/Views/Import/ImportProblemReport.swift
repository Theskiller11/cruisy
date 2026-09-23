import SwiftUI
import MessageUI

/// «Segnala un problema di lettura»: un'email a Matteo con quello che Cruisy ha letto e
/// il testo da cui l'ha letto.
///
/// Esiste perché il lettore migliora solo con documenti veri — quello di Explora ha
/// trovato cinque difetti in un pomeriggio — e Cruisy non raccoglie niente da sola. Qui
/// raccoglie la persona: vede tutto il testo prima di mandarlo, può cancellare quello
/// che non vuole condividere (nome, numero di prenotazione), e l'email parte dalla sua
/// app Mail, non da un nostro server.
enum ImportProblemReport {
    static let recipient = CruisySite.email

    static var subject: String { String(localized: "Cruisy: problema di lettura dell'itinerario") }

    /// Il corpo dell'email: prima lo spazio per dire cosa non torna, poi quello che
    /// l'app ha capito, poi il testo originale.
    static func body(draft: ItineraryDraft, sourceText: String,
                     appVersion: String, systemVersion: String) -> String {
        var lines: [String] = [
            String(localized: "Cosa non torna:"),
            "",
            "",
            "— " + String(localized: "Cosa ha letto Cruisy") + " —",
            String(localized: "Nave: \(draft.shipName ?? "—")"),
        ]
        for call in draft.calls {
            let date = [call.day, call.month, call.year].map { $0.map(String.init) ?? "?" }.joined(separator: "/")
            var line = "\(date)  \(call.displayName)"
            let times = [call.arrival, call.departure, call.allAboard].map { $0?.formatted ?? "–" }
            if !call.isSeaDay { line += "  " + times.joined(separator: " / ") }
            if !call.issues.isEmpty {
                line += "  [" + call.issues.map(\.label).sorted().joined(separator: ", ") + "]"
            }
            lines.append(line)
        }
        lines.append(contentsOf: draft.warnings)
        lines += ["", "— " + String(localized: "Il testo originale") + " —", sourceText, "",
                  "Cruisy \(appVersion) · iOS \(systemVersion)"]
        return lines.joined(separator: "\n")
    }
}

/// Il foglio della segnalazione: si legge e si corregge tutto prima di mandarlo.
struct ImportProblemReportSheet: View {
    let draft: ItineraryDraft
    let sourceText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.livery) private var livery
    @State private var text = ""
    @State private var isComposing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 320)
                } footer: {
                    Text("Scrivi in cima cosa non torna. Qui sotto c'è il testo che Cruisy ha letto: cancella quello che non vuoi mandare, come il tuo nome o il numero di prenotazione. L'email parte dalla tua app Mail e la vedi prima di inviarla.")
                }

                Section {
                    if MailComposer.canSend {
                        Button { isComposing = true } label: {
                            Label("Scrivi l'email", systemImage: "envelope")
                        }
                    } else {
                        // Senza un account in Mail, il testo si manda come si vuole.
                        ShareLink(item: text, subject: Text(ImportProblemReport.subject)) {
                            Label("Condividi il testo", systemImage: "square.and.arrow.up")
                        }
                        Text("Mandalo a \(ImportProblemReport.recipient)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(livery.tint)
            .navigationTitle("Segnala un problema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .onAppear {
                if text.isEmpty {
                    text = ImportProblemReport.body(
                        draft: draft, sourceText: sourceText,
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                        systemVersion: UIDevice.current.systemVersion)
                }
            }
            .sheet(isPresented: $isComposing) {
                MailComposer(recipient: ImportProblemReport.recipient,
                             subject: ImportProblemReport.subject, body: text) { sent in
                    isComposing = false
                    if sent { dismiss() }
                }
                .ignoresSafeArea()
            }
        }
    }
}

/// Il compositore di Mail, con destinatario, oggetto e testo già scritti.
private struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (Bool) -> Void

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent)
        }
    }
}
