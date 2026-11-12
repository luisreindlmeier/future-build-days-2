import SwiftUI
import UIKit

/// Styles the navigation bar once: clear background, ink text.
enum Appearance {
    static func configure() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.ink)]
        navigation.titleTextAttributes = [.foregroundColor: UIColor(Color.ink)]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = navigation
        bar.scrollEdgeAppearance = navigation
        bar.compactAppearance = navigation
        bar.tintColor = UIColor(Color.ink)
    }
}
