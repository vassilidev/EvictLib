import Foundation
import Photos
import AVFoundation
import CoreLocation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import EvictLib

/// Metadata carried over on replacement, per asset type, against the real library (simulator).
/// Test items stay in the library: PhotoKit requires a confirmation to delete them.
@Suite(.serialized, .enabled(if: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized))
struct ReplaceTests {
    let date = Date(timeIntervalSince1970: 1_600_000_000)
    let place = CLLocation(latitude: 48.8566, longitude: 2.3522)

    @Test func jpegToHEIC() async throws {
        let original = try await makeAsset(try jpeg(), .photo)
        let (id, size) = try await Transformer.replace(original, .compress(Compression()), requireGain: false)
        let created = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject)
        expectSameMetadata(created, original, size)

        let photo = try #require(PHAssetResource.assetResources(for: created).first { $0.type == .photo })
        #expect(UTType(photo.uniformTypeIdentifier)?.conforms(to: .heic) == true)
        let file = try await Transformer.download(photo)
        let props = CGImageSourceCreateWithURL(file as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
        let exif = props?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifLensModel] as? String == "EvictLibTest")
    }

    @Test func videoToHEVC() async throws {
        let original = try await makeAsset(try await video(), .video)
        var c = Compression()
        c.preset = .hd
        let (id, size) = try await Transformer.replace(original, .compress(c), requireGain: false)
        let created = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject)
        expectSameMetadata(created, original, size)
        #expect(abs(created.duration - original.duration) < 0.5)
    }

    @Test func stillConversion() async throws {
        // A synthetic Live Photo isn't possible here: this checks the "keep only the photo" path.
        let original = try await makeAsset(try jpeg(), .photo)
        let (id, size) = try await Transformer.replace(original, .still)
        let created = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject)
        expectSameMetadata(created, original, size)
        #expect(!created.mediaSubtypes.contains(.photoLive))
    }

    @Test func batchOfThreeInOneTransaction() async throws {
        // Several items of the same album in one transaction: one album change request, every item verified.
        var originals: [PHAsset] = []
        for _ in 0..<3 { originals.append(try await makeAsset(try jpeg(), .photo)) }
        var prepared: [Transformer.Prepared] = []
        for a in originals { prepared.append(try await Transformer.prepare(a, .still)) }
        let created = try await Transformer.create(prepared)
        #expect(created.count == 3)
        for a in originals {
            let entry = try #require(created[a.localIdentifier])
            let new = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [entry.id], options: nil).firstObject)
            expectSameMetadata(new, a, entry.size)
        }
    }

    // MARK: Helpers

    private func expectSameMetadata(_ created: PHAsset, _ original: PHAsset, _ size: Int64) {
        #expect(size > 0)
        #expect(created.creationDate == original.creationDate)
        #expect(created.isFavorite)
        #expect(abs((created.location?.coordinate.latitude ?? 0) - place.coordinate.latitude) < 0.0001)
        var titles: [String] = []
        PHAssetCollection.fetchAssetCollectionsContaining(created, with: .album, options: nil)
            .enumerateObjects { a, _, _ in titles.append(a.localizedTitle ?? "") }
        #expect(titles.contains("EvictLib Tests"))
    }

    private func makeAsset(_ file: URL, _ type: PHAssetResourceType) async throws -> PHAsset {
        let id = Unchecked<String?>(nil)
        var existing: PHAssetCollection?
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { a, _, stop in if a.localizedTitle == "EvictLib Tests" { existing = a; stop.pointee = true } }
        let album = existing
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: type, fileURL: file, options: nil)
            req.creationDate = date
            req.location = place
            req.isFavorite = true
            let ph = req.placeholderForCreatedAsset!
            id.value = ph.localIdentifier
            let change = album.flatMap { PHAssetCollectionChangeRequest(for: $0) }
                ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "EvictLib Tests")
            change.addAssets([ph] as NSArray)
        }
        let newID = try #require(id.value)
        return try #require(PHAsset.fetchAssets(withLocalIdentifiers: [newID], options: nil).firstObject)
    }

    private func jpeg() throws -> URL {
        let (w, h) = (640, 480)
        var px = (0..<(w * h * 4)).map { _ in UInt8.random(in: 0...255) }
        let image = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString + ".jpg")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "EvictLibTest"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func video() async throws -> URL {
        let (w, h) = (320, 240)
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                         AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for f in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &buffer)
            let b = try #require(buffer)
            CVPixelBufferLockBaseAddress(b, [])
            memset(CVPixelBufferGetBaseAddress(b), Int32(f * 4), CVPixelBufferGetDataSize(b))
            CVPixelBufferUnlockBaseAddress(b, [])
            adaptor.append(b, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }
}
