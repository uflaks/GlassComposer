//
//  SpeechTranscriptAssembler.swift
//  MaloryComposer
//

import Foundation

/// Joins composer text already in the field with live on-device dictation.
public enum SpeechTranscriptAssembler {
    public static func compose(prefix: String, finalized: String, volatile: String) -> String {
        let spoken = finalized + volatile
        if prefix.isEmpty {
            return spoken
        }
        if spoken.isEmpty {
            return prefix
        }
        if prefix.last?.isWhitespace == true {
            return prefix + spoken
        }
        return "\(prefix) \(spoken)"
    }
}
