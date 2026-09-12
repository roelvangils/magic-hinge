import SwiftUI
import DuoCore

struct AboutView: View {
    private static let basicAppleGuy = Bundle.module.url(forResource:"BasicAppleGuy",withExtension:"png")
        .flatMap { NSImage(contentsOf:$0) }
    private var version: String {
        L10n.format("Version %@ (%@)",
            Bundle.main.object(forInfoDictionaryKey:"MagicHingeDisplayVersion") as? String ?? Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—",
            Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—")
    }
    var body: some View {
        VStack(spacing:20) {
            VStack(spacing:8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width:80,height:80)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Magic Hinge").font(.system(size:27,weight:.semibold,design:.rounded))
                Text(version).font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing:8) {
                Text(L10n.text("Built by Roel Van Gils and GPT 6 Astra"))
                Text(L10n.text("© MacBook 3D Models by Apple")).foregroundStyle(.secondary)
            }.font(.callout)
            Divider()
            HStack(spacing:16) {
                if let icon = Self.basicAppleGuy {
                    Image(nsImage:icon).resizable().scaledToFit()
                        .frame(width:48,height:56).accessibilityHidden(true)
                }
                Text((try? AttributedString(markdown:L10n.text("Wallpaper attribution"))) ?? AttributedString(L10n.text("Wallpaper attribution")))
                    .font(.callout)
                    .tint(.accentColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal:false,vertical:true)
                    .frame(maxWidth:.infinity,alignment:.leading)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(width:460)
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing:.appInfo) {
            Button(L10n.text("About Magic Hinge")) {
                openWindow(id:"about")
                NSApp.activate(ignoringOtherApps:true)
            }
        }
    }
}
