import CoreGraphics
import Foundation
import ImageIO
import LoupeCLIModel

enum ScreenshotCropper {
    static func write(source: URL, rect: CGRect, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = image.cropping(to: rect),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
            throw CLIError("Could not crop target screenshot")
        }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CLIError("Could not save target screenshot crop")
        }
    }
}
