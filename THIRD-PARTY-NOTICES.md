# Third-party notices

## agent-device (Callstack)

`Tools/duo/Guest/DuoGuest.swift` and the pose-verification logic in `Tools/duo/Sources/DuoKit/` are derived in part from
`apple/fold-helper/Fold.m` in **agent-device** v0.21.36 (<https://github.com/callstack/agent-device>), translated from
Objective-C to Swift: the vendor-defined HID event used to move the hinge and rotate the device, the CoreMotion hinge-angle
readback, and the read-until-settled policy. Nothing from `apple/snapshot-bridge` (which carries idb's licence) is used.

MIT License

Copyright (c) 2026 Callstack

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
