import Foundation
import UIKit
import Vision
import Testing
@testable import EvictLib

/// VNClassifyImageRequest returns no observations on the simulator (no model there); it works on devices and Macs.
private let classifierAvailable: Bool = {
    let r = VNClassifyImageRequest()
    let img = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { _ in }.cgImage!
    try? VNImageRequestHandler(cgImage: img).perform([r])
    return !(r.results ?? []).isEmpty
}()

private func render(_ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }.cgImage!
}

@Test(.enabled(if: classifierAvailable, "Vision's classifier has no model on the simulator"))
func printedPageIsADocument() {
    let page = render(CGSize(width: 600, height: 800)) { c in
        UIColor(white: 0.97, alpha: 1).setFill()
        c.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        for i in 0..<28 {
            ("Lorem ipsum dolor sit amet, consectetur adipiscing elit \(i)" as NSString)
                .draw(at: CGPoint(x: 40, y: 30 + i * 25), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
    }
    #expect(Insights.inspect(page, modified: nil).document)
}

@Test func blackFrameIsDark() {
    let dark = render(CGSize(width: 400, height: 400)) { c in
        UIColor(white: 0.02, alpha: 1).setFill()
        c.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
    }
    let i = Insights.inspect(dark, modified: nil)
    #expect(i.dark)
    #expect(!i.blurry)          // dark wins, never both
}

@Test func featurelessFrameIsBlurryButDetailIsNot() {
    let flat = render(CGSize(width: 400, height: 400)) { c in
        UIColor(white: 0.5, alpha: 1).setFill()
        c.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
    }
    #expect(Insights.inspect(flat, modified: nil).blurry)

    let detail = render(CGSize(width: 400, height: 400)) { c in
        for x in stride(from: 0, to: 400, by: 4) {
            for y in stride(from: 0, to: 400, by: 4) {
                UIColor(white: CGFloat((x * 7 + y * 13) % 255) / 255, alpha: 1).setFill()
                c.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
    }
    let i = Insights.inspect(detail, modified: nil)
    #expect(!i.blurry)
    #expect(!i.dark)
}

@Test func smallThumbnailsAreNeverJudgedBlurry() {
    let tiny = render(CGSize(width: 120, height: 120)) { c in
        UIColor(white: 0.5, alpha: 1).setFill()
        c.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
    }
    #expect(!Insights.inspect(tiny, modified: nil).blurry)
}

@Test func screenRecordingsAreCompressible() {
    let c = Compression()
    #expect(c.gain(Item(id: "rec", kind: .recording, size: 400_000_000, duration: 60)) == 340_000_000)
}
