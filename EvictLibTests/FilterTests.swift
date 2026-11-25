import Foundation
import Testing
@testable import EvictLib

private func item(_ id: String, _ kind: Kind = .photo, size: Int64 = 10, date: Date? = .now,
                  fav: Bool = false, album: Bool = false) -> Item {
    Item(id: id, kind: kind, size: size, date: date, isFavorite: fav, inAlbum: album)
}

@Test func favoritesAndAlbumItemsExcludedByDefault() {
    var f = Filter()
    #expect(f.matches(item("a")))
    #expect(!f.matches(item("b", fav: true)))
    #expect(!f.matches(item("c", album: true)))
    f.includeProtected = true
    #expect(f.matches(item("b", fav: true)))
    #expect(f.matches(item("c", album: true)))
}

@Test func kindAndMinimumSize() {
    var f = Filter()
    f.kind = .video
    f.minSize = 100
    #expect(f.matches(item("a", .video, size: 100)))
    #expect(!f.matches(item("b", .video, size: 99)))
    #expect(!f.matches(item("c", .photo, size: 500)))
}

@Test func dateRangeIncludesTheLastDay() {
    let cal = Calendar.current
    let day = cal.date(from: DateComponents(year: 2025, month: 6, day: 15, hour: 12))!
    var f = Filter()
    f.byDate = true
    f.from = day
    f.to = day
    #expect(f.matches(item("a", date: cal.date(bySettingHour: 0, minute: 0, second: 0, of: day))))
    #expect(f.matches(item("b", date: cal.date(bySettingHour: 23, minute: 59, second: 59, of: day))))
    #expect(!f.matches(item("c", date: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)))))
    #expect(!f.matches(item("d", date: cal.date(byAdding: .second, value: -1, to: cal.startOfDay(for: day)))))
    #expect(!f.matches(item("e", date: nil)))
}
