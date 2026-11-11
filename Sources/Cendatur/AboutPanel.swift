import AppKit

/// Shows the standard About panel with the name's etymology and a license
/// notice in the credits area.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cendatur",
            // The marketing version alone; the build number CI stamps on
            // each upload isn't something a user needs to read.
            .applicationVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .version: "",
            .credits: credits(),
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6

        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let secondary: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let text = NSMutableAttributedString()
        text.append(
            NSAttributedString(
                string: "Scans paper documents over USB and saves them as PDFs.\n\n",
                attributes: body))
        text.append(etymology(attributes: secondary))
        text.append(
            NSAttributedString(
                string: """
                    Licensed under the Apache License, Version 2.0. Distributed on \
                    an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.\n\n
                    """,
                attributes: secondary))
        text.append(NSAttributedString(string: "See the ", attributes: secondary))
        text.append(link("full license", url: licenseURL, attributes: secondary))
        text.append(
            NSAttributedString(
                string: ". The scanner is driven directly over USB; no third-party "
                    + "components are bundled.",
                attributes: secondary))
        return text
    }

    /// Where the name comes from. The Quenya words are set in italics.
    private static func etymology(
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var italic = attributes
        italic[.font] = NSFontManager.shared.convert(
            NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), toHaveTrait: .italicFontMask)

        let parts: [(String, Bool)] = [
            ("Cendatur", true),
            (" (KEN-da-toor) is a name coined from Quenya, Tolkien's High-elven tongue: ", false),
            ("cenda-", true),
            (", “to read; to watch closely in order to learn”, and ", false),
            ("-tur", true),
            (", “master”, as in ", false),
            ("Ciryatur", true),
            (", “ship-master”. Together: a master of close reading.\n\n", false),
        ]
        let text = NSMutableAttributedString()
        for (string, isItalic) in parts {
            text.append(
                NSAttributedString(string: string, attributes: isItalic ? italic : attributes))
        }
        return text
    }

    /// Prefer the copy shipped inside the bundle; fall back to apache.org.
    private static var licenseURL: URL {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("LICENSE")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!
    }

    private static func link(
        _ label: String, url: URL, attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var linkAttributes = attributes
        linkAttributes[.link] = url
        return NSAttributedString(string: label, attributes: linkAttributes)
    }
}
