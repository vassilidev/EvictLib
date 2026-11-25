import Foundation
import Photos
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Hands a non-Sendable value to a PhotoKit / AVFoundation callback that requires one.
final class Unchecked<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// The only service (besides the basket delete) that writes to the library.
/// PhotoKit can't change an asset's resources: we create a new asset, verify it,
/// and only then delete the original, inside the basket's batched delete.
enum Transformer {
    enum Failure: LocalizedError {
        case noResource, noGain, verify, export(String)
        var errorDescription: String? {
            switch self {
            case .noResource: "resource not found"
            case .noGain: "no savings"
            case .verify: "new item failed verification"
            case .export(let m): "export: \(m)"
            }
        }
    }

    static func name(_ a: PHAsset) -> String {
        PHAssetResource.assetResources(for: a).first?.originalFilename ?? a.localIdentifier
    }

    /// Still kept when converting a Live Photo: the rendered edit if any, otherwise the original.
    static func stillResource(_ res: [PHAssetResource]) -> PHAssetResource? {
        res.first { $0.type == .fullSizePhoto } ?? res.first { $0.type == .photo }
    }

    /// A replacement file ready to be added to the library, already verified.
    struct Prepared {
        let original: PHAsset
        let file: URL
        let type: PHAssetResourceType
        let name: String
        let bytes: Int64
        let albums: [PHAssetCollection]
    }

    /// Creates the replacement (date, location, favorite, hidden, albums, EXIF), verifies it, returns its id and size.
    static func replace(_ asset: PHAsset, _ action: Action, requireGain: Bool = true) async throws -> (id: String, size: Int64) {
        let p = try await prepare(asset, action, requireGain: requireGain)
        guard let created = try await create([p])[asset.localIdentifier] else { throw Failure.verify }
        return created
    }

    /// Renders and verifies the replacement file (size, savings, duration) without touching the library.
    static func prepare(_ asset: PHAsset, _ action: Action, requireGain: Bool = true) async throws -> Prepared {
        let (file, type) = try await render(asset, action)
        let fileBytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let resources = PHAssetResource.assetResources(for: asset)
        let original = resources.reduce(0) { $0 + $1.bytes }
        guard fileBytes > 0 else { throw Failure.verify }
        if requireGain, case .compress = action, fileBytes > original * 9 / 10 {
            try? FileManager.default.removeItem(at: file)
            throw Failure.noGain
        }
        if type == .video {
            // Same duration, except slow-mo brought back to normal speed (shorter by design).
            let d = try await AVURLAsset(url: file).load(.duration).seconds
            var normalSpeed = false
            if case .compress(let c) = action { normalSpeed = c.normalSpeed && asset.mediaSubtypes.contains(.videoHighFrameRate) }
            guard d > 0, normalSpeed || abs(d - asset.duration) < 1 else { throw Failure.verify }
        }
        let base = resources.first { $0.type == .photo || $0.type == .video }?.originalFilename ?? "IMG"
        let name = (base.split(separator: ".").first.map(String.init) ?? "IMG") + "." + file.pathExtension
        var albums: [PHAssetCollection] = []
        PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            .enumerateObjects { album, _, _ in if album.canPerform(.addContent) { albums.append(album) } }
        return Prepared(original: asset, file: file, type: type, name: name, bytes: fileBytes, albums: albums)
    }

    /// Adds a batch of replacements in one library transaction: original id → new id and size.
    /// The transaction is atomic: either every item of the batch exists afterwards, or none does.
    static func create(_ batch: [Prepared]) async throws -> [String: (id: String, size: Int64)] {
        let created = Unchecked<[String: String]>([:])
        try await PHPhotoLibrary.shared().performChanges {
            var byAlbum: [String: (album: PHAssetCollection, items: [PHObjectPlaceholder])] = [:]
            for p in batch {
                let req = PHAssetCreationRequest.forAsset()
                let o = PHAssetResourceCreationOptions()
                o.originalFilename = p.name
                o.shouldMoveFile = true
                req.addResource(with: p.type, fileURL: p.file, options: o)
                req.creationDate = p.original.creationDate
                req.location = p.original.location
                req.isFavorite = p.original.isFavorite
                req.isHidden = p.original.isHidden
                guard let ph = req.placeholderForCreatedAsset else { continue }
                created.value[p.original.localIdentifier] = ph.localIdentifier
                for album in p.albums { byAlbum[album.localIdentifier, default: (album, [])].items.append(ph) }
            }
            // One change request per album, however many items of the batch join it.
            for (_, entry) in byAlbum { PHAssetCollectionChangeRequest(for: entry.album)?.addAssets(entry.items as NSArray) }
        }
        // Files were verified before creation. Past this point never throw: the new items exist,
        // and a retry would duplicate them. A size can read 0 right after creation, so fall back to the file.
        var assets: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: Array(created.value.values), options: nil)
            .enumerateObjects { a, _, _ in assets[a.localIdentifier] = a }
        var out: [String: (id: String, size: Int64)] = [:]
        for p in batch {
            guard let id = created.value[p.original.localIdentifier] else { continue }
            let size = assets[id].map { PHAssetResource.assetResources(for: $0).reduce(0) { $0 + $1.bytes } } ?? 0
            out[p.original.localIdentifier] = (id, size > 0 ? size : p.bytes)
        }
        return out
    }

    /// Writes the replacement file to tmp.
    static func render(_ asset: PHAsset, _ action: Action) async throws -> (URL, PHAssetResourceType) {
        switch action {
        case .delete:
            throw Failure.noResource
        case .still:
            guard let r = stillResource(PHAssetResource.assetResources(for: asset)) else { throw Failure.noResource }
            return (try await download(r), .photo)
        case .compress(let c) where asset.mediaType == .video:
            return (try await compressVideo(asset, c), .video)
        case .compress(let c):
            guard let r = stillResource(PHAssetResource.assetResources(for: asset)) else { throw Failure.noResource }
            let src = try await download(r)
            defer { try? FileManager.default.removeItem(at: src) }
            return (try heic(src, maxSide: c.photoMaxSide), .photo)
        }
    }

    static func download(_ r: PHAssetResource) async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString + "-" + r.originalFilename)
        let o = PHAssetResourceRequestOptions()
        o.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: r, toFile: url, options: o)
        return url
    }

    // MARK: Photos → HEIC (JPEG, PNG, ProRAW/DNG)

    static func heic(_ src: URL, maxSide: Int?) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else { throw Failure.noResource }
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let image: CGImage?
        if let t = CGImageSourceGetType(source) as String?, UTType(t)?.conforms(to: .rawImage) == true,
           let raw = CIRAWFilter(imageURL: src) {
            if let maxSide, let size = raw.outputImage?.extent.size {
                raw.scaleFactor = Float(min(1, CGFloat(maxSide) / max(size.width, size.height)))
            }
            image = raw.outputImage.flatMap { CIContext().createCGImage($0, from: $0.extent) }
            props[kCGImagePropertyOrientation] = 1      // RAW render is already upright
        } else if let maxSide {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
            props[kCGImagePropertyOrientation] = 1
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw Failure.noResource }

        let dst = URL.temporaryDirectory.appending(path: UUID().uuidString + ".heic")
        guard let dest = CGImageDestinationCreateWithURL(dst as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw Failure.export("HEIC unavailable")
        }
        props[kCGImageDestinationLossyCompressionQuality] = 0.8
        CGImageDestinationAddImage(dest, image, props as CFDictionary)   // EXIF, GPS, TIFF carried over
        guard CGImageDestinationFinalize(dest) else { throw Failure.export("HEIC write failed") }
        return dst
    }

    // MARK: Videos → HEVC

    /// Progress of the long steps (iCloud download, encoding) while a cleanup runs: step name and fraction.
    static var onStep: ((_ step: String, _ fraction: Double) -> Void)?

    static func avAsset(_ a: PHAsset, original: Bool, progress: ((Double) -> Void)? = nil) async throws -> AVAsset {
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .highQualityFormat
        o.version = original ? .original : .current
        if let progress { o.progressHandler = { p, _, _, _ in progress(p) } }
        return try await withCheckedThrowingContinuation { c in
            PHImageManager.default().requestAVAsset(forVideo: a, options: o) { av, _, info in
                if let av { c.resume(returning: av) }
                else { c.resume(throwing: (info?[PHImageErrorKey] as? Error) ?? Failure.noResource) }
            }
        }
    }

    static func compressVideo(_ asset: PHAsset, _ c: Compression) async throws -> URL {
        let normalSpeed = c.normalSpeed && asset.mediaSubtypes.contains(.videoHighFrameRate)
        // A slow-mo's .original is the raw 120/240 fps file without the slow ramp: played at 30 fps it's normal speed.
        let step = onStep
        let av = try await avAsset(asset, original: normalSpeed) { step?("Downloading from iCloud", $0) }
        guard let s = AVAssetExportSession(asset: av, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw Failure.export("HEVC unavailable")
        }
        s.videoComposition = try await composition(av, shortSide: c.preset.shortSide, maxFPS: normalSpeed ? 30 : nil)
        s.metadata = try await av.load(.metadata)
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString + ".mov")
        let session = Unchecked(s)
        step?("Encoding", 0)
        let poll = Task {
            while !Task.isCancelled {
                step?("Encoding", Double(session.value.progress))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { poll.cancel() }
        try await withTaskCancellationHandler {
            if #available(iOS 18, *) {
                try await s.export(to: url, as: .mov)
            } else {
                s.outputURL = url
                s.outputFileType = .mov
                await s.export()
                if let e = s.error { throw e }
            }
        } onCancel: { session.value.cancelExport() }
        return url
    }

    /// Scales down to the target short side (keeping orientation) and caps the frame rate if asked.
    /// The source color properties (HDR, HLG) are kept.
    static func composition(_ av: AVAsset, shortSide: CGFloat, maxFPS: Float?) async throws -> AVVideoComposition {
        guard let track = try await av.loadTracks(withMediaType: .video).first else { throw Failure.noResource }
        let (natural, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let comp = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: av)
        let oriented = CGRect(origin: .zero, size: natural).applying(transform).size
        let (w, h) = (abs(oriented.width), abs(oriented.height))
        let scale = min(1, shortSide / min(w, h))
        let even = { (v: CGFloat) in (v * scale / 2).rounded() * 2 }
        comp.renderSize = CGSize(width: even(w), height: even(h))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await av.load(.duration))
        instruction.layerInstructions = [layer]
        comp.instructions = [instruction]
        if let maxFPS, fps > maxFPS { comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(maxFPS)) }
        return comp
    }

    // MARK: Before / after preview

    static func frame(_ av: AVAsset) async -> CGImage? {
        let g = AVAssetImageGenerator(asset: av)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 1200, height: 1200)
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = .zero
        guard let d = try? await av.load(.duration) else { return nil }
        return try? await g.image(at: CMTime(seconds: d.seconds / 2, preferredTimescale: 600)).image
    }

    /// Renders one item without touching the library: before/after frames at the same instant, and the real size.
    static func preview(_ asset: PHAsset, _ c: Compression) async throws -> (before: CGImage?, after: CGImage?, size: Int64) {
        let (url, _) = try await render(asset, .compress(c))
        defer { try? FileManager.default.removeItem(at: url) }
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if asset.mediaType == .video {
            let before = await frame(try await avAsset(asset, original: false))
            return (before, await frame(AVURLAsset(url: url)), size)
        }
        let after = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap {
            CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                        kCGImageSourceThumbnailMaxPixelSize: 1200,
                                                        kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        }
        return (await Similarity.image(asset, side: 1200, network: true), after, size)
    }
}
