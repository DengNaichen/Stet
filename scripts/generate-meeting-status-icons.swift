// Run from the repository root: swift scripts/generate-meeting-status-icons.swift
// Custom 18-point menu-bar glyphs, drawn in a top-left coordinate system.
// Keep these static: meeting status must not add an animation timer to audio capture.
import CoreGraphics
import Foundation

func recordingGesture() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 1.2, y: 9.5))
    path.addCurve(to: CGPoint(x: 3.5, y: 5.5), control1: CGPoint(x: 2.4, y: 9.5), control2: CGPoint(x: 2.5, y: 5.5))
    path.addCurve(to: CGPoint(x: 5.6, y: 13.5), control1: CGPoint(x: 4.6, y: 5.5), control2: CGPoint(x: 4.5, y: 13.5))
    path.addCurve(to: CGPoint(x: 8.1, y: 3.5), control1: CGPoint(x: 6.9, y: 13.5), control2: CGPoint(x: 6.8, y: 3.5))
    path.addCurve(to: CGPoint(x: 10.4, y: 12), control1: CGPoint(x: 9.4, y: 3.5), control2: CGPoint(x: 9.2, y: 12))
    path.addCurve(to: CGPoint(x: 12.6, y: 8), control1: CGPoint(x: 11.5, y: 12), control2: CGPoint(x: 11.7, y: 8))
    return path
}

func processingGesture() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 1.2, y: 10.5))
    path.addCurve(to: CGPoint(x: 4.4, y: 5.8), control1: CGPoint(x: 2.3, y: 10.5), control2: CGPoint(x: 3.1, y: 5.8))
    path.addCurve(to: CGPoint(x: 6.2, y: 11.8), control1: CGPoint(x: 5.5, y: 5.8), control2: CGPoint(x: 5.0, y: 11.8))
    path.addCurve(to: CGPoint(x: 8.8, y: 9), control1: CGPoint(x: 7.2, y: 11.8), control2: CGPoint(x: 7.7, y: 9))
    return path
}

for (name, gesture) in [
    ("meetingRecordingIcon", recordingGesture()),
    ("meetingProcessingIcon", processingGesture()),
] {
    let output = "StetMac/Assets.xcassets/\(name).imageset/\(name).pdf"
    var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
    guard let context = CGContext(URL(fileURLWithPath: output) as CFURL, mediaBox: &bounds, nil) else {
        fatalError("Cannot create \(output)")
    }
    context.beginPDFPage(nil)
    context.translateBy(x: 0, y: 18)
    context.scaleBy(x: 1, y: -1)
    let ink = name == "meetingRecordingIcon"
        ? CGColor(red: 1, green: 0.23, blue: 0.27, alpha: 1)
        : CGColor(gray: 0, alpha: 1)
    context.setStrokeColor(ink)
    context.setFillColor(ink)
    context.setLineWidth(1.65)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(gesture)
    context.strokePath()
    if name == "meetingRecordingIcon" {
        context.fillEllipse(in: CGRect(x: 14.2, y: 7.4, width: 3.2, height: 3.2))
    } else {
        for x in [10.5, 13.1, 15.7] {
            context.fillEllipse(in: CGRect(x: x, y: 8.1, width: 1.8, height: 1.8))
        }
    }
    context.endPDFPage()
    context.closePDF()
}
