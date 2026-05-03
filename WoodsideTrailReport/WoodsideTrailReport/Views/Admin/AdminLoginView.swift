import SwiftUI

struct AdminLoginView: View {
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDashboard = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text("Admin Access")
                    .font(.title2.bold())
                Text(Config.adminEmail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.go)
                    .onSubmit { Task { await login() } }

                if let err = errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await login() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Sign In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .disabled(password.isEmpty || isLoading)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDashboard) {
            AdminDashboardView()
        }
    }

    private func login() async {
        guard !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await SupabaseService.shared.adminSignIn(password: password)
            showDashboard = true
        } catch {
            errorMessage = "Incorrect password. Please try again."
        }
        isLoading = false
    }
}
