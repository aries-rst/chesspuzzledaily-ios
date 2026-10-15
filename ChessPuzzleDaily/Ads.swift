import Foundation
import SwiftUI
import UIKit
import GoogleMobileAds

// Port of AdManager.kt — real Google Mobile Ads SDK wiring, same shape as the Android build:
// a banner on the home screen only, an interstitial every few training/rush rounds, and a
// rewarded ad for hints and for the archive/streak-freeze unlocks.
//
// Portfolio rule (mirrors Android's `ADS_ENABLED = false` in AdManager.kt): real ads stay OFF
// until this is explicitly flipped to `true` for the production App Store build — a TestFlight
// build is still effectively "release", so a debug-only flag wouldn't protect testers the way it
// does on Android. While `adsEnabled` is false: the SDK never starts, the banner renders nothing,
// interstitials continue instantly, and rewarded ads grant the reward instantly.
let adsEnabled = false

/// Real AdMob identifiers (from the user's AdMob console — these are public identifiers meant to
/// ship inside the app binary, not secrets).
/// AdMob App ID (goes in Info.plist as `GADApplicationIdentifier`): ca-app-pub-9638598348702189~1410340420
enum AdUnitIds {
    static let banner = "ca-app-pub-9638598348702189/9097258753"
    static let interstitial = "ca-app-pub-9638598348702189/7541643663"
    static let rewarded = "ca-app-pub-9638598348702189/5167506621"
}

enum AdsInit {
    private(set) static var ready = false

    /// Starts the Google Mobile Ads SDK once and preloads the first interstitial/rewarded ad.
    /// No-op while `adsEnabled` is false. Call once at app launch.
    static func start() {
        guard adsEnabled, !ready else { return }
        MobileAds.shared.start { _ in
            ready = true
            InterstitialAdManager.preload()
            RewardedAdManager.preload()
        }
    }
}

/// The topmost presented view controller, used to present full-screen ads and to host the
/// banner's `rootViewController` (needed for click-through / store-sheet presentation).
private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?.rootViewController
    var top = root
    while let presented = top?.presentedViewController { top = presented }
    return top
}

// MARK: - Interstitial

enum InterstitialAdManager {
    private static var ad: InterstitialAd?
    private static var loading = false
    private static var delegate: InterstitialDelegate?

    static func preload() {
        guard adsEnabled, AdsInit.ready, ad == nil, !loading else { return }
        loading = true
        Task { @MainActor in
            do {
                ad = try await InterstitialAd.load(with: AdUnitIds.interstitial, request: GoogleMobileAds.Request())
            } catch {
                ad = nil
            }
            loading = false
        }
    }

    /// Shows the ad if one is ready; `completion` always runs exactly once.
    static func show(_ completion: @escaping () -> Void) {
        guard adsEnabled, let a = ad, let vc = topViewController() else {
            completion()
            preload()
            return
        }
        ad = nil
        let d = InterstitialDelegate { completion(); preload() }
        delegate = d
        a.fullScreenContentDelegate = d
        a.present(from: vc)
    }
}

private final class InterstitialDelegate: NSObject, FullScreenContentDelegate {
    private var fired = false
    private let onDone: () -> Void
    init(_ onDone: @escaping () -> Void) { self.onDone = onDone }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { fire() }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { fire() }
    private func fire() { guard !fired else { return }; fired = true; onDone() }
}

// MARK: - Rewarded

enum RewardedAdManager {
    private static var ad: RewardedAd?
    private static var loading = false
    private static var delegate: RewardedDelegate?

    static func preload() {
        guard adsEnabled, AdsInit.ready, ad == nil, !loading else { return }
        loading = true
        Task { @MainActor in
            do {
                ad = try await RewardedAd.load(with: AdUnitIds.rewarded, request: GoogleMobileAds.Request())
            } catch {
                ad = nil
            }
            loading = false
        }
    }

    /// `onEarned` runs only if the reward was granted. With ads off (or no fill), the reward is
    /// instant so the player is never blocked — same contract as the Android original.
    static func show(onEarned: @escaping () -> Void) {
        guard adsEnabled, let a = ad, let vc = topViewController() else {
            onEarned()
            preload()
            return
        }
        ad = nil
        let d = RewardedDelegate { preload() }
        delegate = d
        a.fullScreenContentDelegate = d
        a.present(from: vc) { onEarned() }
    }
}

private final class RewardedDelegate: NSObject, FullScreenContentDelegate {
    private let onDone: () -> Void
    init(_ onDone: @escaping () -> Void) { self.onDone = onDone }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { onDone() }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { onDone() }
}

// MARK: - Banner

/// Adaptive-width banner for the home screen only (never on the board). Renders nothing while
/// ads are off — mirrors Android's `BannerAd` composable.
struct BannerAdView: View {
    var body: some View {
        if adsEnabled, AdsInit.ready {
            BannerContainer().frame(height: 50)
        }
    }
}

private struct BannerContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let width = UIScreen.main.bounds.width
        let banner = BannerView(adSize: largeAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = AdUnitIds.banner
        banner.rootViewController = topViewController()
        banner.load(GoogleMobileAds.Request())
        return banner
    }
    func updateUIView(_ uiView: BannerView, context: Context) {}
}
