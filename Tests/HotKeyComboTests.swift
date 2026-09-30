import AppKit
import Carbon

private func keyEvent(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                     windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                     isARepeat: false, keyCode: UInt16(keyCode))!
}

private func testDefaultLabel() {
    expect(HotKeyCombo.defaultVoiceReminder.label == "⌃⌘R", "default is ⌃⌘R, got \(HotKeyCombo.defaultVoiceReminder.label)")
}

private func testLabelOrder() {
    let combo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
    expect(combo.label == "⌃⌥⇧⌘T", "Apple order ⌃⌥⇧⌘, got \(combo.label)")
}

private func testFromEvent() {
    let combo = HotKeyCombo(event: keyEvent(kVK_ANSI_M, [.command, .option]))
    expect(combo?.label == "⌥⌘M", "records ⌥⌘M, got \(String(describing: combo?.label))")
    expect(HotKeyCombo(event: keyEvent(kVK_ANSI_C, [.command])) == nil, "⌘C alone is rejected (would break copy)")
    expect(HotKeyCombo(event: keyEvent(kVK_ANSI_R, [.command, .shift])) == nil, "⇧⌘R is rejected (browser hard reload)")
    expect(HotKeyCombo(event: keyEvent(kVK_ANSI_M, [])) == nil, "plain M is rejected")
    expect(HotKeyCombo(event: keyEvent(kVK_ANSI_M, [.shift])) == nil, "⇧M alone is rejected")
    expect(HotKeyCombo(event: keyEvent(kVK_Tab, [.control])) == nil, "⌘Tab (unsupported key) is rejected")
}

private func testCodable() {
    let combo = HotKeyCombo.defaultVoiceReminder
    let decoded = try! JSONDecoder().decode(HotKeyCombo.self, from: try! JSONEncoder().encode(combo))
    expect(decoded == combo, "round-trips through JSON")
}

let hotKeyTests: [(String, () -> Void)] = [
    ("hotKeyDefaultLabel", testDefaultLabel),
    ("hotKeyLabelOrder", testLabelOrder),
    ("hotKeyFromEvent", testFromEvent),
    ("hotKeyCodable", testCodable),
]
