//
//  Localization.swift
//  GlassComposer
//

import Foundation

/// A built-in string. The package ships no translations, so the key is the English text; apps that
/// localize can override these keys in their own catalog. No string catalog in the package means it
/// also builds with xtool on Linux, where Apple's xcstringstool is not available.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}
