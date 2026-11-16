import Foundation

public enum KilnError: Error, Equatable, Sendable {
    case unsupportedPair(ConversionKey)
    case corruptInput(String)
    case nameCollision(String)
    case diskFull
    case cancelled
    case encryptedPDF(String)
    case needsFFmpeg
    case unsafeInput(String)
    case tooLarge(String)
    case io(String)

    public var message: String {
        switch self {
        case .unsupportedPair(let k): "Kiln can't convert \(k.input.label) to \(k.output.label)."
        case .corruptInput(let n): "\u{201C}\(n)\u{201D} can't be read. It may be damaged, or not the type its name says."
        case .nameCollision(let n): "A file named \u{201C}\(n)\u{201D} already exists there, so nothing was written."
        case .diskFull: "The disk is full. Free some space and try again. Any partial output was removed."
        case .cancelled: "Cancelled. Any partial output was removed."
        case .encryptedPDF(let n): "\u{201C}\(n)\u{201D} is password-protected. Remove the password first, then convert it."
        case .unsafeInput(let n): "\u{201C}\(n)\u{201D} contains links or paths that lead outside itself, so Kiln did not process it."
        case .tooLarge(let n): "\u{201C}\(n)\u{201D} is too big for Kiln to handle safely. Try a smaller file or fewer pages."
        case .needsFFmpeg: "This conversion needs ffmpeg. Install it (for example with Homebrew) and Kiln will use it."
        case .io(let m): "Something went wrong: \(m)"
        }
    }

    /// Map any thrown error to a typed one.
    public static func from(_ error: Error, file: String = "") -> KilnError {
        if let e = error as? KilnError { return e }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError)
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC)) { return .diskFull }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteFileExistsError { return .nameCollision(file) }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? Error, (under as NSError) != ns {
            let mapped = from(under, file: file)
            if case .io = mapped {} else { return mapped }
        }
        return .io(ns.localizedDescription)
    }
}
