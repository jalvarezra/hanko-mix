import Foundation
import Testing
@testable import PAVCore

private func app(_ id: String, playing: Bool) -> AppGroup {
    AppGroup(id: AppID(id), displayName: id, processObjectIDs: [], isPlaying: playing, outputDeviceUIDs: [])
}

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func silentAppStaysVisibleWithinTimeout() {
    var recent = RecentApps(idleTimeout: 600)
    recent.observe([app("Spotify", playing: true)], at: t0)
    recent.observe([app("Spotify", playing: false)], at: t0.addingTimeInterval(10))
    #expect(recent.visibleIdle(excluding: [], at: t0.addingTimeInterval(500)).map(\.id) == [AppID("Spotify")])
}

@Test func silentAppHidesAfterTimeout() {
    var recent = RecentApps(idleTimeout: 600)
    recent.observe([app("Spotify", playing: true)], at: t0)
    recent.observe([app("Spotify", playing: false)], at: t0.addingTimeInterval(10))
    #expect(recent.visibleIdle(excluding: [], at: t0.addingTimeInterval(611)).isEmpty)
}

@Test func idleTimeCountsFromWhenPlaybackStopped() {
    // Played for an hour with no snapshot in between; the clock starts when it stops.
    var recent = RecentApps(idleTimeout: 600)
    recent.observe([app("Spotify", playing: true)], at: t0)
    recent.observe([app("Spotify", playing: false)], at: t0.addingTimeInterval(3600))
    #expect(recent.visibleIdle(excluding: [], at: t0.addingTimeInterval(3900)).map(\.id) == [AppID("Spotify")])
}

@Test func appThatQuitWhilePlayingCountsFromQuit() {
    var recent = RecentApps(idleTimeout: 600)
    recent.observe([app("Slack", playing: true)], at: t0)
    recent.observe([], at: t0.addingTimeInterval(3600))
    #expect(recent.visibleIdle(excluding: [], at: t0.addingTimeInterval(3900)).map(\.id) == [AppID("Slack")])
}

@Test func playingAppsAreExcludedAndResultIsSortedByName() {
    var recent = RecentApps(idleTimeout: 600)
    recent.observe([app("b", playing: true), app("a", playing: true), app("c", playing: true)], at: t0)
    recent.observe([app("b", playing: false), app("a", playing: false), app("c", playing: true)], at: t0.addingTimeInterval(1))
    let visible = recent.visibleIdle(excluding: [AppID("c")], at: t0.addingTimeInterval(2))
    #expect(visible.map(\.id) == [AppID("a"), AppID("b")])
}

@Test func hiddenAppReappearsWhenItPlaysAgain() {
    var recent = RecentApps(idleTimeout: 600)
    recent.observe([app("Spotify", playing: true)], at: t0)
    recent.observe([app("Spotify", playing: false)], at: t0.addingTimeInterval(1))
    recent.observe([app("Spotify", playing: true)], at: t0.addingTimeInterval(2000))
    recent.observe([app("Spotify", playing: false)], at: t0.addingTimeInterval(2001))
    #expect(recent.visibleIdle(excluding: [], at: t0.addingTimeInterval(2100)).map(\.id) == [AppID("Spotify")])
}

@Test func remembersNamesOfAppsThatPlayed() {
    var recent = RecentApps()
    recent.observe([AppGroup(id: AppID("com.spotify.client"), displayName: "Spotify", processObjectIDs: [],
                             isPlaying: true, outputDeviceUIDs: [])], at: t0)
    #expect(recent.name(for: AppID("com.spotify.client")) == "Spotify")
    #expect(recent.name(for: AppID("unknown")) == nil)
}
