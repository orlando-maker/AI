import SwiftUI

struct SubmissionConfirmationView: View {
    let reportID: UUID
    let reportType: ReportType
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Report Submitted")
                    .font(.title.bold())
                Text("Thank you for helping keep Woodside's trails and roads safe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Report Type", value: reportType.displayName)
                LabeledContent("Confirmation ID") {
                    Text(reportID.uuidString.prefix(8).uppercased())
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Text("You can track the status of this report in **My Reports**.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Submitted")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}
