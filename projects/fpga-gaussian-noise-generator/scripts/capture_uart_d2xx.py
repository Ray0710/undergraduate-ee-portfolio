"""Read the Digilent FTDI B channel on Windows and save a timed UART capture."""

import argparse
import ctypes as ct
from ctypes import wintypes as win
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys
import time


def bind(driver, name, *arguments):
    function = getattr(driver, name)
    function.argtypes = arguments
    function.restype = win.DWORD

    def checked(*values):
        status = function(*values)
        if status:
            raise OSError(f'{name} returned FTDI status {status}')

    return checked


def uart_serial(driver, chosen_serial):
    count = win.DWORD()
    dword_ptr = ct.POINTER(win.DWORD)
    bind(driver, 'FT_CreateDeviceInfoList', dword_ptr)(ct.byref(count))
    info = bind(driver, 'FT_GetDeviceInfoDetail', win.DWORD, *[dword_ptr] * 4,
                ct.c_char_p, ct.c_char_p, ct.POINTER(win.HANDLE))
    matches = []
    for index in range(count.value):
        fields = [win.DWORD() for _ in range(4)]
        serial = ct.create_string_buffer(16)
        description = ct.create_string_buffer(64)
        device = win.HANDLE()
        info(index, *(ct.byref(field) for field in fields), serial, description, ct.byref(device))
        if description.value == b'Digilent Adept USB Device B':
            if chosen_serial is None or serial.value == chosen_serial.encode('ascii'):
                matches.append(serial.value)
    if len(matches) != 1:
        raise OSError(f'Expected one Digilent UART B channel, found {len(matches)}')
    return matches[0]


def capture(driver, serial, target, seconds, baud):
    handle = win.HANDLE()
    handle_ptr = ct.POINTER(win.HANDLE)
    dword_ptr = ct.POINTER(win.DWORD)
    bind(driver, 'FT_OpenEx', ct.c_char_p, win.DWORD, handle_ptr)(serial, 1, ct.byref(handle))
    failure = None
    elapsed = 0.0
    longest_idle = 0.0
    byte_count = 0
    started_at = None
    try:
        bind(driver, 'FT_SetBaudRate', win.HANDLE, win.DWORD)(handle, baud)
        bind(driver, 'FT_SetDataCharacteristics', win.HANDLE, ct.c_ubyte, ct.c_ubyte, ct.c_ubyte)(handle, 8, 0, 0)
        bind(driver, 'FT_SetFlowControl', win.HANDLE, ct.c_ushort, ct.c_ubyte, ct.c_ubyte)(handle, 0, 0, 0)
        bind(driver, 'FT_SetTimeouts', win.HANDLE, win.DWORD, win.DWORD)(handle, 100, 100)
        bind(driver, 'FT_Purge', win.HANDLE, win.DWORD)(handle, 1)  # Discard RX before timing starts.
        queue_status = bind(driver, 'FT_GetQueueStatus', win.HANDLE, dword_ptr)
        read = bind(driver, 'FT_Read', win.HANDLE, ct.c_void_p, win.DWORD, dword_ptr)
        available, received = win.DWORD(), win.DWORD()
        buffer = ct.create_string_buffer(16384)
        with target.open('xb') as output:
            started_at = datetime.now().astimezone().isoformat(timespec='seconds')
            start = time.perf_counter()
            last_data = start
            deadline = start + seconds
            print(f'Receiving UART B at {baud} 8N1 for {seconds:g} s into {target}', flush=True)
            try:
                while time.perf_counter() < deadline:
                    queue_status(handle, ct.byref(available))
                    if not available.value:
                        time.sleep(0.005)
                        continue
                    read(handle, buffer, min(available.value, len(buffer)), ct.byref(received))
                    if received.value:
                        output.write(buffer[:received.value])
                        byte_count += received.value
                        now = time.perf_counter()
                        longest_idle = max(longest_idle, now - last_data)
                        last_data = now
            except (OSError, KeyboardInterrupt) as error:
                failure = str(error) or 'Capture interrupted'
            end = time.perf_counter()
            elapsed = end - start
            longest_idle = max(longest_idle, end - last_data)
    finally:
        try:
            bind(driver, 'FT_Close', win.HANDLE)(handle)
        except OSError as error:
            failure = failure or str(error)
    return dict(started_at=started_at, requested_seconds=seconds, elapsed_seconds=elapsed,
                bytes_received=byte_count, longest_read_gap_seconds=longest_idle, capture_error=failure)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output_directory', type=Path, help='new directory for raw data, decoded samples, and summary')
    parser.add_argument('--seconds', type=float, default=60)
    parser.add_argument('--serial', help='serial including B suffix when multiple boards are present')
    parser.add_argument('--profile', choices=('v2', 'v3'), default='v2', help='bitstream on the FPGA')
    args = parser.parse_args()
    if not 0 < args.seconds < float('inf'):
        parser.error('--seconds must be finite and positive')
    baud, pair_clocks = (1_000_000, 1441) if args.profile == 'v3' else (115_200, 12523)
    driver = ct.WinDLL(r'C:\Windows\System32\ftd2xx.dll')
    serial = uart_serial(driver, args.serial)
    folder = args.output_directory.resolve()
    folder.mkdir(parents=True, exist_ok=False)
    raw = folder / 'uart_raw.bin'
    decoded = folder / 'gaussian_samples.txt'
    result = capture(driver, serial, raw, args.seconds, baud)

    decoder = Path(__file__).with_name('decode_uart_capture.py')
    output = subprocess.check_output([sys.executable, str(decoder), str(raw), str(decoded)], text=True)
    result.update(json.loads(output))
    sequences = [int(line.split(' ', 1)[0]) for line in decoded.read_text(encoding='utf-8').splitlines()[1:]]
    steps = [(b - a) & 0xffff for a, b in zip(sequences, sequences[1:])]
    result.update(first_sequence=sequences[0] if sequences else None,
                  last_sequence=sequences[-1] if sequences else None,
                  sequence_wraps=sum(a == 65535 and b == 0 for a, b in zip(sequences, sequences[1:])),
                  inferred_missing_packets=sum(n - 1 for n in steps if 1 < n < 32768),
                  duplicate_sequences=steps.count(0),
                  backward_or_reset_events=sum(n >= 32768 for n in steps),
                  packets_per_second=len(sequences) / result['elapsed_seconds'])
    result['expected_packets_per_second'] = 12_000_000 / pair_clocks
    summary = json.dumps(result, indent=2)
    (folder / 'capture_summary.json').write_text(summary + '\n', encoding='utf-8')
    print(summary)
    if result['capture_error'] or not sequences:
        sys.exit(1)


if __name__ == '__main__':
    main()
