import SwiftUI

// Partagé avec le mode support de l'app Mac (apps/mac/project.yml) :
// une seule image de plateforme pour HelperModel, UIImage sur iPhone, NSImage sur Mac.
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#else
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#endif
