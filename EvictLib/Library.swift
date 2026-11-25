import Foundation
import Photos
import UIKit

enum Kind: String, CaseIterable, Identifiable {
    case video = "Videos", recording = "Screen Recordings", photo = "Photos", live = "Live Photos",
         screenshot = "Screenshots", burst = "Bursts"
    var id: Self { self }

    init(_ a: PHAsset) {
        if a.mediaType == .video { self = a.mediaSubtypes.contains(.videoScreenRecording) ? .recording : .video }
        else if a.mediaSubtypes.contains(.photoScreenshot) { self = .screenshot }
        else if a.burstIdentifier != nil { self = .burst }
        else if a.mediaSubtypes.contains(.photoLive) { self = .live }
        else { self = .photo }
    }
}

struct Item: Identifiable {
    let id: String                  // PHAsset.localIdentifier
    let kind: Kind
    let size: Int64                 // sum of all PHAssetResources
    var liveGain: Int64 = 0         // Live Photo: everything but the still we keep
    var uti: String? = nil          // type of the original resource
    var edited = false
    var date: Date? = nil
    var duration: TimeInterval = 0
    var width = 0
    var height = 0
    var isFavorite = false
    var inAlbum = false
    var burstID: String? = nil
    var burstPick = false           // frame picked by iOS or the user
    var slowMo = false
    var app: String? = nil          // saved by WhatsApp, Telegram… (from that app's album)
    var isProtected: Bool { isFavorite || inAlbum }
    var isVideo: Bool { kind == .video || kind == .recording }
}

extension Item {
    init(_ a: PHAsset, _ m: Meta, inAlbum: Bool, app: String?) {
        self.init(id: a.localIdentifier, kind: Kind(a), size: m.size, liveGain: m.liveGain, uti: m.uti,
                  edited: m.edited, date: a.creationDate, duration: a.duration,
                  width: a.pixelWidth, height: a.pixelHeight, isFavorite: a.isFavorite, inAlbum: inAlbum,
                  burstID: a.burstIdentifier, burstPick: a.representsBurst || !a.burstSelectionTypes.isEmpty,
                  slowMo: a.mediaSubtypes.contains(.videoHighFrameRate), app: app)
    }
}

/// The expensive part of a scan (reading resources), cached by modification date.
struct Meta: Codable {
    var modified: Date?
    var size: Int64
    var liveGain: Int64
    var uti: String?
    var edited: Bool

    init(_ a: PHAsset) {
        let res = PHAssetResource.assetResources(for: a)
        size = res.reduce(0) { $0 + $1.bytes }
        liveGain = a.mediaSubtypes.contains(.photoLive) ? size - (Transformer.stillResource(res)?.bytes ?? size) : 0
        uti = res.first { $0.type == .photo || $0.type == .video }?.uniformTypeIdentifier
        edited = res.contains { $0.type == .adjustmentData }
        modified = a.modificationDate
    }
}

extension PHAssetResource {
    // ponytail: "fileSize" is an undocumented KVC key, the only way to read sizes without downloading originals.
    var bytes: Int64 { (value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0 }
}

struct Filter {
    var kind: Kind?
    var minSize: Int64 = 0
    var byDate = false
    var from = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
    var to = Date.now
    var includeProtected = false    // favorites and album items are excluded by default

    func matches(_ i: Item) -> Bool {
        if let kind, i.kind != kind { return false }
        if i.size < minSize { return false }
        if i.isProtected && !includeProtected { return false }
        if byDate {
            let cal = Calendar.current
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to))!
            guard let d = i.date, d >= cal.startOfDay(for: from), d < end else { return false }
        }
        return true
    }
}

enum Action: Codable, Hashable {
    case delete, still, compress(Compression)

    var isCompress: Bool { if case .compress = self { return true } else { return false } }

    var symbol: String {
        switch self {
        case .delete: "trash.circle.fill"
        case .still: "livephoto.slash"
        case .compress: "arrow.down.circle.fill"
        }
    }
}

struct Compression: Codable, Hashable {
    enum Preset: String, Codable, CaseIterable, Identifiable {
        case uhd = "4K", fhd = "1080p", hd = "720p"
        var id: Self { self }
        var shortSide: CGFloat { switch self { case .uhd: 2160; case .fhd: 1080; case .hd: 720 } }
        // ponytail: estimated HEVC bitrates (video + audio); recalibrate against real preview sizes.
        var bitrate: Double { switch self { case .uhd: 20e6; case .fhd: 8e6; case .hd: 4e6 } }
    }
    var preset = Preset.fhd
    var normalSpeed = false         // slow-mo → normal speed at 30 fps
    var photoMaxSide: Int?          // optional photo downscale

    /// Estimated savings; 0 when not worth compressing (video already under target bitrate, HEIC, etc.).
    func gain(_ i: Item) -> Int64 {
        let estimate: Double
        switch i.kind {
        case .video, .recording:
            guard i.duration > 0 else { return 0 }
            estimate = preset.bitrate * i.duration / 8
        case .photo, .screenshot:
            let ratio = switch i.uti {
            case "public.jpeg": 0.5
            case "public.png": 0.3
            case "com.adobe.raw-image": 0.12    // ProRAW / DNG
            default: 1.0
            }
            let side = Double(max(i.width, i.height, 1))
            let resize = photoMaxSide.map { min(1, Double($0) / side) } ?? 1
            estimate = Double(i.size) * ratio * resize * resize
        default:
            return 0
        }
        // Under 20% savings is not worth the quality loss.
        return estimate < Double(i.size) * 0.8 ? i.size - Int64(estimate) : 0
    }
}

struct Session: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let freed: Int64
    let count: Int
}

struct Report {
    var freed: Int64 = 0
    var count = 0
    var failures: [String] = []
    var cancelled = false
}

extension Sequence<Item> {
    var totalSize: Int64 { reduce(0) { $0 + $1.size } }
}

/// Printed to stdout so `xcrun devicectl device process launch --console` shows what happens on the phone.
func trace(_ message: String) { print("EvictLib:", message) }

extension Int64 {
    var fileSize: String { formatted(.byteCount(style: .file, spellsOutZero: false)) }
}

/// Binary plist persistence. Caches = can be recomputed, Application Support = must survive.
enum Store {
    static func url(_ name: String, cache: Bool) -> URL {
        (cache ? URL.cachesDirectory : URL.applicationSupportDirectory).appending(path: name)
    }
    static func load<T: Decodable>(_ name: String, cache: Bool = false) -> T? {
        try? PropertyListDecoder().decode(T.self, from: Data(contentsOf: url(name, cache: cache)))
    }
    static func save<T: Encodable>(_ value: T, _ name: String, cache: Bool = false) {
        let e = PropertyListEncoder()
        e.outputFormat = .binary
        try? FileManager.default.createDirectory(at: url("", cache: cache), withIntermediateDirectories: true)
        try? e.encode(value).write(to: url(name, cache: cache), options: .atomic)
    }
}

private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    let onChange: () -> Void
    init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}

@MainActor @Observable
final class Library {
    static let shared = Library()

    private(set) var items: [Item] = []             // largest first
    private(set) var byID: [String: Item] = [:]
    private(set) var assets: [String: PHAsset] = [:]
    private(set) var bursts: [Cluster] = []
    private(set) var progress: Double?              // library scan

    /// Work of the current cleanup, saved after every item so an interrupted run can be finished later.
    private(set) var pending: [String: Action] = Store.load("pending.plist") ?? [:]
    private(set) var replaced: [String: Int64] = Store.load("replaced.plist") ?? [:]   // original → size of its replacement
    private(set) var history: [Session] = Store.load("history.plist") ?? []
    var marked: Set<String> = Store.load("marked.plist") ?? [] { didSet { saveSoon() } }  // swiped left
    var kept: Set<String> = Store.load("kept.plist") ?? [] { didSet { saveSoon() } }      // swiped right

    var compression = Compression()
    var similarity = SimilaritySettings() { didSet { if similarity != oldValue { startSimilarAnalysis(after: .milliseconds(500)) } } }
    private(set) var similar: [Cluster]?            // nil until analyzed
    private(set) var analysis: Double?              // runs on its own, whatever screen is shown
    private var prints: [String: Print]?
    private var analysisTask: Task<Void, Never>?
    private var analysisRun = UUID()
    private(set) var insights: [String: Insight] = [:]     // documents, dark and blurry photos
    private(set) var insightProgress: Double?
    private var insightTask: Task<Void, Never>?
    private var analyzed: (items: Int, settings: SimilaritySettings)?  // what the current groups were computed from

    struct Busy {
        var title: String
        var detail = ""
        var progress: Double
        var long = false        // videos: worth telling the user to keep the app open
    }
    private(set) var busy: Busy?
    var report: Report?
    private var commitTask: Task<Void, Never>?
    private var observer: ChangeObserver?
    private var rescan = false

    private var saveTask: Task<Void, Never>?

    /// Saves shortly after the last change, so bursts of swipes write once.
    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { persist() }
        }
    }

    func persist() {
        Store.save(pending, "pending.plist")
        Store.save(replaced, "replaced.plist")
        Store.save(history, "history.plist")
        Store.save(marked, "marked.plist")
        Store.save(kept, "kept.plist")
    }

    // MARK: Scanner

    func scan() async {
        guard progress == nil, busy == nil else { rescan = true; return }
        if observer == nil {
            let o = ChangeObserver { Task { @MainActor in await Library.shared.scan() } }
            PHPhotoLibrary.shared().register(o)
            observer = o
        }
        progress = 0
        let (items, assets) = await Task.detached(priority: .userInitiated) {
            Self.load { p in Task { @MainActor in if self.progress != nil { self.progress = p } } }
        }.value
        self.items = items
        self.assets = assets
        byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        bursts = Similarity.bursts(items)
        similar = similar?.compactMap { $0.pruned(to: assets) }
        pending = pending.filter { assets[$0.key] != nil }
        replaced = replaced.filter { assets[$0.key] != nil }
        marked = marked.filter { assets[$0] != nil }
        progress = nil
        if rescan { rescan = false; await scan(); return }
        // Re-group only when something it depends on changed: avoids a re-run (and a flicker) on every iCloud sync tick.
        if analyzed?.items != items.count || analyzed?.settings != similarity { startSimilarAnalysis() }
    }

    /// Albums that apps create to save media into; they don't make their items protected.
    nonisolated static let appAlbums = ["WhatsApp", "Telegram", "Instagram", "Snapchat", "Messenger", "Signal", "TikTok",
                                        "Facebook", "Twitter", "X", "Threads", "Pinterest", "Viber", "WeChat", "LINE",
                                        "Discord", "Teams", "Slack", "CapCut", "VSCO", "Snapseed", "Lightroom"]

    nonisolated private static func load(progress: @escaping (Double) -> Void) -> ([Item], [String: PHAsset]) {
        let cached: [String: Meta] = Store.load("meta.plist", cache: true) ?? [:]
        var fresh: [String: Meta] = [:]

        // Albums protect their items, except the ones apps create on their own (WhatsApp, Telegram…).
        var inAlbum = Set<String>()
        var app: [String: String] = [:]
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { album, _, _ in
                let owner = album.localizedTitle.flatMap { title in appAlbums.first { $0.caseInsensitiveCompare(title) == .orderedSame } }
                PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { a, _, _ in
                    if let owner { app[a.localIdentifier] = owner } else { inAlbum.insert(a.localIdentifier) }
                }
            }

        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        let fetch = PHAsset.fetchAssets(with: options)
        var items: [Item] = []
        var assets: [String: PHAsset] = [:]
        items.reserveCapacity(fetch.count)
        fetch.enumerateObjects { a, i, _ in
            let id = a.localIdentifier
            let m = cached[id].flatMap { $0.modified == a.modificationDate ? $0 : nil } ?? Meta(a)
            fresh[id] = m
            items.append(Item(a, m, inAlbum: inAlbum.contains(id), app: app[id]))
            assets[id] = a
            if i % 500 == 0 { progress(Double(i) / Double(fetch.count)) }
        }
        Store.save(fresh, "meta.plist", cache: true)
        items.sort { $0.size > $1.size }
        return (items, assets)
    }

    // MARK: Savings

    func gain(_ id: String, _ action: Action) -> Int64 {
        guard let i = byID[id] else { return 0 }
        switch action {
        case .delete: return i.size - (replaced[id] ?? 0)
        case .still: return i.liveGain
        case .compress(let c): return c.gain(i)
        }
    }

    func gain(_ actions: [String: Action]) -> Int64 { actions.reduce(0) { $0 + gain($1.key, $1.value) } }

    /// Everything in a cluster except the best item, favorites and album items.
    func extras(_ g: Cluster) -> [String] { g.members.filter { !g.keep.contains($0) } }

    func gain(_ g: Cluster) -> Int64 { extras(g).reduce(0) { $0 + (byID[$1]?.size ?? 0) } }

    func setFavorite(_ id: String, _ on: Bool) async {
        guard let a = assets[id] else { return }
        try? await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest(for: a).isFavorite = on }
    }

    // MARK: Analyzer (similar items)

    /// Restarts the analysis (fingerprints are cached, so a restart only redoes the grouping).
    func startSimilarAnalysis(after delay: Duration = .zero) {
        analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { await analyzeSimilar() }
        }
    }

    private func analyzeSimilar() async {
        let run = UUID()
        analysisRun = run
        if prints == nil {
            prints = await Task.detached { Store.load("prints.plist", cache: true) ?? [:] }.value
        }
        analysis = 0
        trace("similar: analyzing \(items.count) items, window \(similarity.window)s")
        let (items, assets, settings, cache) = (items, assets, similarity, prints ?? [:])
        let started = Date.now
        let (groups, newPrints) = await Similarity.analyze(items, assets, settings, cache: cache) { p in
            Task { @MainActor in
                guard self.analysisRun == run else { return }
                let old = Int((self.analysis ?? 0) * 100), new = Int(p * 100)
                guard new != old else { return }
                if new / 10 != old / 10 { trace("similar: \(new)% after \(Int(Date.now.timeIntervalSince(started)))s") }
                self.analysis = p
            }
        }
        trace("similar: \(groups.map { "\($0.count) groups" } ?? "cancelled"), \(newPrints.count) fingerprints")
        if analysisRun == run { analysis = nil }
        if newPrints.count != cache.count || groups != nil {
            prints = newPrints
            Task.detached { Store.save(newPrints, "prints.plist", cache: true) }
        }
        if let groups {
            similar = groups
            analyzed = (items.count, settings)
            startInsights()
        }
    }

    // MARK: Insights (documents, dark and blurry photos)

    /// Runs after the similarity pass, one photo at a time, cached by modification date.
    func startInsights() {
        guard insightTask == nil else { return }
        insightTask = Task {
            await runInsights()
            insightTask = nil
        }
    }

    private func runInsights() async {
        if insights.isEmpty {
            insights = await Task.detached { Store.load("insights.plist", cache: true) ?? [:] }.value
        }
        let todo = items
            .filter { ($0.kind == .photo || $0.kind == .live) && insights[$0.id]?.modified != assets[$0.id]?.modificationDate }
            .compactMap { assets[$0.id] }
        guard !todo.isEmpty else { return }
        trace("insights: \(todo.count) photos to inspect")
        let started = Date.now
        var fresh: [String: Insight] = [:]
        insightProgress = 0
        for (n, a) in todo.enumerated() {
            if Task.isCancelled { break }
            if let i = await Insights.inspect(a) { fresh[a.localIdentifier] = i }
            if (n + 1) % 200 == 0 || n == todo.count - 1 {     // publish in steps, not per photo
                insights.merge(fresh) { _, new in new }
                fresh = [:]
                insightProgress = Double(n + 1) / Double(todo.count)
                let snapshot = insights
                Task.detached { Store.save(snapshot, "insights.plist", cache: true) }
            }
        }
        insightProgress = nil
        let found = insights.values
        trace("insights: done in \(Int(Date.now.timeIntervalSince(started)))s, \(found.filter(\.document).count) documents, "
              + "\(found.filter(\.dark).count) dark, \(found.filter(\.blurry).count) blurry")
    }

    // MARK: Executor

    var isCommitting: Bool { commitTask != nil }

    /// Runs a cleanup. With no actions, finishes the interrupted one.
    func run(_ actions: [String: Action] = [:]) {
        guard commitTask == nil else { return }
        pending.merge(actions) { _, new in new }
        persist()
        commitTask = Task { await commit(); commitTask = nil }
    }

    func cancelCommit() { commitTask?.cancel() }

    /// 1. Transforms one by one (create + verify; the original then becomes a plain delete).
    /// 2. A single batched delete, so a single system confirmation.
    /// Pending work is saved after every item, so an interrupted run resumes where it stopped.
    private func commit() async {
        var report = Report()
        UIApplication.shared.isIdleTimerDisabled = true      // the work needs the app open
        trace("commit: \(pending.count) pending")

        let transforms = pending.filter { $0.value != .delete }.map { ($0.key, $0.value) }
        let photos = transforms.filter { assets[$0.0]?.mediaType == .image }
        let videos = transforms.filter { assets[$0.0]?.mediaType == .video }
        var done = 0
        let total = max(transforms.count, 1)
        func progress(_ title: String, detail: String = "", within: Double = 0, long: Bool = false) {
            setBusy((Double(done) + within) / Double(total) * 0.95, title, detail: detail, long: long)
        }

        // Photos (Live to still, HEIC): prepared 3 at a time, then added 12 per library transaction.
        for start in stride(from: 0, to: photos.count, by: 12) {
            if Task.isCancelled { break }
            progress("Converting \(done + 1)–\(min(done + 12, photos.count)) of \(photos.count)",
                     detail: photos.count == transforms.count ? "" : "Photos first, then \(videos.count) videos")
            let batch = photos[start..<min(start + 12, photos.count)]
            let began = Date.now
            var prepared: [Transformer.Prepared] = []
            await withTaskGroup(of: (String, Result<Transformer.Prepared, Error>).self) { group in
                var queue = batch.compactMap { id, action in assets[id].map { (id, $0, action) } }[...]
                func next() {
                    guard let (id, asset, action) = queue.popFirst() else { return }
                    group.addTask { do { return (id, .success(try await Transformer.prepare(asset, action))) } catch { return (id, .failure(error)) } }
                }
                for _ in 0..<3 { next() }
                for await (id, result) in group {
                    switch result {
                    case .success(let p): prepared.append(p)
                    case .failure(Transformer.Failure.noGain):
                        pending[id] = nil
                        report.failures.append("\(assets[id].map(Transformer.name) ?? id): no savings, skipped")
                    case .failure(let error):
                        trace("commit: \(id) failed: \(error)")
                        report.failures.append("\(assets[id].map(Transformer.name) ?? id): \(error.localizedDescription)")
                    }
                    next()
                }
            }
            do {
                for (id, created) in try await Transformer.create(prepared) {
                    replaced[id] = created.size
                    pending[id] = .delete
                }
            } catch {
                trace("commit: batch failed: \(error)")
                prepared.forEach { try? FileManager.default.removeItem(at: $0.file) }
                report.failures.append("\(prepared.count) items: \(error.localizedDescription)")
            }
            done += batch.count
            trace("commit: \(batch.count) photos in \(String(format: "%.1f", Date.now.timeIntervalSince(began)))s")
            persist()
        }

        // Videos: one at a time, encoding already uses the whole device.
        for (n, (id, action)) in videos.enumerated() {
            if Task.isCancelled { break }
            guard let asset = assets[id] else { pending[id] = nil; continue }
            let title = "Compressing video \(n + 1) of \(videos.count)", name = Transformer.name(asset)
            progress(title, detail: name, long: true)
            Transformer.onStep = { step, fraction in
                Task { @MainActor in
                    progress(title, detail: "\(name) · \(step) \(fraction.formatted(.percent.precision(.fractionLength(0))))",
                             within: fraction * 0.9, long: true)
                }
            }
            defer { Transformer.onStep = nil }
            do {
                replaced[id] = try await Transformer.replace(asset, action).size
                pending[id] = .delete
                trace("commit: replaced \(Transformer.name(asset))")
            } catch Transformer.Failure.noGain {
                pending[id] = nil
                report.failures.append("\(Transformer.name(asset)): no savings, skipped")
            } catch {
                trace("commit: \(Transformer.name(asset)) failed: \(error)")
                report.failures.append("\(Transformer.name(asset)): \(error.localizedDescription)")
            }
            done += 1
            persist()
        }

        let ids = pending.filter { $0.value == .delete }.map(\.key)
        if !ids.isEmpty && !Task.isCancelled {
            setBusy(0.97, "Deleting", detail: "Confirm in the iOS dialog")
            do {
                let gone = try await delete(ids)
                report.freed = gone.reduce(0) { $0 + (byID[$1]?.size ?? 0) - (replaced[$1] ?? 0) }
                report.count = gone.count
                for id in gone { pending[id] = nil; replaced[id] = nil; marked.remove(id) }
                history.insert(Session(date: .now, freed: report.freed, count: report.count), at: 0)
            } catch let e as PHPhotosError where e.code == .userCancelled {
                // Changed their mind: forget plain deletes, keep originals whose new version already exists.
                report.cancelled = true
                pending = pending.filter { replaced[$0.key] != nil }
            } catch {
                trace("commit: delete failed: \(error)")
                report.failures.append(error.localizedDescription)
            }
        }
        report.cancelled = report.cancelled || Task.isCancelled
        persist()
        UIApplication.shared.isIdleTimerDisabled = false
        busy = nil
        self.report = report
        await scan()
    }

    private func delete(_ ids: [String]) async throws -> Set<String> {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(fetch) }
        var gone = Set<String>()
        fetch.enumerateObjects { a, _, _ in gone.insert(a.localIdentifier) }
        return gone
    }

    /// Copies originals straight to a chosen folder (Files, external drive, NAS), no local staging.
    func export(_ ids: [String], to folder: URL) async throws -> Int {
        guard folder.startAccessingSecurityScopedResource() else { throw CocoaError(.fileWriteNoPermission) }
        defer { folder.stopAccessingSecurityScopedResource(); busy = nil }
        let skip: Set<PHAssetResourceType> = [.adjustmentData, .adjustmentBasePhoto, .adjustmentBaseVideo,
                                              .adjustmentBasePairedVideo, .photoProxy]
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        var count = 0
        for (n, id) in ids.enumerated() {
            setBusy(Double(n) / Double(ids.count), "Exporting \(n + 1) of \(ids.count)", long: true)
            guard let a = assets[id] else { continue }
            for r in PHAssetResource.assetResources(for: a) where !skip.contains(r.type) {
                var url = folder.appending(path: r.originalFilename)
                if FileManager.default.fileExists(atPath: url.path()) {
                    url = folder.appending(path: "\(id.prefix(8))-\(r.originalFilename)")
                }
                try await PHAssetResourceManager.default().writeData(for: r, toFile: url, options: options)
                count += 1
            }
        }
        return count
    }

    private func setBusy(_ p: Double, _ title: String, detail: String = "", long: Bool = false) {
        busy = Busy(title: title, detail: detail, progress: p, long: long)
    }
}
