import Foundation

// Port of AdManager.kt — stub for now: no ad SDK is integrated yet (the Android build uses
// AdMob; the iOS equivalent is Google Mobile Ads SDK for iOS, to be wired in a later pass).
// `show` calls its completion immediately so hints/rewards/interstitials still work end-to-end
// during development.
enum RewardedAdManager {
    static func show(onEarned: @escaping () -> Void) { onEarned() }
}
enum InterstitialAdManager {
    static func show(_ completion: @escaping () -> Void) { completion() }
}
