import CoreText
import Foundation

/// Fonts loaded from files, so a video does not depend on what is installed.
/// Register them before rendering starts.
public enum Fonts {
    /// Registers a font file, or every `.ttf`, `.otf` and `.ttc` in a folder, for this process.
    /// Returns the PostScript names to use with `Font.custom`.
    @discardableResult
    public static func register(at url: URL) throws -> [String] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            throw FlipbookError.font("there is no file at \(url.path)")
        }
        let files = isFolder.boolValue
            ? try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.path < $1.path }
            : [url]

        var names: [String] = []
        for file in files {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else {
                throw FlipbookError.font("\(file.lastPathComponent) is not a font file")
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) {
                let failure = error?.takeRetainedValue()
                // Registering the same file twice is fine.
                let known = failure.map { CFErrorGetCode($0) == CTFontManagerError.alreadyRegistered.rawValue } ?? false
                guard known else {
                    throw FlipbookError.font("cannot register \(file.lastPathComponent): \(failure.map { "\($0)" } ?? "unknown error")")
                }
            }
            names += descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        }
        return names
    }
}
