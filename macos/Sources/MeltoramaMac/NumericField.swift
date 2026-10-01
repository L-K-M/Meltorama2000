import AppKit
import SwiftUI

enum InspectorNumberFormat {
    static func display(_ value: Float, percent: Bool = false, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = percent ? 0 : 2
        formatter.maximumFractionDigits = 2
        let displayed = percent ? value * 100 : value
        return formatter.string(from: NSNumber(value: displayed)) ?? String(displayed)
    }

    static func parse(_ text: String, percent: Bool = false, locale: Locale = .current) -> Float? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if percent && (trimmed.hasSuffix("%") || trimmed.hasSuffix("％")) {
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let decimal = locale.decimalSeparator ?? "."
        let localized = decimal == "." ? trimmed : trimmed.replacingOccurrences(of: decimal, with: ".")
        var canonical = "", hasDigit = false, hasDecimal = false
        for character in localized {
            if (character == "-" || character == "+") && canonical.isEmpty {
                canonical.append(character)
            } else if character == "." && !hasDecimal {
                canonical.append(character)
                hasDecimal = true
            } else if let digit = character.wholeNumberValue, (0...9).contains(digit) {
                canonical.append(String(digit))
                hasDigit = true
            } else {
                return nil
            }
        }
        guard hasDigit, let value = Float(canonical), value.isFinite else { return nil }
        return percent ? value / 100 : value
    }
}

/// Keystrokes belong to the editing buffer. Only commit can change the value,
/// so an intermediate "0" cannot clamp a user's eventual "0.45" to "0.05".
struct NumericEditingBuffer {
    private(set) var text: String
    private(set) var isDirty = false
    init(value: Float, percent: Bool = false, locale: Locale = .current) { text = InspectorNumberFormat.display(value, percent: percent, locale: locale) }
    mutating func replaceText(_ text: String) { if self.text != text { isDirty = true }; self.text = text }
    mutating func synchronize(value: Float, percent: Bool = false, locale: Locale = .current) { text = InspectorNumberFormat.display(value, percent: percent, locale: locale); isDirty = false }

    mutating func commit(currentValue: Float, range: ClosedRange<Float>, percent: Bool = false, locale: Locale = .current) -> Float {
        guard isDirty else { synchronize(value: currentValue, percent: percent, locale: locale); return currentValue }
        let result: Float
        if let parsed = InspectorNumberFormat.parse(text, percent: percent, locale: locale) {
            result = min(range.upperBound, max(range.lowerBound, parsed))
        } else {
            result = currentValue.isFinite ? currentValue : range.lowerBound
        }
        synchronize(value: result, percent: percent, locale: locale)
        return result
    }
}

struct InspectorNumericField: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var percent = false
    var body: some View {
        HStack(spacing: 3) {
            NativeInspectorNumericField(title: title, value: $value, range: range, percent: percent).frame(width: 54, height: 22)
            if percent { Text("%").foregroundStyle(.secondary).accessibilityHidden(true) }
        }
    }
}

/// AppKit's end-edit notification is synchronous. SwiftUI focus onChange runs
/// later, which allowed Save to serialize the previous value of an active field.
struct NativeInspectorNumericField: NSViewRepresentable {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let percent: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.alignment = .right
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.usesSingleLineMode = true
        field.isEnabled = context.environment.isEnabled
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.setAccessibilityLabel(LF(percent ? "%@ percentage" : "%@ value", L(title)))
        field.stringValue = context.coordinator.buffer.text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = context.environment.isEnabled
        guard !context.coordinator.editing else { return }
        context.coordinator.buffer.synchronize(value: value, percent: percent)
        if field.stringValue != context.coordinator.buffer.text { field.stringValue = context.coordinator.buffer.text }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        if coordinator.editing { coordinator.commit(field) }
        field.delegate = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeInspectorNumericField
        var buffer: NumericEditingBuffer
        var editing = false

        init(_ parent: NativeInspectorNumericField) {
            self.parent = parent
            buffer = NumericEditingBuffer(value: parent.value, percent: parent.percent)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            editing = true
            ((notification.object as? NSTextField)?.currentEditor() as? NSTextView)?.allowsUndo = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            buffer.replaceText(field.currentEditor()?.string ?? field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            editing = false
            commit(field)
        }

        @objc func submit(_ field: NSTextField) { commit(field) }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), let field = control as? NSTextField else { return false }
            buffer.synchronize(value: parent.value, percent: parent.percent)
            field.stringValue = buffer.text
            textView.string = buffer.text
            field.window?.makeFirstResponder(nil)
            return true
        }

        func commit(_ field: NSTextField) {
            buffer.replaceText(field.currentEditor()?.string ?? field.stringValue)
            if buffer.isDirty && InspectorNumberFormat.parse(buffer.text, percent: parent.percent) == nil { NSSound.beep() }
            let committed = buffer.commit(currentValue: parent.value, range: parent.range, percent: parent.percent)
            if committed != parent.value { parent.value = committed }
            field.stringValue = buffer.text
        }

        func discard(_ field: NSTextField) {
            buffer.synchronize(value: parent.value, percent: parent.percent)
            field.stringValue = buffer.text
            field.currentEditor()?.string = buffer.text
        }
    }
}

/// Explicit document commands commit the active field without taking focus.
/// Background autosave must serialize the model without calling this helper.
func commitPendingNumericEditing(in window: NSWindow) {
    guard let content = window.contentView else { return }
    func commit(in view: NSView) {
        if let field = view as? NSTextField, field.currentEditor() != nil,
           let coordinator = field.delegate as? NativeInspectorNumericField.Coordinator {
            coordinator.commit(field)
        }
        for child in view.subviews { commit(in: child) }
    }
    commit(in: content)
}

/// Revert validates first, then drops the old draft before replacing the model.
/// Ending editing with unchanged text cannot reapply that draft to the new state.
func discardPendingNumericEditing(in window: NSWindow) {
    guard let content = window.contentView else { return }
    var foundEditor = false
    func discard(in view: NSView) {
        if let field = view as? NSTextField, field.currentEditor() != nil,
           let coordinator = field.delegate as? NativeInspectorNumericField.Coordinator {
            coordinator.discard(field)
            foundEditor = true
        }
        for child in view.subviews { discard(in: child) }
    }
    discard(in: content)
    if foundEditor { window.endEditing(for: nil) }
}
