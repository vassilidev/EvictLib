import SwiftUI
import Photos
import AVFoundation

// MARK: Live Photos to stills

struct LiveView: View {
    @Environment(Library.self) private var library
    @State private var selection: Set<String> = []

    var body: some View {
        let lives = library.items.filter { $0.kind == .live && $0.liveGain > 0 }.sorted { $0.liveGain > $1.liveGain }
        ScrollView {
            note("Keeps the photo and drops the motion. Date, location, favorite, albums and EXIF are preserved.")
            SelectableGrid(items: lives, selection: $selection, caption: { "−" + $0.liveGain.fileSize })
        }
        .navigationTitle("Live Photos")
        .toolbar { SelectAllButton(ids: lives.map(\.id), selection: $selection) }
        .safeAreaInset(edge: .bottom) {
            ActionBar(verb: "Convert", actions: actions(selection, .still)) { selection = [] }
        }
    }
}

func note(_ text: String) -> some View {
    Text(text)
        .font(.footnote).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal).padding(.bottom, 8)
}

// MARK: Categories (recordings, screenshots, documents, failed photos, app media)

/// A category to clean: pick items, delete them in one confirmation. Nothing is pre-selected.
struct PickView: View {
    let title: String
    var note: String? = nil
    let items: [Item]
    var caption: (Item) -> String? = { _ in nil }
    @State private var selection: Set<String> = []

    var body: some View {
        ScrollView {
            if let note { Text(note).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.bottom, 8) }
            SelectableGrid(items: items, selection: $selection, caption: caption)
        }
        .overlay { if items.isEmpty { ContentUnavailableView("Nothing Here", systemImage: "checkmark.seal") } }
        .navigationTitle(title)
        .toolbar { SelectAllButton(ids: items.map(\.id), selection: $selection) }
        .safeAreaInset(edge: .bottom) {
            ActionBar(verb: "Delete", actions: actions(selection, .delete)) { selection = [] }
        }
    }
}

/// Screenshots, oldest first, with an age filter: old ones are rarely worth keeping.
struct ScreenshotsView: View {
    enum Age: Int, CaseIterable, Identifiable {
        case all = 0, month = 1, halfYear = 6, year = 12
        var id: Self { self }
        var label: String { switch self { case .all: "All"; case .month: "1 Month+"; case .halfYear: "6 Months+"; case .year: "1 Year+" } }
    }
    @Environment(Library.self) private var library
    @State private var age = Age.month

    var body: some View {
        let cutoff = Calendar.current.date(byAdding: .month, value: -age.rawValue, to: .now)!
        let shots = library.items
            .filter { $0.kind == .screenshot && !$0.isProtected && (age == .all || ($0.date ?? .now) < cutoff) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        PickView(title: "Screenshots", note: "Oldest first. \(shots.count) screenshots, \(shots.totalSize.fileSize).", items: shots)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Age", selection: $age) { ForEach(Age.allCases) { Text($0.label).tag($0) } }
                    } label: { Label(age.label, systemImage: "calendar") }
                }
            }
    }
}

/// Media apps saved into their own albums, biggest app first.
struct AppsView: View {
    @Environment(Library.self) private var library

    var body: some View {
        let apps = Dictionary(grouping: library.items.filter { $0.app != nil && !$0.isFavorite }) { $0.app! }
            .map { (name: $0.key, items: $0.value) }
            .sorted { $0.items.totalSize > $1.items.totalSize }
        List {
            Section {
                ForEach(apps, id: \.name) { app in
                    NavigationLink {
                        PickView(title: app.name, note: "Saved by \(app.name) into its album. Albums created by apps don't protect their items.",
                                 items: app.items)
                    } label: {
                        LabeledContent {
                            Text(app.items.totalSize.fileSize).monospacedDigit()
                        } label: {
                            Text(app.name)
                            Text("\(app.items.count) items").monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("Only apps that save into an album of their own name show up here.")
            }
        }
        .overlay { if apps.isEmpty { ContentUnavailableView("No App Albums", systemImage: "app.dashed") } }
        .navigationTitle("From Apps")
    }
}

// MARK: Compression

struct CompressView: View {
    @Environment(Library.self) private var library
    @State private var selection: Set<String> = []
    @State private var previewing: Item?
    @State private var showSettings = false

    var body: some View {
        let c = library.compression
        let candidates = library.items.filter { c.gain($0) > 0 }.sorted { c.gain($0) > c.gain($1) }
        ScrollView {
            note("Videos to HEVC \(c.preset.rawValue)\(c.normalSpeed ? ", slow-mo at normal speed" : ""). Photos to HEIC\(c.photoMaxSide.map { " at \($0) px" } ?? ""). Touch and hold an item to compare before and after.")
            SelectableGrid(items: candidates, selection: $selection, caption: { "−" + c.gain($0).fileSize }) { previewing = $0 }
        }
        .navigationTitle("Compress")
        .toolbar {
            SelectAllButton(ids: candidates.map(\.id), selection: $selection)
            Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
        }
        .sheet(isPresented: $showSettings) { CompressionSettingsForm() }
        .safeAreaInset(edge: .bottom) {
            ActionBar(verb: "Compress", actions: actions(selection, .compress(c))) { selection = [] }
        }
        .sheet(item: $previewing) { CompressionPreview(item: $0, compression: c) }
    }
}

struct CompressionSettingsForm: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                Section("Videos") {
                    Picker("Resolution", selection: $library.compression.preset) {
                        ForEach(Compression.Preset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Slow-Mo to Normal Speed", isOn: $library.compression.normalSpeed)
                }
                Section {
                    Picker("Maximum Size", selection: $library.compression.photoMaxSide) {
                        Text("Original").tag(Int?.none)
                        Text("2048 px").tag(Int?.some(2048))
                        Text("1440 px").tag(Int?.some(1440))
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("JPEG, PNG and ProRAW become HEIC. Videos already below the target bitrate are skipped. Best done while charging.")
                }
            }
            .navigationTitle("Compression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CompressionPreview: View {
    @Environment(Library.self) private var library
    let item: Item
    let compression: Compression
    @State private var result: (before: CGImage?, after: CGImage?, size: Int64)?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let result {
                    Text("\(item.size.fileSize) → \(result.size.fileSize)").font(.title2.bold())
                    side("Before", result.before)
                    side("After", result.after)
                } else if let error {
                    ContentUnavailableView("Preview Failed", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView("Compressing…").padding(.top, 80)
                }
            }
            .padding()
            .navigationTitle("Before & After")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .task {
            guard let asset = library.assets[item.id] else { return }
            do { result = try await Transformer.preview(asset, compression) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func side(_ label: String, _ img: CGImage?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.headline)
            if let img { Image(decorative: img, scale: 1).resizable().scaledToFit() }
        }
    }
}

// MARK: Bursts and similar photos

enum ClusterMode { case bursts, similar }

struct ClustersView: View {
    @Environment(Library.self) private var library
    let mode: ClusterMode
    @State private var selection: Set<String> = []
    @State private var seen: Set<String> = []
    @State private var showSettings = false

    var body: some View {
        let clusters = mode == .bursts ? library.bursts : (library.similar ?? [])
        List {
            if mode == .similar && library.similar == nil {
                ProgressView("Analyzing photos… \(Int((library.analysis ?? 0) * 100))%", value: library.analysis ?? 0)
            } else if clusters.isEmpty {
                ContentUnavailableView("Nothing Found", systemImage: mode == .bursts ? "square.stack.3d.down.right" : "square.on.square")
            }
            ForEach(clusters) { ClusterRow(cluster: $0, selection: $selection) }
        }
        .navigationTitle(mode == .bursts ? "Bursts" : "Similar Photos")
        .toolbar {
            if mode == .similar { Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true } }
        }
        .safeAreaInset(edge: .bottom) {
            ActionBar(verb: "Delete", actions: actions(selection, .delete)) { selection = [] }
        }
        .sheet(isPresented: $showSettings) { SimilaritySettingsForm() }
        // Every item but the best one is pre-selected, once per group: a refresh never resets what you changed.
        .task(id: clusters.map(\.id)) {
            for c in clusters where !seen.contains(c.id) { selection.formUnion(library.extras(c)) }
            seen.formUnion(clusters.map(\.id))
        }
    }
}

struct ClusterRow: View {
    @Environment(Library.self) private var library
    let cluster: Cluster
    @Binding var selection: Set<String>

    var body: some View {
        let items = cluster.members.compactMap { library.byID[$0] }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(items.count) items · \(Int((cluster.similarity * 100).rounded()))% similar").font(.subheadline.bold())
                Spacer()
                Button("Keep Best") {
                    selection.subtract(cluster.members)
                    selection.formUnion(library.extras(cluster))
                }
                .buttonStyle(.borderless).font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        AssetCell(item: item, selected: selection.contains(item.id), best: cluster.keep.contains(item.id),
                                  onTap: { selection.formSymmetricDifference([item.id]) })
                            .frame(width: 110)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SimilaritySettingsForm: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                Section {
                    Toggle("Time Window", isOn: Binding(get: { library.similarity.window > 0 },
                                                        set: { library.similarity.window = $0 ? 3 : 0 }))
                    if library.similarity.window > 0 {
                        slider("Max Gap", $library.similarity.window, 1...60, "\(Int(library.similarity.window)) s")
                    }
                } footer: {
                    Text(library.similarity.window > 0 ? "Only photos taken close together are compared."
                         : "Compares the whole library. Much slower.")
                }
                Section {
                    slider("Similarity", $library.similarity.similar, 0.7...0.99, "\(Int(library.similarity.similar * 100))%")
                    slider("Exact Duplicate", $library.similarity.exact, 0.95...1, "\(Int(library.similarity.exact * 100))%")
                    Toggle("Include Videos", isOn: $library.similarity.videos)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ label: String) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: label)
            Slider(value: value, in: range, step: range.upperBound > 2 ? 1 : 0.01)
        }
    }
}

// MARK: Swipe

/// Liquid Glass on iOS 26; the system material before it.
extension View {
    @ViewBuilder func glassBackground<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else if let tint {
            background(tint.opacity(0.8), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    /// iOS 26's soft scroll edge under the bars; nothing before.
    @ViewBuilder func softTopEdge() -> some View {
        if #available(iOS 26, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }
}

/// Groups glass shapes so they blend and morph together on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: spacing) { content } } else { content }
    }
}

/// The photo owns the screen; size, facts and controls float on glass. Largest items first.
struct SwipeView: View {
    private enum Choice { case delete, keep, favorite }
    @Environment(Library.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var drag: CGSize = .zero
    @State private var undo: [(id: String, choice: Choice)] = []
    @State private var reviewing = false
    @State private var playing: Item?
    @State private var haptic = 0
    @State private var whole = false        // double-tap: whole frame instead of full screen
    @State private var preloader = SwipePreloader()
    @AppStorage("swipeMuted") private var muted = true

    private let threshold: CGFloat = 110

    var body: some View {
        let window = Array(library.items.lazy
            .filter { !library.marked.contains($0.id) && !library.kept.contains($0.id) && !$0.isProtected }
            .prefix(3))
        let next = window.first
        let marked = library.items.filter { library.marked.contains($0.id) }
        ZStack {
            Color.black.ignoresSafeArea()
            if let item = next {
                media(item)
                    .id(item.id)
                    .transition(.opacity)
                edgeGlow
            } else {
                ContentUnavailableView("All Sorted", systemImage: "checkmark.seal",
                                       description: Text("Swipe left to delete, right to keep, up to favorite."))
            }
        }
        .overlay(alignment: .top) { header(next, marked) }
        .overlay(alignment: .bottom) {
            if next != nil { controls(next) } else if !undo.isEmpty { undoOnly }
        }
        .environment(\.colorScheme, .dark)     // media viewer, like Photos
        .sensoryFeedback(.impact(weight: .medium), trigger: haptic)
        // The current item and the next two are kept ready; anything else is released.
        .task(id: window.map(\.id)) { preloader.prepare(window.compactMap { library.assets[$0.id] }) }
        .onDisappear { preloader.prepare([]) }
        .sheet(isPresented: $reviewing) { MarkedReview() }
        .fullScreenCover(item: $playing) { item in
            if let asset = library.assets[item.id] { PlayerView(asset: asset) }
        }
    }

    // MARK: Media and gesture

    private func media(_ item: Item) -> some View {
        FullBleed(asset: library.assets[item.id], fit: whole)
            .overlay {
                if let player = preloader.players[item.id] {
                    LoopingVideo(player: player, fill: !whole, muted: muted)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: preloader.players[item.id] != nil)
            .onTapGesture(count: 2) { withAnimation(.snappy) { whole.toggle() } }
            .overlay {
                if item.kind == .live {
                    Button { playing = item } label: {
                        Image(systemName: "play.fill").font(.title.weight(.semibold))
                            .frame(width: 76, height: 76)
                    }
                    .buttonStyle(.plain)
                    .glassBackground(Circle(), interactive: true)
                    .accessibilityLabel("Play")
                }
            }
            .offset(drag)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width) / 22), anchor: .bottom)
            .gesture(DragGesture(minimumDistance: 12)
                .onChanged { v in
                    let before = decision(drag)
                    drag = v.translation
                    if decision(drag) != nil && before == nil { haptic += 1 }     // the one haptic of a swipe
                }
                .onEnded { v in
                    if let c = decision(v.translation) ?? decision(v.predictedEndTranslation) {
                        if decision(v.translation) == nil { haptic += 1 }     // a fast flick never crossed the threshold
                        commit(c, item, toward: v.predictedEndTranslation)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { drag = .zero }
                    }
                })
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Delete") { tap(.delete, item) }
            .accessibilityAction(named: "Keep") { tap(.keep, item) }
            .accessibilityAction(named: "Favorite") { tap(.favorite, item) }
            .accessibilityAction(named: whole ? "Fill Screen" : "Show Whole Photo") { whole.toggle() }
    }

    /// The edge the item travels toward lights up in that choice's colour, with its symbol.
    private var edgeGlow: some View {
        let left = max(0, -drag.width) / threshold, right = max(0, drag.width) / threshold
        let up = abs(drag.height) > abs(drag.width) ? max(0, -drag.height) / threshold : 0
        return ZStack {
            glow(.red, "trash.fill", from: .leading, level: left)
            glow(.green, "checkmark", from: .trailing, level: right)
            glow(.pink, "heart.fill", from: .top, level: up)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, _ icon: String, from edge: UnitPoint, level: CGFloat) -> some View {
        let l = min(level, 1)
        return LinearGradient(colors: [color.opacity(0.6), .clear], startPoint: edge,
                              endPoint: UnitPoint(x: 1 - edge.x * 0.4 - (1 - edge.x) * 0.6, y: edge == .top ? 0.45 : edge.y))
            .overlay(alignment: Alignment(horizontal: edge == .leading ? .leading : edge == .trailing ? .trailing : .center,
                                          vertical: edge == .top ? .top : .center)) {
                Image(systemName: icon).font(.system(size: 44, weight: .bold))
                    .padding(edge == .top ? 140 : 28)
                    .scaleEffect(0.6 + 0.4 * l)
            }
            .opacity(l)
    }

    private func decision(_ t: CGSize) -> Choice? {
        if t.height < -threshold && abs(t.height) > abs(t.width) { return .favorite }
        if t.width < -threshold { return .delete }
        if t.width > threshold { return .keep }
        return nil
    }

    /// Buttons and VoiceOver: no threshold was crossed, so this is the decision's one haptic.
    private func tap(_ c: Choice, _ item: Item) {
        haptic += 1
        commit(c, item, toward: .zero)
    }

    /// Flies the item off along the swipe's own direction with a spring, then the next one fades in.
    private func commit(_ c: Choice, _ item: Item, toward predicted: CGSize) {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { choose(c, item) }
            return
        }
        let away: CGSize = switch c {
        case .delete: CGSize(width: -720, height: drag.height + predicted.height * 0.2)
        case .keep: CGSize(width: 720, height: drag.height + predicted.height * 0.2)
        case .favorite: CGSize(width: drag.width + predicted.width * 0.2, height: -1100)
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { drag = away } completion: {
            withAnimation(.easeOut(duration: 0.2)) { choose(c, item) }
        }
    }

    private func choose(_ c: Choice, _ item: Item) {
        switch c {
        case .delete: library.marked.insert(item.id)
        case .keep: library.kept.insert(item.id)
        case .favorite:
            library.kept.insert(item.id)
            Task { await library.setFavorite(item.id, true) }
        }
        undo.append((item.id, c))
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { drag = .zero; whole = false }
    }

    private func revert() {
        guard let (id, c) = undo.popLast() else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            switch c {
            case .delete: library.marked.remove(id)
            case .keep: library.kept.remove(id)
            case .favorite:
                library.kept.remove(id)
                Task { await library.setFavorite(id, false) }
            }
        }
    }

    // MARK: Glass HUD

    private func header(_ item: Item?, _ marked: [Item]) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let item {
                // Stacks at accessibility text sizes instead of truncating the facts.
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            size(item)
                            facts(item)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 16) {
                            size(item)
                            Spacer(minLength: 8)
                            facts(item).fixedSize().layoutPriority(1)     // the size figure shrinks first
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .glassBackground(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            if !marked.isEmpty {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { reviewing = true } label: {
                            Label("\(marked.count) · \(marked.totalSize.fileSize)", systemImage: "trash")
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .contentTransition(.numericText())
                                .padding(.horizontal, 16).padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        .glassBackground(Capsule(), interactive: true)
                        .accessibilityLabel("\(marked.count) to delete, \(marked.totalSize.fileSize). Review")
                        Button("Delete") { library.run(actions(library.marked, .delete)) }
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .buttonStyle(.plain)
                            .glassBackground(Capsule(), tint: .red.opacity(0.75), interactive: true)
                            .disabled(library.busy != nil)
                    }
                }
                .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .animation(.snappy, value: marked.count)
    }

    private func size(_ item: Item) -> some View {
        Text(item.size.fileSize)
            .font(.largeTitle.bold()).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func facts(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            fact("TYPE", type(item))
            fact("DATE", item.date?.formatted(.dateTime.month(.abbreviated).year()) ?? "—")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
    }

    private func type(_ item: Item) -> String {
        switch item.kind {
        case .video: "Video " + Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond))
        case .recording: "Recording " + Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond))
        case .live: "Live Photo"
        case .screenshot: "Screenshot"
        case .burst: "Burst"
        case .photo: "Photo"
        }
    }

    /// When everything is sorted, Undo is the only thing left to do.
    private var undoOnly: some View {
        control("Undo", "arrow.uturn.backward", .primary) { revert() }
            .padding(6)
            .glassBackground(Capsule(), interactive: true)
            .padding(.bottom, 14)
    }

    /// One glass control bar, like a Photos toolbar: Delete, Undo, Favorite, Keep.
    private func controls(_ item: Item?) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            if let item, item.isVideo { soundButton(item) }
            actionBar(item)
        }
    }

    /// Videos autoplay muted; this turns the sound on for every video until turned off again.
    private func soundButton(_ item: Item) -> some View {
        Button {
            muted.toggle()
            if !muted { try? AVAudioSession.sharedInstance().setCategory(.playback) }    // plays even in silent mode
        } label: {
            Group {
                if preloader.players[item.id] == nil {
                    ProgressView()
                } else {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(PressStyle())
        .glassBackground(Circle(), interactive: true)
        .padding(.trailing, 20)
        .accessibilityLabel(muted ? "Turn sound on" : "Mute")
    }

    private func actionBar(_ item: Item?) -> some View {
        HStack(spacing: 6) {
            control("Delete", "trash.fill", .red) { if let item { tap(.delete, item) } }.disabled(item == nil)
            control("Undo", "arrow.uturn.backward", .secondary) { revert() }.disabled(undo.isEmpty)
            control("Favorite", "heart.fill", .pink) { if let item { tap(.favorite, item) } }.disabled(item == nil)
            control("Keep", "checkmark", .green) { if let item { tap(.keep, item) } }.disabled(item == nil)
        }
        .padding(6)
        .glassBackground(Capsule(), interactive: true)
        .padding(.bottom, 14)
    }

    private func control(_ title: String, _ icon: String, _ color: some ShapeStyle,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(color)
                .frame(width: 66, height: 56)
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }
}

/// Keeps the swipe window ready: videos as players (downloaded from iCloud when needed, high quality),
/// photos warm in the image cache. Whatever leaves the window is released.
@MainActor @Observable
final class SwipePreloader {
    static let images = PHCachingImageManager()
    static let photoSize = CGSize(width: 1400, height: 2600)

    private(set) var players: [String: AVPlayer] = [:]
    @ObservationIgnored private var loading: [String: PHImageRequestID] = [:]
    @ObservationIgnored private var warm: [PHAsset] = []

    func prepare(_ window: [PHAsset]) {
        let ids = Set(window.map(\.localIdentifier))
        for (id, request) in loading where !ids.contains(id) {
            PHImageManager.default().cancelImageRequest(request)
            loading[id] = nil
        }
        for (id, player) in players where !ids.contains(id) {
            player.pause()
            players[id] = nil
        }
        for a in window where a.mediaType == .video && players[a.localIdentifier] == nil && loading[a.localIdentifier] == nil {
            let id = a.localIdentifier
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .highQualityFormat
            loading[id] = PHImageManager.default().requestPlayerItem(forVideo: a, options: o) { item, _ in
                Task { @MainActor in
                    guard self.loading.removeValue(forKey: id) != nil, let item else { return }
                    let player = AVPlayer(playerItem: item)
                    player.isMuted = true
                    player.actionAtItemEnd = .none
                    self.players[id] = player
                }
            }
        }
        let photos = window.filter { $0.mediaType == .image }
        Self.images.stopCachingImages(for: warm.filter { !photos.contains($0) }, targetSize: Self.photoSize,
                                      contentMode: .aspectFill, options: nil)
        Self.images.startCachingImages(for: photos, targetSize: Self.photoSize, contentMode: .aspectFill, options: nil)
        warm = photos
    }
}

/// A muted, looping video with no controls, filling or fitting the screen.
struct LoopingVideo: UIViewRepresentable {
    let player: AVPlayer
    var fill = true
    var muted = true

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var loop: NSObjectProtocol?
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.backgroundColor = .clear
        v.playerLayer.player = player
        v.loop = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                        object: player.currentItem, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        player.play()
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        player.isMuted = muted
    }

    static func dismantleUIView(_ v: PlayerView, coordinator: ()) {
        v.playerLayer.player?.pause()
        if let loop = v.loop { NotificationCenter.default.removeObserver(loop) }
    }
}

/// The media at screen size, edge to edge under the glass; `fit` shows the whole frame instead.
struct FullBleed: View {
    let asset: PHAsset?
    var fit = false
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .task(id: asset?.localIdentifier) {
            guard let asset else { return }
            // Same manager and size as the preloader, so the next photos come out of its warm cache.
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .opportunistic
            SwipePreloader.images.requestImage(for: asset, targetSize: SwipePreloader.photoSize,
                                               contentMode: .aspectFill, options: o) { img, _ in
                if let img { image = img }
            }
        }
    }
}

/// Swiped-left items: tap one to keep it, then delete the rest in one confirmation.
struct MarkedReview: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            ScrollView {
                note("Tap an item to keep it.")
                SelectableGrid(items: library.items.filter { library.marked.contains($0.id) }, selection: $library.marked)
            }
            .navigationTitle("To Delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .safeAreaInset(edge: .bottom) {
                ActionBar(verb: "Delete", actions: actions(library.marked, .delete)) { dismiss() }
            }
        }
    }
}

// MARK: History

struct HistoryView: View {
    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Label("Deleted items stay in Recently Deleted for 30 days. Empty that album in Photos to free iCloud space now.",
                      systemImage: "info.circle")
                Button("Open Photos", systemImage: "photo.on.rectangle") { openURL(photosURL) }
            }
            if !library.history.isEmpty {
                Section("Total Freed: \(library.history.reduce(0) { $0 + $1.freed }.fileSize)") {
                    ForEach(library.history) { s in
                        LabeledContent(s.date.formatted(date: .abbreviated, time: .shortened),
                                       value: "\(s.freed.fileSize) · \(s.count) items")
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
    }
}
