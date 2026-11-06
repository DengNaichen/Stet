// Run from the repository root: swift scripts/generate-menu-bar-icon.swift
// Hand-drawn voice gesture; coordinates use a top-left origin.
import Foundation
import CoreGraphics

let output = CommandLine.arguments.dropFirst().first
    ?? "StetMac/Assets.xcassets/menuBarIcon.imageset/menuBarIcon.pdf"
var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
guard let context = CGContext(
    URL(fileURLWithPath: output) as CFURL, mediaBox: &bounds, nil
) else {
    fatalError("Cannot create menu bar icon PDF at \(output)")
}

// Broad rising stroke, a narrow falling stroke, then a smaller trailing wave.
// The closed outline keeps the changing pen pressure independent of stroke scaling.
let outline = CGMutablePath()
outline.move(to: CGPoint(x: 18, y: 145))
outline.addCurve(to: CGPoint(x: 101, y: 47), control1: CGPoint(x: 48, y: 137), control2: CGPoint(x: 69, y: 76))
outline.addCurve(to: CGPoint(x: 167, y: 0), control1: CGPoint(x: 124, y: 24), control2: CGPoint(x: 146, y: 0))
outline.addCurve(to: CGPoint(x: 205, y: 37), control1: CGPoint(x: 190, y: -2), control2: CGPoint(x: 200, y: 12))
outline.addCurve(to: CGPoint(x: 233, y: 126), control1: CGPoint(x: 213, y: 64), control2: CGPoint(x: 211, y: 123))
outline.addCurve(to: CGPoint(x: 285, y: 91), control1: CGPoint(x: 249, y: 131), control2: CGPoint(x: 268, y: 101))
outline.addCurve(to: CGPoint(x: 327, y: 72), control1: CGPoint(x: 300, y: 78), control2: CGPoint(x: 310, y: 70))
outline.addCurve(to: CGPoint(x: 366, y: 100), control1: CGPoint(x: 345, y: 72), control2: CGPoint(x: 363, y: 86))
outline.addCurve(to: CGPoint(x: 354, y: 115), control1: CGPoint(x: 374, y: 118), control2: CGPoint(x: 361, y: 119))
outline.addCurve(to: CGPoint(x: 324, y: 105), control1: CGPoint(x: 342, y: 112), control2: CGPoint(x: 337, y: 103))
outline.addCurve(to: CGPoint(x: 268, y: 147), control1: CGPoint(x: 306, y: 105), control2: CGPoint(x: 290, y: 134))
outline.addCurve(to: CGPoint(x: 229, y: 168), control1: CGPoint(x: 253, y: 160), control2: CGPoint(x: 245, y: 170))
outline.addCurve(to: CGPoint(x: 196, y: 138), control1: CGPoint(x: 210, y: 169), control2: CGPoint(x: 203, y: 157))
outline.addCurve(to: CGPoint(x: 179, y: 69), control1: CGPoint(x: 187, y: 115), control2: CGPoint(x: 190, y: 81))
outline.addCurve(to: CGPoint(x: 151, y: 56), control1: CGPoint(x: 172, y: 52), control2: CGPoint(x: 163, y: 48))
outline.addCurve(to: CGPoint(x: 91, y: 127), control1: CGPoint(x: 130, y: 65), control2: CGPoint(x: 111, y: 101))
outline.addCurve(to: CGPoint(x: 29, y: 190), control1: CGPoint(x: 66, y: 160), control2: CGPoint(x: 51, y: 190))
outline.addCurve(to: CGPoint(x: 1, y: 173), control1: CGPoint(x: 11, y: 195), control2: CGPoint(x: 0, y: 185))
outline.addCurve(to: CGPoint(x: 18, y: 145), control1: CGPoint(x: -4, y: 155), control2: CGPoint(x: 4, y: 150))
outline.closeSubpath()

context.beginPDFPage(nil)
context.translateBy(x: 0.6, y: 13.5)
context.scaleBy(x: 16.8 / 368, y: -16.8 / 368)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.addPath(outline)
context.fillPath()
context.endPDFPage()
context.closePDF()
