import CoreGraphics

/// The spacing scale (design-system.md, "간격"). Pick by role, not by look: the same role gets the same value on every
/// screen. Optical nudges that line text up with a system inset are the only other numbers allowed, with a comment.
enum Spacing {
    /// Lines of one item: a row's title, preview and meta lines; a label and its value; a list of warnings.
    static let xxs: CGFloat = 2
    /// A title and the control it names; a caption attached to an element; the vertical inset of an input surface.
    static let xs: CGFloat = 4
    /// Siblings in one group: buttons, chips, inline items, the lines of a section; the horizontal inset of an input.
    static let s: CGFloat = 8
    /// Sections of a compact surface (Save Popup, sheets).
    static let m: CGFloat = 12
    /// Sections of a pane; the inset of the inspector, popovers and the Save Popup.
    static let l: CGFloat = 16
    /// The inset of a sheet (the macOS standard margin).
    static let xl: CGFloat = 20
    /// The inset of the reading area (the drop body).
    static let xxl: CGFloat = 24
}
