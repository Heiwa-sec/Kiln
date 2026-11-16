import Testing
import Foundation
import ImageIO
import PDFKit
@testable import KilnCore

@Suite struct OptionsTests {
    func props(_ u: URL) -> [CFString: Any] { CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(u as CFURL, nil)!, 0, nil) as! [CFString: Any] }
    func opts(_ f: Format, _ edit: (inout ImageSetting) -> Void) -> ConversionOptions {
        var o = ConversionOptions.standard; var s = o.image(f); edit(&s); o.setImage(f, s); return o
    }

    @Test func lowerJPEGQualityMakesASmallerFile() async throws {
        let s = try Scratch(); defer { s.remove() }
        let src = try s.noisePNG()
        let low = try await runJob(src, .png, .jpg, options: opts(.jpg) { $0.quality = 0.3 })[0]
        let high = try await runJob(src, .png, .jpg, options: opts(.jpg) { $0.quality = 1.0 })[0]
        #expect(fileSize(low) < fileSize(high) / 2, "\(fileSize(low)) vs \(fileSize(high))")
    }
    @Test func metadataIsKeptByDefaultAndDroppedOnRequest() async throws {
        let s = try Scratch(); defer { s.remove() }
        let src = try s.jpeg()
        let kept = try await runJob(src, .jpg, .tiff)[0]
        #expect(props(kept)[kCGImagePropertyGPSDictionary] != nil)
        let dropped = try await runJob(src, .jpg, .tiff, options: opts(.tiff) { $0.preserveMetadata = false })[0]
        #expect(props(dropped)[kCGImagePropertyGPSDictionary] == nil)
        #expect((props(dropped)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
    }
    @Test func maxDimensionScalesTheLongestSideDown() async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = try await runJob(try s.png(w: 200, h: 100), .png, .tiff, options: opts(.tiff) { $0.maxEdge = 50 })[0]
        #expect(props(r)[kCGImagePropertyPixelWidth] as? Int == 50 && props(r)[kCGImagePropertyPixelHeight] as? Int == 25)
    }
    @Test func smallerImagesAreNotUpscaled() async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = try await runJob(try s.png(w: 40, h: 30), .png, .tiff, options: opts(.tiff) { $0.maxEdge = 1000 })[0]
        #expect(props(r)[kCGImagePropertyPixelWidth] as? Int == 40)
    }
    @Test func pdfDPIChangesThePageImageSize() async throws {
        let s = try Scratch(); defer { s.remove() }
        var o = ConversionOptions.standard; o.pdfDPI = 150
        let folder = try await runJob(try s.pdf(), .pdf, .png, options: o)[0]
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(folder.appendingPathComponent("page-001.png") as CFURL, nil)!, 0, nil)!
        #expect(img.width == 417 && img.height == 208)   // 200x100 pt at 150 DPI
    }
    @Test func gifFrameRateAndLengthComeFromSettings() async throws {
        let s = try Scratch(); defer { s.remove() }
        var o = ConversionOptions.standard; o.gifFPS = 5
        let r = try await runJob(try await s.movie(seconds: 2), .mov, .gif, options: o)[0]
        #expect(CGImageSourceGetCount(CGImageSourceCreateWithURL(r as CFURL, nil)!) == 10)   // 2 s at 5 fps
        o.gifMaxSeconds = 1
        let short = try await runJob(try await s.movie("b.mov", seconds: 2), .mov, .gif, options: o)[0]
        #expect(CGImageSourceGetCount(CGImageSourceCreateWithURL(short as CFURL, nil)!) == 5)
    }
    @Test func aacBitrateChangesTheFileSize() async throws {
        let s = try Scratch(); defer { s.remove() }
        let src = try s.wav(seconds: 2)
        var lo = ConversionOptions.standard; lo.aacKbpsPerChannel = 32
        var hi = ConversionOptions.standard; hi.aacKbpsPerChannel = 128
        let a = try await runJob(src, .wav, .m4a, options: lo)[0], b = try await runJob(src, .wav, .m4a, options: hi)[0]
        #expect(fileSize(a) < fileSize(b), "\(fileSize(a)) vs \(fileSize(b))")
    }
    @Test func optionsSurviveJSONAndDefaultsAreSane() throws {
        var o = ConversionOptions.standard; o.pdfDPI = 600; o.videoQuality = .p720; o.setImage(.jpg, ImageSetting(quality: 0.5, preserveMetadata: false, maxEdge: 2048))
        #expect(try JSONDecoder().decode(ConversionOptions.self, from: JSONEncoder().encode(o)) == o)
        #expect(ConversionOptions.standard.image(.jpg).quality == 0.75 && ConversionOptions.standard.image(.png).quality == nil)
        #expect(ConversionOptions.standard.image(.png).preserveMetadata && ConversionOptions.standard.image(.png).maxEdge == nil)
    }
}
