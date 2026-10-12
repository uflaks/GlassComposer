//
//  Localization.swift
//  GlassComposer
//

import Foundation

/// Looks a built-in string up in the package's string catalog.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
