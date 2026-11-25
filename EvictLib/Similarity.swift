import Foundation
import Photos
import Vision
import Accelerate
import AVFoundation

struct SimilaritySettings: Equatable {
    var window: Double = 3          // seconds, 0 = scan the whole library
    var exact = 1.0                 // dHash threshold
    var similar = 0.9               // Vision threshold
    var videos = false              // 3 keyframes per video
}

/// Fingerprint of an item: one entry per frame (1 for a photo, 3 for a video).
struct Print: Codable {
    var modified: Date?
    var hashes: [UInt64]            // 64-bit dHash
    var vector: Data                // Vision feature prints (768 normalized Floats per frame), concatenated
    var sharpness: Float            // variance of the Laplacian
    var faces: Float?               // best face capture quality
}

struct Cluster: Identifiable {
    let id: String
    let members: [String]
    let keep: Set<String>           // best item + favorites and album items
    let similarity: Double

    func pruned(to assets: [String: PHAsset]) -> Cluster? {
        let m = members.filter { assets[$0] != nil }
        return m.count > 1 ? Cluster(id: id, members: m, keep: keep, similarity: similarity) : nil
    }
}

enum Similarity {
    /// Native bursts, grouped by burstIdentifier; frames picked by iOS or the user are kept.
    static func bursts(_ items: [Item]) -> [Cluster] {
        Dictionary(grouping: items.filter { $0.burstID != nil }) { $0.burstID! }
            .compactMap { id, frames -> Cluster? in
                guard frames.count > 1 else { return nil }
                let ordered = frames.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                let picks = frames.filter { $0.burstPick || $0.isProtected }.map(\.id)
                return Cluster(id: id, members: ordered.map(\.id), keep: Set(picks.isEmpty ? [ordered[0].id] : picks), similarity: 1)
            }
            .sorted { $0.members.count > $1.members.count }
    }

    /// Time window → missing fingerprints → pairs (exact dHash OR similar Vision print) → union-find → clusters.
    /// Returns nil clusters when cancelled; computed fingerprints are always returned for the cache.
    // Measured on revision 2 prints: re-encode ≈ 0.02, same scene slightly moved 0.09–0.26, different scenes 0.6–1.0
    // (Euclidean distance). The dHash can't tell "slightly moved" from "different", so it only flags exact duplicates.
    static func analyze(_ items: [Item], _ assets: [String: PHAsset], _ s: SimilaritySettings,
                        cache: [String: Print], progress: @escaping (Double) -> Void) async -> ([Cluster]?, [String: Print]) {
        let cands = items
            .filter { $0.date != nil && ([.photo, .live, .screenshot].contains($0.kind) || (s.videos && $0.kind == .video)) }
            .sorted { $0.date! < $1.date! }
        let n = cands.count

        // 1. Time window: only neighbors less than N seconds apart are compared.
        var windowPairs: [(Int, Int)] = []
        var needed = Set<Int>()
        if s.window > 0 {
            for i in 0..<n {
                var j = i + 1
                while j < n, cands[j].date!.timeIntervalSince(cands[i].date!) <= s.window {
                    windowPairs.append((i, j)); needed.insert(i); needed.insert(j); j += 1
                }
            }
        } else {
            needed = Set(0..<n)
        }

        // 2. Missing fingerprints, one at a time: the analysis runs while the app is used, so it must stay light.
        var prints = cache.filter { assets[$0.key] != nil }
        let missing = needed.map { cands[$0] }
            .filter { item in prints[item.id].map { $0.modified != assets[item.id]?.modificationDate } ?? true }
            .compactMap { assets[$0.id] }
        trace("similar: \(n) candidates, \(needed.count) in pairs, \(missing.count) fingerprints to compute")
        for (done, a) in missing.enumerated() {
            if Task.isCancelled { return (nil, prints) }
            prints[a.localIdentifier] = await makePrint(a)
            if done % 10 == 0 { progress(Double(done) / Double(missing.count)) }
        }

        // 3. Similar pairs.
        let P = cands.map { prints[$0.id] }
        func sim(_ i: Int, _ j: Int) -> Double? {
            guard (cands[i].kind == .video) == (cands[j].kind == .video),
                  let a = P[i], let b = P[j], a.hashes.count == b.hashes.count, !a.hashes.isEmpty else { return nil }
            let frames = Double(a.hashes.count)
            let h = zip(a.hashes, b.hashes).reduce(0.0) { $0 + 1 - Double(($1.0 ^ $1.1).nonzeroBitCount) / 64 } / frames
            let v = Double(dot(a.vector, b.vector)) / frames      // mean cosine similarity
            if h >= s.exact { return max(h, v) }
            return v >= s.similar ? v : nil
        }
        var edges: [(Int, Int, Double)] = []
        if s.window > 0 {
            edges = windowPairs.compactMap { p in sim(p.0, p.1).map { (p.0, p.1, $0) } }
        } else {
            // ponytail: global scan is O(n²) (~200M pairs for 20k photos), spread across cores.
            let rows = UnsafeMutableBufferPointer<[(Int, Int, Double)]>.allocate(capacity: n)
            rows.initialize(repeating: [])
            defer { _ = rows.deinitialize(); rows.deallocate() }
            let out = Unchecked(rows)       // each iteration writes its own slot
            DispatchQueue.concurrentPerform(iterations: n) { i in
                var row: [(Int, Int, Double)] = []
                for j in (i + 1)..<n { if let v = sim(i, j) { row.append((i, j, v)) } }
                out.value[i] = row
            }
            edges = rows.flatMap { $0 }
        }

        // 4. Union-find, then the best item of each cluster.
        var parent = Array(0..<n)
        var minSim: [Int: Double] = [:]
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for (i, j, v) in edges {
            let (ri, rj) = (find(i), find(j))
            let m = min(minSim[ri] ?? 1, minSim[rj] ?? 1, v)
            if ri != rj { parent[ri] = rj }
            minSim[rj] = m
        }
        var comps: [Int: [Int]] = [:]
        for (i, _, _) in edges { comps[find(i), default: []].append(i) }
        for (_, j, _) in edges { comps[find(j), default: []].append(j) }

        let clusters = comps.map { root, raw -> Cluster in
            let members = Array(Set(raw)).sorted()
            let winner = best(members.map { (cands[$0], P[$0]) })
            let keep = Set([winner] + members.map { cands[$0] }.filter(\.isProtected).map(\.id))
            return Cluster(id: winner, members: members.map { cands[$0].id }, keep: keep, similarity: minSim[root] ?? 1)
        }
        let size = Dictionary(uniqueKeysWithValues: cands.map { ($0.id, $0.size) })
        let gain = { (g: Cluster) in g.members.filter { !g.keep.contains($0) }.reduce(Int64(0)) { $0 + (size[$1] ?? 0) } }
        return (clusters.sorted { gain($0) > gain($1) }, prints)
    }

    /// Favorite first, then sharpness, face quality, resolution, edited.
    // ponytail: weighted score instead of a strict lexicographic sort (two sharpness values are never exactly equal).
    static func best(_ members: [(Item, Print?)]) -> String {
        let maxSharp = max(members.compactMap { $0.1?.sharpness }.max() ?? 1, 1e-6)
        let maxPixels = Double(max(members.map { $0.0.width * $0.0.height }.max() ?? 1, 1))
        func score(_ m: (Item, Print?)) -> Double {
            (m.0.isFavorite ? 10 : 0)
                + Double((m.1?.sharpness ?? 0) / maxSharp)
                + Double(m.1?.faces ?? 0) * 0.8
                + Double(m.0.width * m.0.height) / maxPixels * 0.3
                + (m.0.edited ? 0.2 : 0)
        }
        return members.max { score($0) < score($1) }!.0.id
    }

    static func dot(_ a: Data, _ b: Data) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var r: Float = 0
        a.withUnsafeBytes { pa in b.withUnsafeBytes { pb in
            vDSP_dotpr(pa.bindMemory(to: Float.self).baseAddress!, 1, pb.bindMemory(to: Float.self).baseAddress!, 1,
                       &r, vDSP_Length(a.count / MemoryLayout<Float>.size))
        } }
        return r
    }

    // MARK: Fingerprints

    /// Vision runs synchronously; keep it off Swift's cooperative threads so the rest of the app never waits on it.
    static let visionQueue = DispatchQueue(label: "com.joffroy.evictlib.vision", qos: .utility)

    static func makePrint(_ a: PHAsset) async -> Print? {
        var frames: [CGImage] = []
        if a.mediaType == .video {
            frames = await videoFrames(a)
        } else if let img = await image(a) {
            frames = [img]
        } else if let img = await image(a, network: true) {
            frames = [img]
        }
        guard !frames.isEmpty else { return nil }
        let modified = a.modificationDate
        return await withCheckedContinuation { c in
            visionQueue.async { c.resume(returning: fingerprint(frames, modified: modified)) }
        }
    }

    // ponytail: no face-quality pass here (it doubled the cost); best() ranks on favorite, sharpness, resolution, edits.
    private static func fingerprint(_ frames: [CGImage], modified: Date?) -> Print? {
        var print = Print(modified: modified, hashes: [], vector: Data(), sharpness: 0, faces: nil)
        for f in frames {
            let fp = VNGenerateImageFeaturePrintRequest()
            fp.revision = VNGenerateImageFeaturePrintRequestRevision2
            try? VNImageRequestHandler(cgImage: f).perform([fp])
            guard let o = fp.results?.first, o.elementType == .float else { return nil }
            print.vector.append(o.data)
            print.hashes.append(dHash(f))
            print.sharpness += sharpness(f) / Float(frames.count)
        }
        return print
    }

    /// Without network: the small thumbnail Photos always keeps on device (instant, enough to fingerprint).
    /// With network: a real high-quality render, downloaded from iCloud if needed.
    static func image(_ a: PHAsset, side: CGFloat = 384, network: Bool = false) async -> CGImage? {
        let o = PHImageRequestOptions()
        o.deliveryMode = network ? .highQualityFormat : .fastFormat     // both call the handler exactly once
        o.isNetworkAccessAllowed = network
        o.resizeMode = .fast
        return await withCheckedContinuation { c in
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFit, options: o) { img, _ in c.resume(returning: img?.cgImage) }
        }
    }

    static func videoFrames(_ a: PHAsset) async -> [CGImage] {
        guard let av = try? await Transformer.avAsset(a, original: false) else { return [] }
        let g = AVAssetImageGenerator(asset: av)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 384, height: 384)
        var out: [CGImage] = []
        for f in [0.25, 0.5, 0.75] {
            if let r = try? await g.image(at: CMTime(seconds: a.duration * f, preferredTimescale: 600)) { out.append(r.image) }
        }
        return out.count == 3 ? out : []
    }

    /// dHash: 9×8 grayscale thumbnail, one bit per horizontal comparison.
    static func dHash(_ img: CGImage) -> UInt64 {
        let px = gray(img, 9, 8)
        var h: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 { h = h << 1 | (px[y * 9 + x] < px[y * 9 + x + 1] ? 1 : 0) } }
        return h
    }

    /// Variance of the Laplacian on a 256×256 thumbnail: higher means sharper.
    static func sharpness(_ img: CGImage) -> Float {
        let w = 256
        let px = gray(img, w, w).map(Float.init)
        var sum: Float = 0, sum2: Float = 0
        for y in 1..<(w - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let l = px[i - 1] + px[i + 1] + px[i - w] + px[i + w] - 4 * px[i]
                sum += l; sum2 += l * l
            }
        }
        let count = Float((w - 2) * (w - 2))
        return sum2 / count - (sum / count) * (sum / count)
    }

    /// Mean luminance 0–255 on a 64×64 thumbnail.
    static func luminance(_ img: CGImage) -> Float {
        let px = gray(img, 64, 64)
        return Float(px.reduce(0) { $0 + Int($1) }) / Float(px.count)
    }

    static func gray(_ img: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h)
        px.withUnsafeMutableBytes { buf in
            let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            c.interpolationQuality = .medium
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return px
    }
}

/// What a photo is, from its local thumbnail: a document or receipt, too dark, or too blurry.
struct Insight: Codable {
    var modified: Date?
    var document = false
    var dark = false
    var blurry = false
}

enum Insights {
    // Vision's own classes for paper. Measured: a printed page scores 0.35–0.54, landscapes under 0.001.
    static let paper: Set<String> = ["document", "receipt", "printed_page", "handwriting", "newspaper", "ticket",
                                     "whiteboard", "sticky_note", "checkbook"]

    static func inspect(_ a: PHAsset) async -> Insight? {
        guard let img = await Similarity.image(a) else { return nil }
        let modified = a.modificationDate
        return await withCheckedContinuation { c in
            Similarity.visionQueue.async { c.resume(returning: inspect(img, modified: modified)) }
        }
    }

    // Measured on 256 px: sharp photos 520–2,600, heavy blur 2–8; pocket shots average 14–27 out of 255.
    // ponytail: fixed thresholds, conservative on purpose; nothing is pre-selected, so a miss costs nothing.
    static func inspect(_ img: CGImage, modified: Date?) -> Insight {
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: img).perform([request])
        let document = (request.results ?? []).contains { paper.contains($0.identifier) && $0.confidence >= 0.3 }
        let mean = Similarity.luminance(img)
        let judgeable = min(img.width, img.height) >= 200          // smaller thumbnails look blurry anyway
        let blurry = judgeable && mean >= 15 && Similarity.sharpness(img) < 15
        return Insight(modified: modified, document: document, dark: mean < 15, blurry: blurry)
    }
}
