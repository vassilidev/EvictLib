import SwiftUI
import Photos
import PhotosUI
import AVKit

let gridColumns = [GridItem(.adaptive(minimum: 110), spacing: 2)]
let photosURL = URL(string: "photos-redirect://")!

func actions(_ ids: Set<String>, _ action: Action) -> [String: Action] {
    Dictionary(uniqueKeysWithValues: ids.map { ($0, action) })
}

extension Kind {
    var color: Color {
        switch self {
        case .video: .pink
        case .recording: .purple
        case .photo: .blue
        case .live: .yellow
        case .screenshot: .green
        case .burst: .orange
        }
    }
}

/// What a long cleanup is doing right now: step, file, real progress, and a way out.
struct BusyCard: View {
    let busy: Library.Busy
    let canStop: Bool
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(busy.title).font(.headline).monospacedDigit()
                if !busy.detail.isEmpty {
                    Text(busy.detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
                }
            }
            ProgressView(value: busy.progress)
                .animation(.easeOut(duration: 0.4), value: busy.progress)
            HStack {
                Text(busy.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                if canStop { Button("Stop", role: .destructive, action: stop).font(.subheadline.weight(.semibold)) }
            }
            if busy.long {
                Label("Keep EvictLib open; the screen stays on.", systemImage: "iphone")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: 340)
        .glassBackground(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL
    @AppStorage("tab") private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Clean", systemImage: "sparkles") }.tag(0)
            SwipeView()
                .tabItem { Label("Swipe", systemImage: "hand.draw") }.tag(1)
        }
        .task { if library.items.isEmpty { await library.scan() } }
        .overlay {
            if let p = library.progress, library.items.isEmpty {
                card { ProgressView("Scanning library…", value: p) }
            } else if let busy = library.busy {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    BusyCard(busy: busy, canStop: library.isCommitting) { library.cancelCommit() }
                }
                .transition(.opacity)
            }
        }
        .alert(title(library.report), isPresented: Binding(get: { library.report != nil }, set: { if !$0 { library.report = nil } })) {
            Button("Open Photos") { openURL(photosURL) }
            Button("OK", role: .cancel) {}
        } message: {
            Text(message(library.report))
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 12, content: content)
            .padding().frame(maxWidth: 300)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private func title(_ r: Report?) -> String {
        guard let r else { return "" }
        return r.cancelled ? "Nothing Deleted" : "\(r.freed.fileSize) Freed"
    }

    private func message(_ r: Report?) -> String {
        guard let r else { return "" }
        var lines: [String] = []
        if r.cancelled { lines.append("New versions already created were kept. You can finish from the Clean tab.") }
        if r.count > 0 { lines.append("Items are in Recently Deleted for 30 days. Empty it in Photos to free iCloud space now.") }
        lines += r.failures
        return lines.joined(separator: "\n")
    }
}

// MARK: Home

/// Heavy Wall: your heaviest items are the home; the totals float on glass over them.
struct HomeView: View {
    @Environment(Library.self) private var library
    @State private var showHistory = false

    var body: some View {
        let items = library.items
        let heaviest = Array(items.lazy.filter { !$0.isProtected }.prefix(12))
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink { WeightList() } label: { Mosaic(items: heaviest) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Largest items")
                StorageSummary(items: items, freed: library.history.reduce(0) { $0 + $1.freed })
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .glassBackground(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, heaviest.isEmpty ? 16 : -Mosaic.overlap)    // the glass always sits over photos
                recommendations
                    .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .softTopEdge()
        .navigationTitle("EvictLib")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }   // the wall replaces the title
            ToolbarItem(placement: .topBarTrailing) {
                Button("History", systemImage: "clock.arrow.circlepath") { showHistory = true }
            }
        }
        .sheet(isPresented: $showHistory) { NavigationStack { HistoryView() } }
        .refreshable { await library.scan() }
    }

    private var recommendations: some View {
        let items = library.items
        let bursts = library.bursts.reduce(0) { $0 + library.gain($1) }
        let live = items.reduce(0) { $0 + $1.liveGain }
        let compress = items.reduce(0) { $0 + library.compression.gain($1) }
        let top = items.lazy.filter { !$0.isProtected }.prefix(50).reduce(Int64(0)) { $0 + $1.size }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations").font(.headline).padding(.leading, 4)
            VStack(spacing: 0) {
                if !library.pending.isEmpty && !library.isCommitting {
                    Button { library.run() } label: {
                        row("Finish Previous Cleanup", "\(library.pending.count) items left", icon: "arrow.clockwise",
                            color: .gray, savings: nil)
                    }
                    divider
                }
                link("Largest Items", "Top 50, biggest first", icon: "scalemass", color: .blue, savings: top) { WeightList() }
                divider
                if let similar = library.similar {
                    let gain = similar.reduce(0) { $0 + library.gain($1) }
                    link("Similar Photos", similar.isEmpty ? "No near-duplicates" : "\(similar.count) groups found",
                         icon: "square.on.square", color: .indigo, savings: gain) { ClustersView(mode: .similar) }
                } else {
                    link("Similar Photos", "Analyzing… \((library.analysis ?? 0).formatted(.percent.precision(.fractionLength(0))))", icon: "square.on.square",
                         color: .indigo, savings: 0) { ClustersView(mode: .similar) }
                }
                // Only what can actually free space is listed.
                if bursts > 0 {
                    divider
                    link("Bursts", "\(library.bursts.count) bursts", icon: "square.stack.3d.down.right", color: .orange,
                         savings: bursts) { ClustersView(mode: .bursts) }
                }
                if live > 0 {
                    divider
                    link("Live Photos", "Keep the photo only", icon: "livephoto", color: .yellow, savings: live) { LiveView() }
                }
                if compress > 0 {
                    divider
                    link("Compress", "HEVC and HEIC", icon: "arrow.down.right.and.arrow.up.left", color: .teal,
                         savings: compress) { CompressView() }
                }
                let recordings = items.filter { $0.kind == .recording && !$0.isProtected }
                if !recordings.isEmpty {
                    divider
                    link("Screen Recordings", "\(recordings.count) recordings", icon: "record.circle", color: .purple,
                         savings: recordings.totalSize) {
                        PickView(title: "Screen Recordings", note: "Largest first. Often long and forgotten.", items: recordings)
                    }
                }
                let shots = items.filter { $0.kind == .screenshot && !$0.isProtected }
                if !shots.isEmpty {
                    divider
                    link("Screenshots", "\(shots.count) screenshots", icon: "camera.viewfinder", color: .green,
                         savings: shots.totalSize) { ScreenshotsView() }
                }
                insightRows(items)
                let fromApps = items.filter { $0.app != nil && !$0.isFavorite }
                if !fromApps.isEmpty {
                    divider
                    link("From Apps", "WhatsApp, Telegram, Instagram…", icon: "app.badge", color: .mint,
                         savings: fromApps.totalSize) { AppsView() }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    private var divider: some View { Divider().padding(.leading, 62) }

    /// Documents and failed photos come from the background inspection; until it is done, they show its progress.
    @ViewBuilder private func insightRows(_ items: [Item]) -> some View {
        let insights = library.insights
        let docs = items.filter { insights[$0.id]?.document == true && !$0.isProtected }
        let failed = items.filter { (insights[$0.id]?.dark == true || insights[$0.id]?.blurry == true) && !$0.isProtected }
        let analyzing = library.insightProgress.map { "Analyzing… \($0.formatted(.percent.precision(.fractionLength(0))))" }
        if !docs.isEmpty || analyzing != nil {
            divider
            link("Documents & Receipts", analyzing ?? "\(docs.count) photos of paper", icon: "doc.text.viewfinder",
                 color: .brown, savings: docs.totalSize) {
                PickView(title: "Documents & Receipts",
                         note: "Photos of documents, receipts, tickets and notes, detected on this iPhone. Nothing is selected for you.",
                         items: docs.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            }
        }
        if !failed.isEmpty || analyzing != nil {
            divider
            link("Blurry & Dark", analyzing ?? "\(failed.count) likely failed shots", icon: "camera.metering.unknown",
                 color: .gray, savings: failed.totalSize) {
                PickView(title: "Blurry & Dark",
                         note: "Very dark (often taken in a pocket) or very blurry shots. Nothing is selected for you.",
                         items: failed, caption: { insights[$0.id]?.dark == true ? "Dark" : "Blurry" })
            }
        }
    }

    private func link<D: View>(_ title: String, _ detail: String, icon: String, color: Color, savings: Int64,
                               @ViewBuilder _ destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            row(title, detail, icon: icon, color: color, savings: savings > 0 ? savings : nil, chevron: true)
        }
        .buttonStyle(.plain)
    }

    /// Settings-style row: tinted icon tile, title over a one-line description, savings trailing.
    private func row(_ title: String, _ detail: String, icon: String, color: Color, savings: Int64?,
                     chevron: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.subheadline).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let savings {
                Text(savings.fileSize).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// The 12 heaviest items edge to edge, each with its size, fading into the page under the summary card.
struct Mosaic: View {
    static let overlap: CGFloat = 84
    @Environment(Library.self) private var library
    let items: [Item]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
            ForEach(items) { item in
                Thumbnail(asset: library.assets[item.id], side: 420)      // ~100pt tiles at 3x, never upscaled
                    .overlay(alignment: .bottomLeading) {
                        Text(item.size.fileSize)
                            .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: .capsule)
                            .padding(4)
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.isVideo {
                            Image(systemName: "play.fill").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 2, y: 1).padding(6)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {      // fades only where the card will sit
            // Fully opaque before the badge line, so nothing peeks out beside the card.
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: Color(.systemGroupedBackground), location: 0.7)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Mosaic.overlap)
                .allowsHitTesting(false)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Same idea as Settings › iPhone Storage: one bar split by type, with a legend.
struct StorageSummary: View {
    let items: [Item]
    var freed: Int64 = 0

    var body: some View {
        let sizes = Kind.allCases.map { k in (k, items.lazy.filter { $0.kind == k }.totalSize) }.filter { $0.1 > 0 }
        let total = max(items.totalSize, 1)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(items.totalSize.fileSize).font(.largeTitle.bold()).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: items.totalSize)
                Text(freed > 0 ? "\(items.count) items · \(freed.fileSize) freed so far" : "\(items.count) items in your library")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let usable = geo.size.width - CGFloat(max(sizes.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(sizes, id: \.0) { kind, size in
                        kind.color.frame(width: max(3, usable * CGFloat(size) / CGFloat(total)))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(sizes, id: \.0) { kind, size in
                    HStack(spacing: 6) {
                        Circle().fill(kind.color).frame(width: 8, height: 8)
                        Text(kind.rawValue)
                        Text(size.fileSize).foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Largest items

struct WeightList: View {
    @Environment(Library.self) private var library
    @State private var filter = Filter()
    @State private var selection: Set<String> = []
    @State private var showFilters = false

    var body: some View {
        let shown = library.items.filter(filter.matches)
        ScrollView {
            SelectableGrid(items: shown, selection: $selection)
        }
        .navigationTitle(filter.kind?.rawValue ?? "Largest Items")
        .toolbar {
            SelectAllButton(ids: shown.map(\.id), selection: $selection)
            Button("Filters", systemImage: "line.3.horizontal.decrease") { showFilters = true }
        }
        .safeAreaInset(edge: .bottom) {
            ActionBar(verb: "Delete", actions: actions(selection, .delete)) { selection = [] }
        }
        .sheet(isPresented: $showFilters) { FilterForm(filter: $filter) }
    }
}

// MARK: Shared components

struct SelectableGrid: View {
    let items: [Item]
    @Binding var selection: Set<String>
    var caption: (Item) -> String? = { _ in nil }
    var preview: ((Item) -> Void)?

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(items) { item in
                AssetCell(item: item, selected: selection.contains(item.id), caption: caption(item),
                          onTap: { selection.formSymmetricDifference([item.id]) },
                          preview: preview.map { p in { p(item) } })
            }
        }
    }
}

struct SelectAllButton: View {
    let ids: [String]
    @Binding var selection: Set<String>

    var body: some View {
        let all = !ids.isEmpty && selection.isSuperset(of: ids)
        Button(all ? "Deselect All" : "Select All") {
            if all { selection.subtract(ids) } else { selection.formUnion(ids) }
        }
        .disabled(ids.isEmpty)
    }
}

/// The one place where work starts: a floating glass button that states the savings; iOS confirms deletions.
struct ActionBar: View {
    @Environment(Library.self) private var library
    let verb: String
    let actions: [String: Action]
    var onStart: () -> Void = {}
    @State private var confirmProtected = false
    @State private var exporting = false
    @State private var exportResult: String?

    var body: some View {
        let deletes = actions.filter { $0.value == .delete }.map(\.key)
        let protected = deletes.filter { library.byID[$0]?.isProtected == true }.count
        let tint: Color = deletes.isEmpty ? .accentColor : .red
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                if !deletes.isEmpty {
                    Button { exporting = true } label: {
                        Image(systemName: "externaldrive").font(.title3.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(PressStyle())
                    .glassBackground(Circle(), interactive: true)
                    .accessibilityLabel("Export originals before deleting")
                }
                Button {
                    if protected > 0 { confirmProtected = true } else { start() }
                } label: {
                    VStack(spacing: 1) {
                        Text(actions.isEmpty ? "Select Items" : "\(verb) \(actions.count) \(actions.count == 1 ? "Item" : "Items")")
                            .font(.headline)
                        if !actions.isEmpty {
                            Text("Saves \(library.gain(actions).fileSize)").font(.caption.weight(.medium)).opacity(0.85)
                        }
                    }
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(actions.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .glassBackground(Capsule(), tint: actions.isEmpty ? nil : tint.opacity(0.85), interactive: true)
                .disabled(actions.isEmpty || library.busy != nil)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .animation(.snappy, value: actions.count)
        .confirmationDialog("\(protected) of these are favorites or in albums.", isPresented: $confirmProtected, titleVisibility: .visible) {
            Button("Delete Anyway", role: .destructive, action: start)
        }
        .fileImporter(isPresented: $exporting, allowedContentTypes: [.folder]) { result in
            guard case .success(let folder) = result else { return }
            Task {
                do { exportResult = "Copied \(try await library.export(deletes, to: folder)) files to \(folder.lastPathComponent)." }
                catch { exportResult = "Export stopped: \(error.localizedDescription)" }
            }
        }
        .alert("Export", isPresented: Binding(get: { exportResult != nil }, set: { if !$0 { exportResult = nil } })) {
        } message: { Text(exportResult ?? "") }
    }

    private func start() {
        library.run(actions)
        onStart()
    }
}

/// Plain button that dips when pressed and dims when disabled, for controls drawn on glass.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

struct AssetCell: View {
    @Environment(Library.self) private var library
    let item: Item
    var selected = false
    var caption: String?
    var best = false
    var onTap: () -> Void = {}
    var preview: (() -> Void)?
    @State private var playing = false

    var body: some View {
        Thumbnail(asset: library.assets[item.id])
            .overlay { if selected { Color.black.opacity(0.28) } }
            // One job per corner: play, status, size, selection.
            .overlay(alignment: .topLeading) {
                if item.isPlayable {
                    Button { playing = true } label: {
                        Label(item.isVideo ? Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)) : "LIVE",
                              systemImage: item.isVideo ? "play.fill" : "livephoto")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.5), in: .capsule)
                            .padding(5)
                            .frame(minHeight: 44, alignment: .topLeading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Play")
                }
            }
            .overlay(alignment: .topTrailing) {
                if let status {
                    Image(systemName: status.icon).font(.caption.weight(.bold)).foregroundStyle(status.color)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1).padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(caption ?? item.size.fileSize)
                    .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: .capsule)
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(.white, .blue)
                    .shadow(color: .black.opacity(selected ? 0 : 0.35), radius: 2, y: 1)
                    .padding(5)
            }
            .onTapGesture(perform: onTap)
            .contextMenu {
                Section(facts) {
                    if item.isPlayable { Button("Play", systemImage: "play") { playing = true } }
                    if let preview { Button("Before & After", systemImage: "eye", action: preview) }
                }
            } preview: {
                Thumbnail(asset: library.assets[item.id], side: 1200, fill: false)
                    .aspectRatio(CGFloat(max(item.width, 1)) / CGFloat(max(item.height, 1)), contentMode: .fit)
                    .frame(width: 340)
            }
            .fullScreenCover(isPresented: $playing) {
                if let asset = library.assets[item.id] { PlayerView(asset: asset) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.kind.rawValue), \(caption ?? item.size.fileSize)\(best ? ", best" : "")")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Best shot first, then why an item is protected.
    private var status: (icon: String, color: Color)? {
        if best { return ("star.fill", .yellow) }
        if item.isFavorite { return ("heart.fill", .white) }
        if item.inAlbum { return ("rectangle.stack.fill", .white) }
        return nil
    }

    private var facts: String {
        [item.size.fileSize, item.kind.rawValue, item.date?.formatted(date: .abbreviated, time: .shortened)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

extension Item {
    var isPlayable: Bool { isVideo || kind == .live }
}

/// Full-screen playback with the system player. Streams from iCloud when the original isn't on the device.
struct PlayerView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var live: PHLivePhoto?
    @State private var failed = false
    @State private var download: Double?        // iCloud download progress

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player).ignoresSafeArea(edges: .bottom)
                } else if let live {
                    LivePhotoView(livePhoto: live)
                } else if failed {
                    ContentUnavailableView("Can't Play", systemImage: "exclamationmark.triangle",
                                           description: Text("The video couldn't be loaded from iCloud."))
                        .foregroundStyle(.white)
                } else if let download {
                    ProgressView("Downloading from iCloud… \(Int(download * 100))%", value: download)
                        .tint(.white).foregroundStyle(.white).padding(40)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)     // video always plays on black, like Photos
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        trace("player: loading \(asset.localIdentifier), video \(asset.mediaType == .video)")
        let onProgress: (Double) -> Void = { p in
            Task { @MainActor in
                if Int(p * 10) != Int((download ?? -1) * 10) { trace("player: download \(Int(p * 100))%") }
                download = p
            }
        }
        if asset.mediaType == .video {
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .automatic
            o.progressHandler = { p, error, _, _ in
                if let error { trace("player: download error \(error)") }
                onProgress(p)
            }
            let item = await withCheckedContinuation { (c: CheckedContinuation<AVPlayerItem?, Never>) in
                PHImageManager.default().requestPlayerItem(forVideo: asset, options: o) { item, info in
                    trace("player: item \(item != nil), info \(info ?? [:])")
                    c.resume(returning: item)
                }
            }
            guard let item else { failed = true; return }
            let p = AVPlayer(playerItem: item)
            player = p
            p.play()
        } else {
            let o = PHLivePhotoRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .highQualityFormat
            o.progressHandler = { p, _, _, _ in onProgress(p) }
            PHImageManager.default().requestLivePhoto(for: asset, targetSize: PHImageManagerMaximumSize,
                                                      contentMode: .aspectFit, options: o) { photo, info in
                trace("player: live \(photo != nil), info \(info ?? [:])")
                if let photo { live = photo } else { failed = true }
            }
        }
    }
}

/// Plays the motion once on appear; touch and hold replays it, like in Photos.
struct LivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let v = PHLivePhotoView()
        v.contentMode = .scaleAspectFit
        return v
    }

    func updateUIView(_ v: PHLivePhotoView, context: Context) {
        guard v.livePhoto !== livePhoto else { return }
        v.livePhoto = livePhoto
        v.startPlayback(with: .full)
    }
}

struct Thumbnail: View {
    let asset: PHAsset?
    var side: CGFloat = 300     // pixels
    var fill = true             // square crop, otherwise the whole image
    @State private var image: UIImage?

    var body: some View {
        Group {
            if fill {
                Rectangle().fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
                    .clipped()
                    .contentShape(Rectangle())
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: asset?.localIdentifier) {
            // No network: the local version is enough, iCloud originals are never downloaded here.
            guard let asset else { return }
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                  contentMode: fill ? .aspectFill : .aspectFit, options: nil) { img, _ in
                if let img { image = img }
            }
        }
    }
}

struct FilterForm: View {
    @Binding var filter: Filter
    @Environment(\.dismiss) private var dismiss
    private let sizes: [Int64] = [0, 10, 50, 100, 500, 1000].map { $0 * 1_000_000 }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $filter.kind) {
                    Text("All").tag(Kind?.none)
                    ForEach(Kind.allCases) { Text($0.rawValue).tag(Kind?.some($0)) }
                }
                Picker("Minimum Size", selection: $filter.minSize) {
                    ForEach(sizes, id: \.self) { Text($0 == 0 ? "None" : $0.fileSize).tag($0) }
                }
                Toggle("Date Range", isOn: $filter.byDate)
                if filter.byDate {
                    DatePicker("From", selection: $filter.from, in: ...filter.to, displayedComponents: .date)
                    DatePicker("To", selection: $filter.to, in: filter.from..., displayedComponents: .date)
                }
                Toggle("Include Favorites & Album Items", isOn: $filter.includeProtected)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}
