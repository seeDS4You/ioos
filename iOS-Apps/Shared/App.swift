import SwiftUI

@main struct SISSApp: App {
    @StateObject private var api = API.shared
    var body: some Scene {
        WindowGroup {
            Group {
                if api.user != nil {
                    #if STAFF
                    StaffRoot()
                    #elseif ADMIN
                    AdminRoot()
                    #else
                    SupervisorRoot()
                    #endif
                } else { LoginScreen() }
            }
            .environmentObject(api).preferredColorScheme(.dark).tint(Palette.blue)
        }
    }
}
struct LoginScreen: View {
    @EnvironmentObject var api: API
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 48)).foregroundStyle(Palette.blue)
                Text(AppKind.name).font(.largeTitle.bold())
                Text(AppKind.supervisor ? "Your shift. Your team. Your report." : "Security Shift Management").foregroundStyle(Palette.muted)
                Panel {
                    Text("Welcome back").font(.title2.bold())
                    TextField("Email address", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 12))
                    SecureField("Password", text: $password).textContentType(.password).padding(14).background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 12))
                    if let error { Notice(text: error) }
                    PrimaryButton(title: busy ? "Signing in…" : "Sign in", enabled: !busy && !api.restoring && !email.isEmpty && !password.isEmpty) {
                        busy = true; error = nil
                        Task { defer { busy = false }; do { try await api.login(email, password); password = "" } catch { self.error = error.localizedDescription } }
                    }
                    if api.hasSession { Button("Unlock saved session") { Task { await api.restore() } }.disabled(api.restoring) }
                    if api.restoring { ProgressView("Checking session…") }
                    if let message = api.message { Notice(text: message) }
                }
                Text("Sierra 1 Security Stewarding Ltd").font(.caption).foregroundStyle(Palette.muted)
                Text(API.base.host ?? "").font(.caption2).foregroundStyle(Palette.muted)
            }.padding(.top, 60)
        }.task { await api.restore() }
    }
}
struct AccountScreen: View {
    @EnvironmentObject var api: API
    @State private var confirm = false
    var body: some View {
        Screen {
            Panel { Text(api.user?.name ?? "").font(.title2.bold()); Text(api.user?.text("email") ?? "").foregroundStyle(Palette.muted); Badge(text: AppKind.role) }
            Panel { Text("Sierra 1 Security Stewarding Ltd").font(.headline); Text(API.base.host ?? "").foregroundStyle(Palette.muted) }
            Button("Sign out", role: .destructive) { confirm = true }.buttonStyle(.bordered).frame(maxWidth: .infinity)
        }.navigationTitle("Account").confirmationDialog("Sign out of \(AppKind.name)?", isPresented: $confirm, titleVisibility: .visible) { Button("Sign out", role: .destructive) { Task { await api.logout() } } }
    }
}
