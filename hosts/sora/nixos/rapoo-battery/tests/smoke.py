"""Synthetic hidraw/UHID transports only; never touches real input hardware."""
import os
import select
import struct
import subprocess
import sys
import threading
import time
import tty

BINARY = sys.argv[1]
DESCRIPTOR = bytes.fromhex("050c0901a1010506092015002564750895018102c0")


def read_exact(fd, size, timeout=4):
    data = b""
    deadline = time.monotonic() + timeout
    while len(data) < size:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([fd], [], [], remaining)[0], (size, data)
        data += os.read(fd, size - len(data))
    return data


class Device:
    def __init__(self, responses):
        self.master, self.slave = os.openpty()
        tty.setraw(self.slave)
        self.path = os.ttyname(self.slave)
        self.responses = responses
        self.requests = []
        self.errors = []
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.serve)
        self.thread.start()

    def serve(self):
        try:
            while not self.stop.is_set():
                if not select.select([self.master], [], [], 0.05)[0]:
                    continue
                request = read_exact(self.master, 32)
                assert request == b"\xba\xb0" + bytes(30), request
                self.requests.append(request)
                index = min(len(self.requests) - 1, len(self.responses) - 1)
                response = self.responses[index]
                if response is not None:
                    os.write(self.master, response)
        except BaseException as error:
            self.errors.append(error)

    def close(self):
        self.stop.set()
        self.thread.join(timeout=5)
        os.close(self.master)
        os.close(self.slave)
        assert not self.thread.is_alive()
        assert not self.errors, self.errors


for value in [0, 42, 100]:
    device = Device([bytes([0xbb, 0xb0, value])])
    try:
        result = subprocess.run([BINARY, "--device", device.path], capture_output=True, timeout=5)
        assert result.returncode == 0, result.stderr
        assert result.stdout == f"{value}%\n".encode(), result.stdout
        assert len(device.requests) == 1
    finally:
        device.close()

for response in [None, b"\xbb\xb0\x65", b"\xba\xb0\x2a", b"\xbb"]:
    device = Device([response])
    try:
        result = subprocess.run([BINARY, "--device", device.path], capture_output=True, timeout=5)
        assert result.returncode != 0 and b"did not answer" in result.stderr, result
    finally:
        device.close()

master, slave = os.openpty()
tty.setraw(slave)
device = Device([b"\xbb\xb0\x2a", b"\xbb\xb0\x2b"])
process = subprocess.Popen([BINARY, "--daemon", "--device", device.path, "--uhid", os.ttyname(slave)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    create = read_exact(master, 280 + len(DESCRIPTOR))
    expected = (
        struct.pack("=I", 11)
        + b"Rapoo VT9 Pro".ljust(128, b"\0")
        + b"rapoo-vt9pro".ljust(64, b"\0")
        + b"24ae:185a".ljust(64, b"\0")
        + struct.pack("=HHIIII", len(DESCRIPTOR), 3, 0x24ae, 0x185a, 0x100, 0)
        + DESCRIPTOR
    )
    assert create == expected
    os.write(master, struct.pack("=IIBB", 9, 123, 0, 0))
    assert read_exact(master, 14) == struct.pack("=IIHHBB", 10, 123, 0, 2, 0, 42)
    assert read_exact(master, 7) == struct.pack("=IHB", 12, 1, 43)
    os.write(master, struct.pack("=IIBB", 9, 456, 0, 0))
    assert read_exact(master, 14) == struct.pack("=IIHHBB", 10, 456, 0, 2, 0, 43)
    assert process.poll() is None
    process.terminate()
    process.wait(timeout=2)
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    device.close()
    os.close(master)
    os.close(slave)

for args in [["--unknown"], ["--device"], ["--uhid"], ["--device", "/no/such/rapoo-test-device"]]:
    assert subprocess.run([BINARY, *args], capture_output=True, timeout=2).returncode != 0
assert subprocess.run([BINARY, "--help"], capture_output=True, timeout=2).returncode == 0
print("PASS: synthetic HID requests, percentages, invalid reports/timeouts, UHID layout/replies/updates, CLI failures")
