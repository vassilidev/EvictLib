# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

The owner of a large iCloud Photos library (17,661 items on the reference device) who has run out of iCloud space and refuses the subscription-and-quota model of existing cleaners. Today a single user installing from Xcode; the product must be able to become an App Store product later.

## Product Purpose

Free as much iCloud Photos space as possible in one sorting session, with no subscription and no daily quota. Success is gigabytes actually freed (visible in Settings › iCloud after Recently Deleted is emptied), with zero unconfirmed deletion and zero lost favorite or album item.

## Positioning

Everything runs on the device through PhotoKit: no account, no server, no upload. Items are sorted by real file size, so the biggest wins come first; replacements (Live Photo to still, HEVC/HEIC compression) keep date, location, favorite, albums and EXIF.

## Operating Context

Used on iPhone, with the Photos library often in Optimize Storage mode (originals in iCloud). Sessions happen at home, plugged in for long compressions. Deletions go to Recently Deleted for 30 days; iOS asks for one system confirmation per delete batch.

## Capabilities and Constraints

- Largest Items (sorted by size, filters), Similar Photos and Bursts (pre-selected duplicates, best item kept), Live Photos to stills, Compress (HEVC video, HEIC photo), Swipe sorting, History.
- Swipe: the job is maximum space gained, fast; largest items first. Gestures stay as they are: left = delete, right = keep, up = favorite, plus Undo. File size stays prominent. Videos and Live Photos play from the card.
- Every action starts from a direct button with its savings; no basket or staging step (the user rejected it).
- Full photo library access required. Background work must never block Photos requests (lesson: heavy Vision work on the cooperative pool starved the app).

## Brand Commitments

- Clean, simple, efficient, native iOS: system components, light and dark mode, English only. The user wants an app people feel like using.
- Name: EvictLib. App icon: stacked photo cards with a down-arrow badge (light, dark, tinted variants).

## Evidence on Hand

PRD (Claude Doc, 2026-11-25). Real measurements from the reference iPhone: 2,011 fingerprints analyzed in 13 s, 325 similar groups. No testimonials, users, or benchmarks beyond these.

## Product Principles

1. Biggest wins first: every screen leads with bytes saved.
2. Never lose a memory: favorites and album items are protected by default, iOS confirms every deletion.
3. One tap to act: no intermediate queues, the action button states the savings.
4. Native over novel: system controls and conventions, polish in the details.
5. Never block: background work stays light and invisible.

## Accessibility & Inclusion

Swipe actions also exist as buttons (VoiceOver, no gesture required). Support Dynamic Type and both appearances.
