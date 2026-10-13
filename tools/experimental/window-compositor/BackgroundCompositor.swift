import CoreImage
import Foundation

final class BackgroundCompositor {
    private let key: CIColorKernel

    init() throws {
        guard let key = CIColorKernel(source: """
        kernel vec4 extractForeground(__sample pixel, vec4 first, vec4 second, vec4 third, float tolerance, float softness) {
            vec3 rgb = unpremultiply(pixel).rgb;
            float delta = min(distance(rgb, first.rgb), min(distance(rgb, second.rgb), distance(rgb, third.rgb)));
            float alpha = smoothstep(tolerance, tolerance + softness, delta);
            return pixel * alpha;
        }
        """) else {
            throw NSError(domain: "CodexBackdrop.Compositor", code: 1)
        }
        self.key = key
    }

    func compose(frame: CIImage, background: CIImage, palette: [CIColor], protectedAreas: [CGRect]) throws -> CIImage {
        guard palette.count == 3, let foreground = key.apply(extent: frame.extent, arguments: [frame, palette[0], palette[1], palette[2], 0.008, 0.018]) else {
            throw NSError(domain: "CodexBackdrop.Compositor", code: 2)
        }
        var mask = CIImage(color: .clear).cropped(to: frame.extent)
        for area in protectedAreas {
            let region = area.intersection(frame.extent)
            if !region.isNull {
                mask = CIImage(color: .white).cropped(to: region).composited(over: mask)
            }
        }
        let safeForeground = frame.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: foreground,
            kCIInputMaskImageKey: mask,
        ])
        return safeForeground.composited(over: background.cropped(to: frame.extent))
    }
}
