import SwiftUI
import MessageUI

/// Prefilled Messages compose sheet. iOS never lets an app send a text by
/// itself — the pilot always taps Send — so this is the closest legal thing
/// to an auto-text: everything filled in, one tap to go.
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    @Environment(\.dismiss) private var dismiss

    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            dismiss()
        }
    }
}

/// The message + recipients being prepared, driving the compose sheet.
struct FlightTextPayload: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
}
