import Foundation
import Photos
import Testing
@testable import EvictLib

@Test func compressionSkipsWhatWouldNotShrink() {
    let c = Compression()   // 1080p ≈ 8 Mbit/s
    #expect(c.gain(Item(id: "heavy", kind: .video, size: 400_000_000, duration: 60)) == 340_000_000)
    #expect(c.gain(Item(id: "light", kind: .video, size: 60_000_000, duration: 60)) == 0)
    #expect(c.gain(Item(id: "jpeg", kind: .photo, size: 4_000_000, uti: "public.jpeg", width: 4000, height: 3000)) == 2_000_000)
    let heic = Item(id: "heic", kind: .photo, size: 2_000_000, uti: "public.heic", width: 4000, height: 3000)
    #expect(c.gain(heic) == 0)
    var resize = c
    resize.photoMaxSide = 2000
    #expect(resize.gain(heic) == 1_500_000)
    #expect(c.gain(Item(id: "live", kind: .live, size: 5_000_000, uti: "public.jpeg")) == 0)
}

@Test func burstsKeepPicksAndFavorites() {
    let t = Date(timeIntervalSince1970: 0)
    func frame(_ id: String, _ s: Double, pick: Bool = false, fav: Bool = false) -> Item {
        Item(id: id, kind: .burst, size: 1, date: t.addingTimeInterval(s), isFavorite: fav, burstID: "B", burstPick: pick)
    }
    let picked = Similarity.bursts([frame("a", 0), frame("b", 1, pick: true), frame("c", 2, fav: true)])
    #expect(picked.count == 1)
    #expect(picked[0].keep == ["b", "c"])
    #expect(Similarity.bursts([frame("a", 1), frame("b", 0)])[0].keep == ["b"])     // no pick: keep the first frame
    #expect(Similarity.bursts([frame("single", 0)]).isEmpty)
}

@Test func bestItemFavoriteThenSharpness() {
    let sharp = Print(modified: nil, hashes: [0], vector: Data(), sharpness: 100, faces: nil)
    let blurry = Print(modified: nil, hashes: [0], vector: Data(), sharpness: 10, faces: nil)
    let a = Item(id: "a", kind: .photo, size: 1, width: 10, height: 10)
    let b = Item(id: "b", kind: .photo, size: 1, width: 10, height: 10, isFavorite: true)
    #expect(Similarity.best([(a, sharp), (Item(id: "c", kind: .photo, size: 1, width: 10, height: 10), blurry)]) == "a")
    #expect(Similarity.best([(a, sharp), (b, blurry)]) == "b")
}

@Test func clusteringRespectsWindowAndThresholds() async {
    func unit(_ axis: Int) -> Data {
        var v = [Float](repeating: 0, count: 768)
        v[axis] = 1
        return v.withUnsafeBytes { Data($0) }
    }
    let t = Date(timeIntervalSince1970: 0)
    let items = [
        Item(id: "a", kind: .photo, size: 3, date: t),
        Item(id: "b", kind: .photo, size: 2, date: t.addingTimeInterval(1)),        // same scene as a
        Item(id: "c", kind: .photo, size: 1, date: t.addingTimeInterval(100)),      // same scene, far away in time
        Item(id: "d", kind: .photo, size: 1, date: t.addingTimeInterval(2)),        // different scene, same dHash as a
    ]
    let cache = [
        "a": Print(modified: nil, hashes: [1], vector: unit(0), sharpness: 1, faces: nil),
        "b": Print(modified: nil, hashes: [2], vector: unit(0), sharpness: 2, faces: nil),
        "c": Print(modified: nil, hashes: [3], vector: unit(0), sharpness: 1, faces: nil),
        "d": Print(modified: nil, hashes: [1], vector: unit(1), sharpness: 1, faces: nil),
    ]
    let assets = Dictionary(uniqueKeysWithValues: items.map { ($0.id, PHAsset()) })

    var s = SimilaritySettings()
    s.exact = 0.99                                  // d only matches a through the dHash
    let (windowed, _) = await Similarity.analyze(items, assets, s, cache: cache) { _ in }
    #expect(windowed?.map { Set($0.members) } == [["a", "b", "d"]])
    #expect(windowed?.first?.keep == ["b"])         // the sharpest

    s.exact = 1.01                                  // dHash disabled
    s.window = 0                                    // global scan: c joins a and b
    let (global, _) = await Similarity.analyze(items, assets, s, cache: cache) { _ in }
    #expect(global?.map { Set($0.members) } == [["a", "b", "c"]])
}

