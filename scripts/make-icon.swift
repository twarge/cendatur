// Writes the Cendatur app icon as an Icon Composer bundle.
// Usage: swift scripts/make-icon.swift [output.icon]
//
// The output is Support/AppIcon.icon: icon.json plus one SVG per layer.
// Xcode's asset compiler turns it into every size the app needs and applies
// the system shape and the glass, dark, clear and tinted treatments, so the
// artwork here is full bleed and carries no squircle, shadow or glow of its
// own.
//
// The picture, from back to front: a blue field (the fill in icon.json), a
// sheet of paper whose lower half has already been read and gone dark (Page),
// the hex that came off it (Digits), and the scan beam dividing the two,
// right across the icon (Beam).
//
// The bundle is committed, so this only needs running when the design
// changes. To look at the result without building:
//
//     "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
//         Support/AppIcon.icon --export-image --output-file icon.png \
//         --platform macOS --rendition Default --width 512 --height 512 --scale 2
import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let outputURL =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Support/AppIcon.icon")

// MARK: Colours

// Icon Composer ignores opacity and gradients inside a layer's SVG, so every
// colour here is solid; the field's shading is the fill in icon.json.
struct RGB {
    var r, g, b: Double

    var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// The fill syntax icon.json uses.
    var fill: String { String(format: "extended-srgb:%.5f,%.5f,%.5f,1.00000", r, g, b) }

    /// This colour at `alpha` over `backing`, as the solid colour it makes.
    func over(_ backing: RGB, alpha: Double) -> RGB {
        RGB(
            r: backing.r + (r - backing.r) * alpha,
            g: backing.g + (g - backing.g) * alpha,
            b: backing.b + (b - backing.b) * alpha)
    }
}

let fieldTop = RGB(r: 0.13, g: 0.42, b: 0.81)
let fieldBottom = RGB(r: 0.05, g: 0.23, b: 0.52)
let paper = RGB(r: 1, g: 1, b: 1)
let ink = RGB(r: 0.75, g: 0.75, b: 0.75)  // text lines
let readout = RGB(r: 0.02, g: 0.07, b: 0.04)  // the page once it is read
let phosphor = RGB(r: 0.15, g: 1.0, b: 0.38)  // digits
let phosphorHead = RGB(r: 0.82, g: 1.0, b: 0.86)  // the head of a trail
let beam = RGB(r: 0.35, g: 0.85, b: 1.0)

// MARK: Geometry, on the 1024 x 1024 canvas with y downward

let canvas = 1024.0
let pageWidth = canvas * 0.60
let pageHeight = canvas * 0.78
let pageMinX = (canvas - pageWidth) / 2
let pageMaxX = pageMinX + pageWidth
let pageMinY = (canvas - pageHeight) / 2
let pageMaxY = pageMinY + pageHeight
let pageCorner = pageWidth * 0.045
// The beam is the dividing line: paper above it, data below.
let splitY = canvas / 2
let textInset = pageWidth * 0.14
let textWidth = pageWidth * 0.72

/// A coordinate, to a tenth of a point.
func n(_ value: Double) -> String {
    let text = String(format: "%.1f", value)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
}

func svg(_ body: [String]) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n"
        + body.map { "  \($0)\n" }.joined() + "</svg>\n"
}

// MARK: Page

func pageLayer() -> [String] {
    let (x0, x1, y0, y1, r) = (pageMinX, pageMaxX, pageMinY, pageMaxY, pageCorner)
    let arc = "A\(n(r)) \(n(r)) 0 0 1"
    var body = [
        // Unread paper above the beam, rounded at the top corners only.
        "<path d=\"M\(n(x0)) \(n(splitY)) L\(n(x0)) \(n(y0 + r)) \(arc) \(n(x0 + r)) \(n(y0)) "
            + "L\(n(x1 - r)) \(n(y0)) \(arc) \(n(x1)) \(n(y0 + r)) L\(n(x1)) \(n(splitY)) Z\" "
            + "fill=\"\(paper.hex)\"/>",
        // Below the beam the page has already been read, and its backing
        // goes dark.
        "<path d=\"M\(n(x1)) \(n(splitY)) L\(n(x1)) \(n(y1 - r)) \(arc) \(n(x1 - r)) \(n(y1)) "
            + "L\(n(x0 + r)) \(n(y1)) \(arc) \(n(x0)) \(n(y1 - r)) L\(n(x0)) \(n(splitY)) Z\" "
            + "fill=\"\(readout.hex)\"/>",
    ]
    // Text lines on the paper half; the ones further down are already hex.
    let lineHeight = pageHeight * 0.045
    for i in 0..<6 {
        let bottom = pageMinY + pageHeight * (0.18 + Double(i) * 0.13)
        if bottom > splitY { break }
        body.append(
            "<rect x=\"\(n(pageMinX + textInset))\" y=\"\(n(bottom - lineHeight))\" "
                + "width=\"\(n(textWidth))\" height=\"\(n(lineHeight))\" "
                + "rx=\"\(n(lineHeight / 2))\" fill=\"\(ink.hex)\"/>")
    }
    return body
}

// MARK: Digits

// The digits are drawn here rather than set in a font: single strokes on a
// 20 x 30 box, y downward, in M/L/C commands only so placing one is a matter
// of moving its coordinates.
let strokes: [Character: String] = [
    "0": "M10 0 C15.5 0 20 4.5 20 10 L20 20 C20 25.5 15.5 30 10 30 C4.5 30 0 25.5 0 20 "
        + "L0 10 C0 4.5 4.5 0 10 0 Z M6.5 20 L13.5 10",
    "1": "M3 7 L11 0 L11 30 M3 30 L19 30",
    "2": "M1 8 C1 3 5 0 10 0 C15.5 0 19 3.5 19 8.5 C19 14 13 17 1 30 L20 30",
    "3": "M1 5 C3 2 6 0 10 0 C15 0 19 3 19 7.5 C19 12 15 14.5 9 14.5 "
        + "C15 14.5 20 17 20 22 C20 27 15.5 30 10 30 C5.5 30 2 28 0 25",
    "4": "M15 30 L15 0 L0 21 L20 21",
    "5": "M18 0 L3 0 L1.5 13 C4 11 7 10.5 10 10.5 C16 10.5 20 14.5 20 20 "
        + "C20 26 15.5 30 10 30 C5.5 30 2 28 0 25",
    "6": "M17 1.5 C15 0.5 13 0 11 0 C4 0 0 7 0 19 C0 26 4 30 10 30 "
        + "C16 30 20 26 20 20.5 C20 15 16 11.5 10 11.5 C5 11.5 1 14.5 0 19",
    "7": "M0 0 L20 0 L8 30",
    "8": "M10 0 C14.4 0 18 3.4 18 7.5 C18 11.6 14.4 15 10 15 C5.6 15 2 11.6 2 7.5 "
        + "C2 3.4 5.6 0 10 0 Z M10 15 C15.5 15 20 18.4 20 22.5 C20 26.6 15.5 30 10 30 "
        + "C4.5 30 0 26.6 0 22.5 C0 18.4 4.5 15 10 15 Z",
    // A 6 turned half way round.
    "9": "M3 28.5 C5 29.5 7 30 9 30 C16 30 20 23 20 11 C20 4 16 0 10 0 "
        + "C4 0 0 4 0 9.5 C0 15 4 18.5 10 18.5 C15 18.5 19 15.5 20 11",
    "A": "M0 30 L10 0 L20 30 M4 20 L16 20",
    "B": "M0 0 L0 30 M0 0 L10 0 C15 0 18 3 18 7.25 C18 11.5 15 14.5 10 14.5 L0 14.5 "
        + "M10 14.5 C16 14.5 20 17.5 20 22.25 C20 27 16 30 10 30 L0 30",
    "C": "M19 5.5 C17 2 14 0 10.5 0 C4 0 0 5 0 15 C0 25 4 30 10.5 30 C14 30 17 28 19 24.5",
    "D": "M0 0 L0 30 L8 30 C16 30 20 24 20 15 C20 6 16 0 8 0 Z",
    "E": "M19 0 L0 0 L0 30 L19 30 M0 14.5 L15 14.5",
    "F": "M19 0 L0 0 L0 30 M0 14.5 L15 14.5",
    // A ring small enough that its stroke closes it into a dot.
    "·": "M10 13.5 C10.8 13.5 11.5 14.2 11.5 15 C11.5 15.8 10.8 16.5 10 16.5 "
        + "C9.2 16.5 8.5 15.8 8.5 15 C8.5 14.2 9.2 13.5 10 13.5 Z",
    "×": "M3 8 L17 22 M17 8 L3 22",
    "≡": "M2 7 L18 7 M2 15 L18 15 M2 23 L18 23",
    // Two S curves, the lower one the upper turned half way round.
    "§": "M16 5 C15 2 13 0 10 0 C6.5 0 4 2 4 5 C4 8.5 7 10 10.5 11.5 "
        + "C14 13 17 14.5 17 18 C17 20.5 15 22 12.5 22.5 "
        + "M4 25 C5 28 7 30 10 30 C13.5 30 16 28 16 25 C16 21.5 13 20 9.5 18.5 "
        + "C6 17 3 15.5 3 12 C3 9.5 5 8 7.5 7.5",
]

/// A glyph's strokes centred on (`cx`, `cy`), one box unit drawn `unit` wide.
func place(_ glyph: Character, cx: Double, cy: Double, unit: Double) -> String {
    var isX = true
    return strokes[glyph]!.split(separator: " ").map { token -> String in
        var token = Substring(token)
        var command = ""
        if let first = token.first, first.isLetter {
            command = String(first)
            token = token.dropFirst()
        }
        guard let value = Double(token) else { return command }
        defer { isX.toggle() }
        return command + n(isX ? cx + (value - 10) * unit : cy + (value - 15) * unit)
    }.joined(separator: " ")
}

func digitsLayer() -> [String] {
    // A fixed seed, so regenerating the icon reproduces this exact scatter of
    // digits rather than a new one every time.
    var seed: UInt64 = 0x5CA1_AB1E
    func random() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 40) / Double(1 << 24)
    }

    // ¥ is never reached by the index below; it stays in the list so the
    // scatter matches the icon this one replaces.
    let glyphs = Array("0123456789ABCDEF·×≡§¥")
    let columns = 6
    let rows = 5
    let cellWidth = textWidth / Double(columns)
    let cellHeight = (pageMaxY - splitY - pageHeight * 0.06) / Double(rows)
    // The size a bold monospaced face would be set at to fill the cell, and
    // from it the height of its capitals and the weight of its stems.
    let fontSize = min(cellWidth, cellHeight) * 0.86
    let weight = fontSize * 0.13
    let unit = (fontSize * 0.70 - weight) / 30

    // Each column sits at its own height, so the digits fall in streaks
    // instead of lining up into a table.
    let columnOffsets = (0..<columns).map { _ in (random() - 0.5) * cellHeight * 0.55 }

    var body = [
        "<g fill=\"none\" stroke-width=\"\(n(weight))\" stroke-linecap=\"round\" "
            + "stroke-linejoin=\"round\">"
    ]
    for row in 0..<rows {
        // Fade with distance below the beam, like the tail of a rain column.
        let depth = Double(row) / Double(rows - 1)
        for column in 0..<columns {
            // Gaps keep it reading as falling code rather than a filled grid.
            if random() < 0.18 { continue }
            let glyph = glyphs[Int(random() * Double(glyphs.count - 1))]
            // A few glyphs burn white-green: the head of a trail.
            let isHead = random() < 0.16
            let color =
                isHead
                ? phosphorHead
                : phosphor.over(readout, alpha: 0.95 - depth * 0.45 - random() * 0.2)
            let path = place(
                glyph,
                cx: pageMinX + textInset + (Double(column) + 0.5) * cellWidth,
                cy: splitY + pageHeight * 0.03 + (Double(row) + 0.5) * cellHeight
                    - columnOffsets[column],
                unit: unit)
            body.append("  <path d=\"\(path)\" stroke=\"\(color.hex)\"/>")
        }
    }
    body.append("</g>")
    return body
}

// MARK: Beam

func beamLayer() -> [String] {
    // Edge to edge: the system's shape is what ends it.
    let height = canvas * 0.055
    return [
        "<rect x=\"0\" y=\"\(n(splitY - height / 2))\" "
            + "width=\"\(n(canvas))\" height=\"\(n(height))\" fill=\"\(beam.hex)\"/>"
    ]
}

// MARK: Bundle

struct Layer {
    var name: String
    var body: [String]
    var shadow: [String: Any]
    /// A colour the whole layer takes in the dark appearance, in place of
    /// the ones in its SVG.
    var darkFill: RGB?
}

// Layers from front to back, the order icon.json lists them. All three are
// glass, which is what keeps the dark half of the page apart from a dark
// field. The beam's shadow and the digits' take their own colour, which
// stands in for the glow the flat icon painted around them. On the dark
// field the beam is the digits' green rather than cyan.
let layers = [
    Layer(
        name: "Beam", body: beamLayer(),
        shadow: ["kind": "layer-color", "opacity": 0.5], darkFill: phosphor),
    Layer(name: "Digits", body: digitsLayer(), shadow: ["kind": "layer-color", "opacity": 0.75]),
    Layer(name: "Page", body: pageLayer(), shadow: ["kind": "neutral", "opacity": 0.5]),
]

let assetsURL = outputURL.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
var groups: [[String: Any]] = []
for layer in layers {
    try svg(layer.body).write(
        to: assetsURL.appendingPathComponent(layer.name + ".svg"),
        atomically: true, encoding: .utf8)
    var entry: [String: Any] = ["image-name": layer.name + ".svg", "name": layer.name]
    if let darkFill = layer.darkFill {
        entry["fill-specializations"] = [
            ["appearance": "dark", "value": ["solid": darkFill.fill]]
        ]
    }
    groups.append([
        "layers": [entry],
        "shadow": layer.shadow,
        "translucency": ["enabled": false, "value": 0.5],
    ])
}
let document: [String: Any] = [
    "fill": ["linear-gradient": [fieldTop.fill, fieldBottom.fill]],
    "groups": groups,
    "supported-platforms": ["squares": "shared"],
]
var json = try JSONSerialization.data(
    withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
json.append(contentsOf: "\n".utf8)
try json.write(to: outputURL.appendingPathComponent("icon.json"))
print("Wrote \(outputURL.path)")
