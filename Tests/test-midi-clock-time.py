#!/usr/bin/env python3
"""Fail when a MIDI clock pulse is dated by main-queue delivery instead of the
driver's CoreMIDI packet stamp, or when the receipt-time fallback disappears.

Issue #108 records the receipt-time gap: tempo following used the moment a pulse
reached the main queue, so other main-thread work stretched the intervals the
tempo is measured from. The clock path must resolve the packet stamp through
`MIDIClockTimestamp`, keep receipt time as the fallback (a zero stamp means "as
soon as possible", and a driver may use another epoch), and must not hand
`ProcessInfo.systemUptime` straight to the clock handler again.
"""
import re
import sys
from pathlib import Path

RECEIPT_DIRECTLY = 'handleMIDIClock(status, source: source, at: ProcessInfo.processInfo.systemUptime)'


def main(root: Path) -> int:
    errors: list[str] = []

    session = (root / 'Sources/SessionSettings.swift').read_text()
    if 'enum MIDIClockTimestamp' not in session:
        errors.append('Sources/SessionSettings.swift has no MIDIClockTimestamp resolver')
    for member in ('static let maximumLatency', 'static func seconds(', 'static func at('):
        if member not in session:
            errors.append(f'MIDIClockTimestamp is missing {member}')
    if not re.search(r'receipt\.isFinite, abs\(packet - receipt\) <= maximumLatency else \{ return receipt \}',
                     session):
        errors.append('MIDIClockTimestamp.at no longer falls back to the receipt time '
                      'outside the latency window')

    header = (root / 'Sources/Synth.h').read_text()
    if 'SKMIDITimedEvent' not in header or 'sk_read_midi_timed' not in header:
        errors.append('The native reader has no packet-timed callback')
    native = (root / 'Sources/Synth.c').read_text()
    if 'callback(context,status,0,0,p->timeStamp)' not in native:
        errors.append('System realtime messages lost their current packet stamp')
    input_source = (root / 'Sources/MIDIInput.swift').read_text()
    for required in ('sk_read_midi_timed(list, receiveInput,', 'MIDIClockTimestamp.at(', 'mach_timebase_info('):
        if required not in input_source:
            errors.append(f'Sources/MIDIInput.swift no longer uses {required}')
    if 'receiver.packetTicks' in input_source or 'sk_read_midi_first_timestamp' in input_source:
        errors.append('MIDI input reuses the first packet stamp for the list')

    store = (root / 'Sources/Store.swift').read_text()
    if not re.search(r'private func handleMIDI\(_ status: UInt8, _ a: UInt8, _ b: UInt8, source: Int32, at time: Double\)',
                     store):
        errors.append('PerformanceStore.handleMIDI does not take the event timestamp')
    if 'handleMIDIClock(status, source: source, at: time)' not in store:
        errors.append('the clock dispatch does not use the event timestamp')
    if RECEIPT_DIRECTLY in store:
        errors.append('PerformanceStore still dates clock pulses at main-queue receipt '
                      f'({RECEIPT_DIRECTLY})')
    if 'func debugReceiveMIDIClock(' not in store:
        errors.append('the test entry point debugReceiveMIDIClock is missing')

    tests = (root / 'Tests/MetronomeSettingsTests.swift').read_text()
    if 'the receipt-only path must show the delivery delay' not in tests:
        errors.append('Tests/MetronomeSettingsTests.swift lost the receipt-time regression witness')
    if 'the packet stamp must recover the true tempo' not in tests:
        errors.append('Tests/MetronomeSettingsTests.swift lost the packet-stamp assertion')

    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    print('PASS: MIDI clock pulses are dated by the CoreMIDI packet stamp, '
          'with the receipt-time fallback and its regression witness intact')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(Path(__file__).resolve().parents[1]))
