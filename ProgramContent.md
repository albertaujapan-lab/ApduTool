# ApduTool: Technical Architecture and Developer Guide
> **Target Audience:** Junior iOS developers, embedded/hardware enthusiasts, and smart card engineers.  
> **Topic:** How iOS communicates with ACS Smart Card Readers over USB using Apple's `CryptoTokenKit`, and how to build & test this multiplatform project using GitHub Actions.

---

## Table of Contents
1. [Introduction & Project Overview](#1-introduction--project-overview)
2. [Smart Card & USB Fundamentals: Demystifying the Concepts](#2-smart-card--usb-fundamentals-demystifying-the-concepts)
   - [What is a Smart Card?](#what-is-a-smart-card)
   - [What is an APDU? (Application Protocol Data Unit)](#what-is-an-apdu-application-protocol-data-unit)
   - [APDU vs. TPDU: What is the Difference?](#apdu-vs-tpdu-what-is-the-difference)
   - [What is an ATR? (Answer To Reset)](#what-is-an-atr-answer-to-reset)
   - [What is USB CCID?](#what-is-usb-ccid)
   - [What is an Escape Command?](#what-is-an-escape-command)
3. [Apple Platform Architecture: iOS vs. macOS](#3-apple-platform-architecture-ios-vs-macos)
   - [The iOS Reality: CryptoTokenKit & Sandboxing](#the-ios-reality-cryptotokenkit--sandboxing)
   - [The macOS Difference: Native PC/SC (`winscard`)](#the-macos-difference-native-pcsc-winscard)
   - [Hardware Requirements for iOS (Lightning & USB-C)](#hardware-requirements-for-ios-lightning--usb-c)
   - [The Critical Entitlement: `com.apple.security.smartcard`](#the-critical-entitlement-comapplesecuritysmartcard)
4. [Software Architecture & Component Walkthrough](#4-software-architecture--component-walkthrough)
   - [Architecture Diagram (MVVM)](#architecture-diagram-mvvm)
   - [The Core Engine: `Pcsc.swift`](#the-core-engine-pcscswift)
   - [Deep Dive: The `divideAPDU()` Parsing Algorithm & `ApduCommand`](#deep-dive-the-divideapdu-parsing-algorithm--apducommand)
   - [Automatic Handling of Data > 254 Bytes (Command Chaining & Response Looping)](#automatic-handling-of-data--254-bytes-command-chaining--response-looping)
   - [The ViewModel: `PcscViewModel.swift`](#the-viewmodel-pcscviewmodelswift)
   - [Objective-C Bridge: `EscapeCommand` & `TransmitCommand`](#objective-c-bridge-escapecommand--transmitcommand)
   - [User Interface: SwiftUI Components](#user-interface-swiftui-components)
5. [Automated APDU Script Execution](#5-automated-apdu-script-execution)
   - [Script Format and Syntax](#script-format-and-syntax)
   - [Wildcard Response Matching (`*` and `XX`)](#wildcard-response-matching--and-xx)
   - [File Management: Document Picker & Sandbox Security](#file-management-document-picker--sandbox-security)
6. [Cross-Platform CI/CD with GitHub Actions](#6-cross-platform-cicd-with-github-actions)
   - [Why CI/CD for Multiplatform Apple Projects?](#why-cicd-for-multiplatform-apple-projects)
   - [Code Signing in Headless CI Environments](#code-signing-in-headless-ci-environments)
   - [Complete GitHub Actions Workflow (`.github/workflows/build.yml`)](#complete-github-actions-workflow-githubworkflowsbuildyml)
7. [Junior Developer Troubleshooting & FAQ](#7-junior-developer-troubleshooting--faq)
   - [Common Gotchas & Error Codes](#common-gotchas--error-codes)
   - [Smart Card Status Word (SW1 SW2) Cheat Sheet](#smart-card-status-word-sw1-sw2-cheat-sheet)

---

## 1. Introduction & Project Overview

Welcome to **ApduTool**! If you are new to smart cards, USB hardware, or iOS low-level system frameworks, you might find terms like *APDU*, *TPDU*, *CCID*, and *ATR* a bit intimidating. Do not worry—this guide was written specifically to help you understand every single line of code and the hardware standards behind it.

### What is `ApduTool`?
`ApduTool` is an open-source, multiplatform application written in **SwiftUI** that runs on both **iOS** (iPhones and iPads) and **macOS**. Its core mission is:
1. Detect external **ACS (Advanced Card Systems)** smart card readers plugged in via USB.
2. Monitor when a physical smart card (such as a banking EMV chip card, eID card, or NFC tag) is inserted or removed.
3. Establish a secure communication session with the card.
4. Send commands to the card formatted as **APDUs** and receive replies.
5. Send special control commands directly to the reader hardware (**Escape Commands**).
6. Run automated test scripts line-by-line and export communication logs for analysis.

---

## 2. Smart Card & USB Fundamentals: Demystifying the Concepts

Before looking at the Swift code, let's establish a clear mental model of the hardware and protocols.

### What is a Smart Card?
A smart card is essentially a tiny, secure computer embedded inside a piece of plastic. It contains a CPU, cryptographic co-processors, RAM, and secure non-volatile memory (EEPROM/Flash).
- Unlike a smartphone or laptop, a contact smart card **has no battery and no screen**.
- When you insert it into a reader, the reader's gold pins make contact with the card's pads to supply **Power (VCC)**, **Ground (GND)**, a **Clock signal (CLK)**, a **Reset line (RST)**, and an **Input/Output data line (I/O)**.
- Contactless smart cards (NFC) work identically in terms of logic, but power is delivered wirelessly via electromagnetic induction (RFID antenna).

### What is an APDU? (Application Protocol Data Unit)
Think of an **APDU** as the application-level "network packet" or HTTP request/response used between your app and the smart card chip (governed by the **ISO/IEC 7816-4** standard).

#### 1. Command APDU (Sent from App to Card)
Every command APDU consists of a mandatory **4-byte Header**, followed by an optional **Body**:

| Field | Size | Name | Purpose / Meaning |
| :--- | :--- | :--- | :--- |
| **CLA** | 1 byte | Class | Identifies the instruction category (e.g., `0x00` for standard ISO, `0x80` for proprietary). |
| **INS** | 1 byte | Instruction | The command opcode (e.g., `0xA4` for SELECT FILE, `0xB0` for READ BINARY, `0x20` for VERIFY PIN). |
| **P1** | 1 byte | Parameter 1 | First argument modifying the instruction. |
| **P2** | 1 byte | Parameter 2 | Second argument modifying the instruction. |
| **Lc** | 0 to 3 bytes | Length of Command Data | Tells the card how many bytes of data are in the payload that follows. |
| **Data** | `Lc` bytes | Command Payload | The actual payload (e.g., AID of an applet, public key, PIN digits). |
| **Le** | 0 to 3 bytes | Expected Length | Tells the card how many bytes of response data the host expects back. |

ISO 7816-4 defines **4 Cases** of command APDUs:
- **Case 1:** Header only (4 bytes). No data sent, no data expected (e.g., card internal reset).
- **Case 2:** Header + `Le`. No data sent, but expecting `Le` bytes back from the card.
- **Case 3:** Header + `Lc` + `Data`. Data sent to the card, expecting only status word back.
- **Case 4:** Header + `Lc` + `Data` + `Le`. Data sent to the card, expecting data back + status word.

#### 2. Response APDU (Sent from Card to App)
The smart card processes your command and replies with:
- **Response Data** (0 to $N$ bytes).
- **Status Word (SW1 SW2)** (2 bytes at the very end).
  - The most famous status word is `0x90 0x00` (`9000`), which means **"Success"** (the smart card equivalent of HTTP `200 OK`).

### APDU vs. TPDU: What is the Difference?
This is one of the most critical details in `ApduTool`:
- **APDU (Application Protocol Data Unit):** High-level message (ISO 7816-4).
- **TPDU (Transmission Protocol Data Unit):** Low-level transmission frame (ISO 7816-3), using either:
  - **T=0:** Asynchronous half-duplex character transmission protocol. In T=0, you cannot send data and receive data in a single exchange; if a card has data to return, it replies with `61 XX` (meaning "I have XX bytes waiting for you"), and the host must follow up with a `GET RESPONSE` command (`00 C0 00 00 XX`).
  - **T=1:** Asynchronous half-duplex block transmission protocol (includes error detection like CRC/LRC).
- **Why this matters for ACS Readers:**
  - Modern USB readers (like ACS ACR122U / ACR1252U) often perform APDU-to-TPDU translation automatically inside the reader hardware/firmware.
  - However, popular contact card readers (like the **ACR38, ACR39, ACR40** series) are **TPDU-level readers**. They require the host OS driver to manage the lower-level transmission frames.
  - In `Pcsc.swift`, the code detects if the connected reader is a TPDU reader (`isTPDUReader()`) and uses special handling to ensure transmission succeeds!

### What is an ATR? (Answer To Reset)
When a smart card is powered up in a reader, it immediately answers with an **ATR (Answer To Reset)** string of bytes (governed by ISO 7816-3).
- Think of the ATR as the card's "digital handshake" or hardware identification tag.
- It tells the reader:
  - What voltage and clock frequency the chip supports.
  - Which communication protocols it supports (`T=0`, `T=1`, or both).
  - "Historical bytes" that often identify the card manufacturer, operating system, or chip type.

### What is USB CCID?
**CCID** stands for **Chip Card Interface Device**. It is an official USB-IF class specification (USB Device Class `0x0B`).
- When a hardware manufacturer builds a smart card reader adhering to the CCID specification, **no proprietary third-party kernel driver is needed**.
- Operating systems (including macOS, Windows, Linux, and iOS) have built-in CCID class drivers that can recognize and drive the hardware as soon as it is plugged in.

### What is an Escape Command?
Normally, APDUs are sent **through** the reader to the **smart card**.
However, what if you want to:
- Turn on a green LED on the reader?
- Sound the reader's internal buzzer?
- Read the reader's firmware version?

The smart card knows nothing about the reader's LED or buzzer. To command the **reader device itself**, we use an **Escape Command** (PC/SC `SCardControl`). In ACS readers, these commands typically start with byte `0xE0` (for example, `E0 00 00 18 00` requests the firmware version string).

---

## 3. Apple Platform Architecture: iOS vs. macOS

A major strength of this project is how it navigates Apple's operating system security and driver layers.

```
+---------------------------------------------------------------+
|                       ApduTool (SwiftUI)                      |
+-------------------------------+-------------------------------+
|             iOS               |             macOS             |
+-------------------------------+-------------------------------+
|        CryptoTokenKit         |     PCSC / winscard API       |
|   (TKSmartCardSlotManager)    |  (SCardEstablishContext, etc) |
+-------------------------------+-------------------------------+
|   iOS CCID Driver Stack       |      macOS pcscd daemon       |
+-------------------------------+-------------------------------+
| USB-C / Lightning + CCK Port  |         USB-A / USB-C         |
+-------------------------------+-------------------------------+
|              ACS Smart Card Reader (ACR39 / ACR122U)          |
+---------------------------------------------------------------+
```

### The iOS Reality: CryptoTokenKit & Sandboxing
On iOS, third-party apps **cannot** open raw USB devices directly (there is no `libusb`, nor direct access to kernel `IOKit`).
Instead, Apple provides the **`CryptoTokenKit`** framework:
- `TKSmartCardSlotManager.default`: Manages all smart card slots recognized by the system.
- `TKSmartCardSlot`: Represents a physical card slot in a reader.
- `TKSmartCard`: Represents an active communication channel with an inserted smart card.

#### iOS Limitation: No `SCardControl` (Escape Commands)
Because `CryptoTokenKit` is designed to interact with *cards* (tokens) rather than configuring *reader hardware*, Apple does not expose a public API on iOS to send raw Escape/Control codes to the USB reader.
Notice in `EscapeCommand.m`:
```objc
#if TARGET_OS_OSX
    // On macOS: Calls SCardControl(hCard, SCARD_CTRL_CODE(3500), ...)
    res = SCardControl(hCard, SCARD_CTRL_CODE(3500), sendData, sendLength, ...);
#else
    // On iOS: Returns Unsupported Feature error!
    return SCARD_E_UNSUPPORTED_FEATURE; // 0x80100022
#endif
```
This is an important design choice to keep in mind: **Escape commands work on macOS, but return `0x80100022` on iOS**.

### The macOS Difference: Native PC/SC (`winscard`)
macOS ships with the UNIX/PC/SC smart card daemon (`pcscd`) and the legacy C header `<PCSC/PCSC.h>`.
On macOS:
- Full support for `SCardEstablishContext`, `SCardConnect`, `SCardTransmit`, and `SCardControl`.
- `ApduTool` utilizes `EscapeCommand.m` and `TransmitCommand.m` via the Objective-C bridging header to access these low-level C functions when compiled for macOS.

### Hardware Requirements for iOS (Lightning & USB-C)
To connect an ACS USB reader to an iPhone or iPad:
1. **USB-C Devices (iPhone 15/16, modern iPads):**
   - You can connect USB-C ACS readers directly, or use a standard USB-A to USB-C OTG adapter.
2. **Lightning Devices (iPhone 14 and earlier):**
   - You **must** use the official **Apple Lightning to USB 3 Camera Adapter**.
   - **Crucial Junior Dev Gotcha:** A standard passive Lightning-to-USB adapter often gives an error on iOS: *"This accessory requires too much power"*. Smart card readers with smart card chips and contact pins draw more than the ~100mA current limit of the iPhone's Lightning port. The Apple USB 3 Camera Adapter includes a Lightning charging port so you can supply external 5V power while reading cards!

### The Critical Entitlement: `com.apple.security.smartcard`
In `ApduTool/ApduTool.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.smartcard</key>
	<true/>
</dict>
</plist>
```
> **Senior Developer Insight:** If this entitlement is missing or not signed by your provisioning profile, `TKSmartCardSlotManager.default` will either return `nil` or report zero slots on iOS devices. It is the gatekeeper key granting your app permission to communicate with external CCID readers.

---

## 4. Software Architecture & Component Walkthrough

The project is structured according to the classic **MVVM (Model-View-ViewModel)** pattern.

### Architecture Diagram (MVVM)

```
+-------------------------------------------------------------------------------+
|                                  VIEW LAYER                                   |
|   ContentView  |  ReadersView  |  TransferApduView  |  StateView  |  LogView  |
+-------------------------------------------------------------------------------+
                                      | @EnvironmentObject (Data Binding)
                                      v
+-------------------------------------------------------------------------------+
|                              VIEWMODEL LAYER                                  |
|                            PcscViewModel.swift                                |
|   - Holds @Published state (slotNames, connected, sendData, recvData, log)    |
|   - Coordinates background threading & MainActor UI updates                   |
|   - Runs script execution & wildcard response evaluation                      |
+-------------------------------------------------------------------------------+
                 |                                              |
                 v                                              v
+------------------------------------+        +---------------------------------+
|          COMPONENT ENGINE          |        |           DATA MODELS           |
|  Pcsc.swift                        |        |  Apdu.swift                     |
|  - TKSmartCardSlotManager KVO      |        |  - sendData: [UInt8]            |
|  - slot observation & session      |        |  - recvData: [UInt8]            |
|  - divideAPDU() Case 1-4 parser    |        |  CardInfo / CardState (Enums)   |
|                                    |        +---------------------------------+
|  Script.swift                      |
|  - .txt/.scr parser (strips ';')   |
|                                    |
|  Utils.swift                       |
|  - Hex string <-> [UInt8] helpers  |
+------------------------------------+
                 |
                 v (Objective-C Bridging)
+-------------------------------------------------------------------------------+
|                         NATIVE PC/SC C-BRIDGES (macOS)                        |
|       EscapeCommand.m (SCardControl)  |  TransmitCommand.m (SCardTransmit)    |
+-------------------------------------------------------------------------------+
```

---

### The Core Engine: `Pcsc.swift`
`Pcsc.swift` is the heartbeat of hardware communication. Let's look at its key responsibilities:

#### 1. Discovering Readers with Key-Value Observing (KVO)
```swift
@objc private var mngr = TKSmartCardSlotManager.default

override init() {
    super.init()
    // Observe the slotNames property of the manager
    managerObservation = mngr?.observe(\.slotNames, options: .initial, changeHandler: updateCardSlots)
}

func getSlotNames() -> [String] {
    // Only show readers whose names begin with "ACS"
    return mngr?.slotNames.filter({ name in
        return name.starts(with: "ACS")
    }) ?? []
}
```
- When you plug in an ACS reader over USB, iOS registers the device with `TKSmartCardSlotManager`.
- KVO fires immediately, notifying `PcscViewModel` to refresh the picker UI.

#### 2. Monitoring Card Insertion/Removal
```swift
private func monitorCard() -> NSKeyValueObservation? {
    return self.currentSlot?.observe(\.state, options: .initial) { _, _ in
        if let state = self.currentSlot?.state {
            switch state {
            case .missing:
                self.stopSlotMonitor()
            case .empty:
                self.activeCard?.endSession()
                self.activeCard = nil
            case .validCard:
                self.tpduReader = self.isTPDUReader()
                self.activeCard = self.currentSlot?.makeSmartCard()
                self.activeCard?.beginSession(reply: { res, error in
                    if error != nil { self.activeCard = nil }
                    self.getCardInfo?(state, error)
                })
                return
            default:
                break
            }
            self.getCardInfo?(state, nil)
        }
    }
}
```
- When a card is inserted, the slot state transitions to `.validCard`.
- The code creates a card instance (`makeSmartCard()`) and begins an exclusive communication session (`beginSession`).
- When the card is removed (`.empty`), the session is cleanly closed (`endSession()`).

---

### Deep Dive: The `divideAPDU()` Parsing Algorithm & `ApduCommand`
Why does `Pcsc.swift` provide `divideAPDU()` and `parseAPDU()`?

```swift
public func divideAPDU(_ apdu: [UInt8]) -> (cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8, data: Data?, le: Int?)
public func parseAPDU(_ apdu: [UInt8]) -> ApduCommand
```

#### The Problem:
On iOS, for TPDU readers (like ACR38/39/40), calling `activeCard.transmit(rawBytes)` directly can fail because the underlying reader hardware expects TPDU frames (T=0/T=1), not a monolithic APDU block.

#### The Solution:
`CryptoTokenKit` offers a structured method:
```swift
activeCard?.send(ins: ins, p1: p1, p2: p2, data: sendData, le: le, reply: { replyData, sw, error in ... })
```

To use this method, the code parses the raw byte array into its constituent ISO 7816-4 parts via `ApduCommand`:

```
Raw APDU Byte Array:
+-----+-----+----+----+-------------------+---------------------+
| CLA | INS | P1 | P2 | Lc (Payload Size) | Data (Payload) | Le |
+-----+-----+----+----+-------------------+---------------------+
   0     1    2    3    4                   5 ... 5+Lc       end
```

The algorithm checks:
1. **Case 1 (Length == 4):** CLA, INS, P1, P2 only.
2. **Case 2S (Length == 5):** Short APDU with expected return length (`Le = apdu[4] == 0 ? 256 : apdu[4]`). No command data.
3. **Payload / Extended APDU (Length > 5):**
   - If `apdu[4] != 0`: Standard Short APDU (`Lc = apdu[4]`). Data starts at index 5.
   - If `apdu[4] == 0` and length >= 7: Extended APDU! The length is encoded in the next two bytes (`(apdu[5] << 8) + apdu[6]`). Data starts at index 7.
4. **Determines `Le` (Expected return length):**
   - If remaining bytes exist after the payload (`dataOffset + lc`), those remaining bytes represent `Le`!

---

### Automatic Handling of Data > 254 Bytes (Command Chaining & Response Looping)

A common challenge in smart card engineering is transmitting or retrieving payloads exceeding **254 / 255 bytes**.

#### 1. Why 254 Bytes?
- **ISO 7816-3 T=0:** The TPDU parameter $P3$ is strictly 1 byte ($0 - 255$). There is no native extended APDU in T=0.
- **ISO 7816-3 T=1:** The Information Field length ($IFSC / IFSD$) negotiated per $I$-block is typically at most **254 bytes**.
- **ISO 7816-4 Short APDU:** Maximum $Lc = 255$ bytes, maximum $Le = 256$ bytes ($0x00$).

#### 2. Writing Data > 254 Bytes (ISO 7816-4 Command Chaining & Offset Tracking)
When `autoIsoHandling` is enabled and the payload exceeds 254 bytes, `Pcsc.swift` utilizes `Pcsc.splitForCommandChaining(...)`:
1. Slices the data into safe blocks of $\le 254$ bytes (or up to 255 bytes).
2. **Intermediate blocks ($0 \dots N-2$):** Sets **Bit 5 of the CLA byte** (`CLA |= 0x10`), signaling *"not the last command of a chain"*.
3. **Final block ($N-1$):** Clears Bit 5 of CLA (`CLA &= ~0x10`), signaling *"last command of a chain"*, and attaches the original $Le$.
4. **Transparent File Offset Incrementing (`P1-P2`):**
   - For binary write/update commands (`UPDATE BINARY` `0xD6`/`0xD7` or `WRITE BINARY` `0xD0`/`0xD1`), `P1-P2` represents the target byte offset in the transparent Elementary File (EF).
   - The engine automatically calculates `currentOffset = baseOffset + offset` and updates `chunkP1` and `chunkP2` for each block.
   - This ensures consecutive chunks are written contiguously across the file rather than repeatedly overwriting offset `00 00`.
   - For non-binary commands (e.g. `PUT DATA`, crypto operations), `P1-P2` qualifiers are strictly preserved.
5. Logs each intermediate block step: `[Chain 1/N] ...` in the datalog.
6. Verifies each intermediate block receives status `90 00` before transmitting the subsequent block.

#### 3. Reading Data > 254 / 256 Bytes
`ApduTool` supports two complementary ISO 7816 reading mechanisms:

##### A. Segmented `READ BINARY` (`INS == 0xB0` or `0xB1`)
- When a `READ BINARY` command specifies an expected return length $Le > 256$ bytes (e.g. `00 B0 00 00 00 10 00` requesting 4096 bytes):
- In standard short APDU environments (and strictly on T=0), the card cannot deliver $> 256$ bytes in a single APDU.
- `Pcsc.swift` automatically slices the request via `Pcsc.splitForSegmentedReadBinary(...)` into standard chunks of up to 256 bytes ($Le = 0x00$).
- Increments the `P1-P2` byte offset contiguously for each subsequent block.
- Logs each retrieval block in the datalog: `[Read 1/N] ...`.
- Transparently accumulates the returned data buffers, checks for end-of-file conditions (`62 82` or short length), and appends `90 00` upon completion.

##### B. Looped `GET RESPONSE` on T=0 (`61 XX`)
- When any command generates response data under T=0, the card returns **`61 XX`** ($XX$ indicates available bytes; $0x00$ means $\ge 256$ bytes).
- `Pcsc.swift` automatically intercepts `61 XX` and issues `GET RESPONSE (00 C0 00 00 XX)`.
- If subsequent bytes remain (`61 YY`), the engine loops `GET RESPONSE`, accumulating all chunks until the final status word (`90 00`).

#### 4. Automatic Wrong Le (`6C XX`) Re-issue
If a command returns status word `6C XX`, the engine automatically re-transmits the command setting $Le = XX$ ($0x00 = 256$).

#### 5. Mode Toggle: Auto ISO vs. Raw Mode
- **Auto ISO (Default):** Automatically manages offset-aware command chaining, segmented `READ BINARY`, `GET RESPONSE` accumulation, and `6C XX` re-issue.
- **Raw Mode:** Passes exact APDU bytes directly to the card without manipulation (crucial for raw procedure byte testing or scripts expecting raw `61 XX`).

---

### The ViewModel: `PcscViewModel.swift`
`PcscViewModel` serves as the central state hub.
- Conforms to `ObservableObject`, publishing variables like `@Published var sendData`, `@Published var recvData`, and `@Published var connected`.
- Dispatches all UI updates to `DispatchQueue.main.async` so background smart card callbacks never trigger thread-safety warnings in SwiftUI.
- Handles script automation and timestamped logging.

### Objective-C Bridge: `EscapeCommand` & `TransmitCommand`
Why are there `.m` (Objective-C) files in a modern Swift project?
- `ApduTool-Bridging-Header.h` exposes `EscapeCommand.h` and `TransmitCommand.h` to Swift.
- These classes wrap direct C API calls (`SCardEstablishContext`, `SCardControl`, `SCardTransmit`) from `<PCSC/PCSC.h>`.
- In Xcode, Swift cannot directly `#import <PCSC/PCSC.h>` conditionally if the framework header doesn't exist on iOS SDKs. Objective-C handles this elegantly using `#if TARGET_OS_OSX` conditional compilation.

### User Interface: SwiftUI Components
The UI is cleanly divided into modular, previewable SwiftUI views:
- **`ContentView.swift`:** Uses `GeometryReader` to calculate responsive screen widths and adapts seamlessly between iPhone, iPad, and Mac.
- **`ReadersView.swift`:** Dropdown picker populated by `pcsc.slotNames` with dynamic Connect/Disconnect button.
- **`TransferApduView.swift`:**
  - Auto-formats input: `newValue.uppercased().filter("0123456789ABCDEF".contains)`.
  - Smart command routing: If the input starts with `"E0"`, it routes to `transferEscapeCommand()`; otherwise, it routes to `transferApdu()`.
  - Loop configuration: Adds `Loop#:` with automated validation (defaults to `1`, automatically resets `0` or negative values to `1`) to control batch script repetition.
  - Auto ISO-7816 Toggle: Allows switching between **Auto Mode** (automatic command chaining & GET RESPONSE looping) and **Raw Mode** (direct byte transmission).
- **`StateView.swift`:** Displays card status (Present, Removed, Probing), ATR hex string, and active protocol (T0, T1).
- **`LogView.swift`:** Scrollable terminal log with auto-scroll using `ScrollViewReader` and `proxy.scrollTo(bottomID)`.
- **`ToastView.swift`:** Animated floating feedback pill for user alerts.

---

## 5. Automated APDU Script Execution

Manually typing 20-character hex strings into a text box gets tedious very quickly. `ApduTool` supports running batch scripts (`.txt` or `.scr`).

### Script Format and Syntax
Script files follow standard smart card test script conventions:
```text
; ============================================
; Test Script: Select Master File and Read Data
; Lines beginning with ';' are comments
; ============================================

; Step 1: Select 3F 00 (Master File)
00A40000023F00
9000

; Step 2: Read Binary (First 16 bytes)
00B0000010
9000

; Step 3: Get Processing Options
80A8000002830000
77*
```

Each command has two lines:
1. **Send line:** The hex APDU to transmit.
2. **Expect line:** The expected response hex string.

### Smart Card Reset Directive (`[RST]`)
Scripts can also instruct the reader to power-reset the card on the fly:
- When a line contains `[RST]`, `PcscViewModel` executes `resetCard()`.
- **Card Reset Flow (`resetCard()`):**
  1. Disconnects and ends the active card session (`card.endSession()`).
  2. Re-connects to the card slot (`slot.makeSmartCard()`) and sets `newCard.isSensitive = true` to trigger an ISO 7816-3 **Warm Reset** (toggling RST line while maintaining VCC power) upon starting the session (`beginSession`).
  3. Resets `newCard.isSensitive = false` for subsequent normal APDU transmissions and updates active card tracking.
  4. Obtains the returned Answer-To-Reset (ATR) bytes (`slot.atr`).
  5. Logs `"ATR:"` followed by the ATR hex buffer into `LogView` and `datalog`.
  6. If an error occurs, logs `"Error: " + error.localizedDescription` and flags the loop step as failed.
- **Optional Expected ATR:** If the line directly following `[RST]` begins with `3B`, `3F`, or `*`, it is validated against the card's ATR; otherwise, the script immediately advances to the next APDU command.

### Wildcard Response Matching (`*` and `XX`)
In real smart card testing, card responses often contain dynamic data (such as card serial numbers, session keys, or random cryptographic nonces). You cannot always do an exact string match.

`PcscViewModel.swift` implements an intelligent comparison method: `specCompare(_ expStr: String, _ cmpStr: String)`:
```swift
private func specCompare(_ expStr: String, _ cmpStr: String) -> Bool {
    // 1. '*' means match anything
    if expStr.subString(0, 1) == "*" {
        return true
    }
    if expStr.count > cmpStr.count {
        return false
    }
    // 2. Step byte by byte (2 hex characters per byte)
    for i in stride(from: 0, to: expStr.count, by: 2) {
        if expStr.subString(i, 1) == "*" {
            return true
        } else if expStr.subString(i, 2) != "XX" { // "XX" is a wildcard byte
            if expStr.subString(i, 2) != cmpStr.subString(i, 2) {
                return false
            }
        }
    }
    return true
}
```
- `*`: Matches any subsequent data (e.g. `77*` checks that response starts with tag `77`).
- `XX`: Masks out a specific variable byte (e.g. `9F3602XXXX9000` ignores the 2-byte Application Transaction Counter).

### Status Word Matching & Negative Testing (e.g. `90 XX`, `6C 04`, `6A 82`)
In smart card testing, scripts frequently test negative cases, proprietary status words, or protocol handshakes expecting non-`9000` status words (such as `90 XX` matching `90 20`, `6C 04` indicating wrong Le, or `6A 82` indicating file not found):
- **Apple `CryptoTokenKit` Error Semantics:** Apple's `TKSmartCard` flags any status word other than `0x9000` as an `NSError` (`"SmartCard returned error XXXX"`), even though the card completed execution and returned the exact status word bytes.
- **Auto ISO-7816 Status Word Preservation:** In `Pcsc.swift`, `executeIsoApdu` and `handleIsoResponse` distinguish between fatal transport/communication errors (`sw == 0 && error != nil`) and card status words (`sw != 0`). When a card returns a non-`9000` status word (e.g., `0x9020`), the engine appends the 2-byte status word to the response data buffer and forwards it to `getScriptResponse`.
- **Wildcard & Spec Verification:** `ApduTool` evaluates test success by matching the actual output against the script's expected response: as long as the received data matches the expected output (`specCompare`), the step passes. For example, if the script expects `90 XX` and the card returns `90 20`, the step passes cleanly without error logs in both Auto ISO and Raw modes. Error messages are only flagged if the card output does not match expectation or if a fatal transport disconnection occurs.

### File Management: Document Picker & Sandbox Security
Because iOS apps are strictly sandboxed:
- The app uses `UIDocumentPickerViewController` (`presentDocumentPicker()`) to let the user pick a script file from iCloud Drive, local Files, or AirDrop.
- Notice the security-scoped resource handling:
  ```swift
  guard let accessGranted = scriptURL?.startAccessingSecurityScopedResource() else { ... }
  // Read file ...
  scriptURL?.stopAccessingSecurityScopedResource()
  ```
- In `Info.plist`, `UIFileSharingEnabled = true` enables sharing logs directly through the iOS Files app or macOS Finder when tethered via cable.

### Batch Looping & Automated Stress Testing
For hardware reliability testing, `PcscViewModel` supports repeating script execution:
- The UI exposes a validated `Loop#:` field (defaulting to 1; values $\le 0$ automatically reset to 1).
- When **Run Script** is triggered, `runScript()` parses the batch file once, resets tracking counters, and begins execution.
- **Loop Lifecycle Logging:**
  - Start of each loop: logs `Loop# m/n starts`.
  - End of each loop: checks whether all APDU expected responses matched without communication errors and logs `Loop# m pass` or `Loop# n fail`.
  - Conclusion of test: logs aggregate results `Pass: m and Fail: n`.
- **Rolling UI Display Buffer (`maxDisplayCharacters = 10000`):**
  - Large data APDUs (e.g., 4096-byte `UPDATE BINARY` or `READ BINARY` payloads) generate lines with over 8,192 characters. Limiting by line count alone can still allow hundreds of thousands of characters in the view, slowing down SwiftUI's text layout and word-wrapping engine.
  - The `LogView` display (`message`) is strictly capped at the latest **10,000 characters** via a FIFO rolling window aligned cleanly to line boundaries.
  - As new log entries arrive, older characters automatically roll off the top of the display view, keeping rendering speeds consistently high regardless of script size or loop iteration count.
- **Dedicated Unbounded `datalog` Buffer:**
  - Unlike the rolling UI view, `datalog` stores the complete, unabridged history of all APDU commands, responses, and loop results from loop #1 to the final loop.
  - When tapping **Save Log**, the full unbounded `datalog` content is written to `apdulog.txt`.
- **UI Scroll Performance Optimizations:**
  - Removed continuous animation interpolation (`withAnimation`) from the 100ms scroll timer in `LogView`, eliminating frame backlog and stutter.
  - Reused a static `DateFormatter` and optimized string append operations in `PcscViewModel` to eliminate $O(N)$ string copying overhead per APDU.

---

## 6. Cross-Platform CI/CD with GitHub Actions

As an engineer on this project, having automated builds across platforms guarantees that a change made for macOS does not inadvertently break the iOS build, and vice-versa.

### Why CI/CD for Multiplatform Apple Projects?
The `ApduTool.xcodeproj` defines:
```text
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"
```
Because the project targets both operating systems with conditional `#if os(macOS)` and `#if os(iOS)` blocks, compiling on only one platform risks letting compilation errors slip through.

### Code Signing in Headless CI Environments
In a continuous integration runner (like GitHub Actions), there are no physical developer smart cards or private development certificates installed by default.
To build successfully without errors, we pass:
```bash
CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
This tells `xcodebuild` to compile and link everything for syntax, frameworks, and architecture without requiring an active Apple Developer Certificate.

### Complete GitHub Actions Workflow (`.github/workflows/build.yml`)
Below is a production-grade workflow configuration file that compiles `ApduTool` for **iOS (Simulator & Device)** and **macOS**, packages the **`.ipa`** and macOS `.app`, and uploads them as downloadable artifacts:

```yaml
name: Build & Test ApduTool Multiplatform

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-verify:
    name: Build (${{ matrix.platform.name }})
    runs-on: macos-14  # Apple Silicon M1/M2 Runner with latest Xcode
    strategy:
      fail-fast: false
      matrix:
        platform:
          - name: "iOS Simulator"
            destination: "generic/platform=iOS Simulator"
            sdk: "iphonesimulator"
            run_tests: true
          - name: "iOS Device (iphoneos)"
            destination: "generic/platform=iOS"
            sdk: "iphoneos"
            run_tests: false
          - name: "macOS"
            destination: "generic/platform=macOS"
            sdk: "macosx"
            run_tests: true

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Select Xcode Version
        run: |
          sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer
          xcodebuild -version

      - name: Build Target (${{ matrix.platform.name }})
        run: |
          set -o pipefail
          xcodebuild clean build \
            -project ApduTool.xcodeproj \
            -scheme ApduTool \
            -sdk ${{ matrix.platform.sdk }} \
            -destination "${{ matrix.platform.destination }}" \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO

      - name: Run Unit Tests (${{ matrix.platform.name }})
        if: ${{ matrix.platform.run_tests }}
        run: |
          set -o pipefail
          xcodebuild test \
            -project ApduTool.xcodeproj \
            -scheme ApduTool \
            -destination "${{ matrix.platform.destination }}" \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO

      - name: Package iOS IPA
        if: matrix.platform.sdk == 'iphoneos'
        run: |
          APP_PATH=$(find build/Build/Products -name "ApduTool.app" -type d | head -n 1)
          echo "Found iOS app at: $APP_PATH"
          mkdir -p Payload
          cp -r "$APP_PATH" Payload/
          zip -r ApduTool.ipa Payload

      - name: Upload iOS IPA Artifact
        if: matrix.platform.sdk == 'iphoneos'
        uses: actions/upload-artifact@v4
        with:
          name: ApduTool-iOS-Device-ipa
          path: ApduTool.ipa
          retention-days: 7

      - name: Package macOS App
        if: matrix.platform.sdk == 'macosx'
        run: |
          APP_PATH=$(find build/Build/Products -name "ApduTool.app" -type d | head -n 1)
          echo "Found macOS app at: $APP_PATH"
          zip -r ApduTool-macOS.zip "$APP_PATH"

      - name: Upload macOS App Artifact
        if: matrix.platform.sdk == 'macosx'
        uses: actions/upload-artifact@v4
        with:
          name: ApduTool-macOS-app
          path: ApduTool-macOS.zip
          retention-days: 7
```

### Explanation of Workflow Steps:
1. **`runs-on: macos-14`**: Uses GitHub's macOS ARM64 runners (M1/M2) which build Swift/SwiftUI projects 3x faster than older Intel runners.
2. **`-derivedDataPath build`**: Ensures build products land in a deterministic local path (`./build`) instead of random global DerivedData folders.
3. **Packaging the `.ipa` (`matrix.platform.sdk == 'iphoneos'`):**
   - By definition, an iOS `.ipa` file is a ZIP archive containing a top-level directory called `Payload/` with the compiled `ApduTool.app` inside.
   - The workflow creates `Payload/`, copies the built `.app` bundle into it, and zips it into `ApduTool.ipa`.
4. **Publishing Artifacts (`actions/upload-artifact@v4`):**
   - Uploads `ApduTool.ipa` (for iOS) and `ApduTool-macOS.zip` (for macOS) directly to the GitHub Actions run summary page under the **Artifacts** section.
2. **Matrix Strategy**: Spawns 3 parallel jobs:
   - **iOS Simulator:** Verifies iOS SwiftUI compilation and executes XCTests.
   - **iOS Device (`iphoneos`):** Verifies ARM64 device linking and entitlements compatibility.
   - **macOS:** Verifies macOS PC/SC C-headers and desktop targets.
3. **`set -o pipefail`**: Ensures that if `xcodebuild` encounters an error, the CI step halts and reports failure properly.

---

## 7. Junior Developer Troubleshooting & FAQ

### Common Gotchas & Error Codes

#### Q1: "I plugged in my ACS reader into my iPhone, but `slotNames` is empty!"
- **Check 1: Name Filtering.** In `Pcsc.swift`, line 38 filters reader names:
  ```swift
  return name.starts(with: "ACS")
  ```
  If your reader reports its USB string as anything other than starting with `"ACS"`, it will be filtered out. You can change this to `return true` to see all connected readers.
- **Check 2: Power.** Are you using an iPhone with a Lightning port? If so, the reader is probably starved of electrical power. Plug a Lightning cable into the side of the Apple USB 3 Camera Adapter.
- **Check 3: Entitlements.** Ensure `com.apple.security.smartcard` is present in your provisioning profile and entitlement file.

#### Q2: "Can I test USB card readers inside the Xcode iOS Simulator?"
- **No.** The Xcode iOS Simulator runs in a virtual container and **does not forward USB CCID devices** from your Mac into the simulated iOS environment.
- To test smart card communication on iOS, you **must run the app on a physical iPhone or iPad**. (On macOS, however, you can test directly on your Mac machine!).

#### Q3: "What does error `0x80100022` mean when sending `E0...` commands on iPhone?"
- `0x80100022` is `SCARD_E_UNSUPPORTED_FEATURE`.
- As discussed in [Section 3](#the-ios-reality-cryptotokenkit--sandboxing), Apple's `CryptoTokenKit` on iOS does not support raw Escape Commands (`SCardControl`). These commands only work on macOS.

#### Q4: "Why does my test script report `> 9000 (Error: expected 61XX)` on iPhone when selecting a file/AID?"
- **Symptom:** You run an automated test script containing a `SELECT FILE` command expecting `61 XX`:
  ```text
  00 A4 04 00 0E 31 50 41 59 2E 53 59 53 2E 44 44 46 30 33
  61 17
  ```
  The app logs:
  ```text
  < 00A404000E315041592E5359532E4444463033
  > 9000 (Error: expected 6117)
  ```
- **Root Cause:**
  - On desktop PC/SC (e.g. `winscard` / `SCardTransmit`), when a smart card using the **T=0** protocol executes a command that has response data (such as File Control Information / FCI for `SELECT FILE`), the card cannot return data directly on a Case 3 command. It returns the status word **`61 XX`** (where `XX` is the number of available response bytes). Desktop PC/SC simply passes `61 XX` back to the calling application.
  - On iOS with TPDU readers (ACR38, ACR39, ACR40), `ApduTool` transmits via Apple's high-level `TKSmartCard.send(...)` API in `Pcsc.swift`.
  - Apple's `TKSmartCard.send` adheres to the full ISO 7816-4 APDU layer: when it detects `SW1 == 0x61`, **it automatically sends `GET RESPONSE (00 C0 00 00 XX)` under the hood** to fetch the remaining data from the card.
  - When the underlying `GET RESPONSE` finishes, the smart card completes the exchange with status word **`90 00`**.
  - As a result, `TKSmartCard.send` returns `9000` to `ApduTool` rather than intermediate `61 XX` procedure bytes.
- **Resolution:**
  - In scripts written for `ApduTool` on iOS, expect **`90 00`** instead of `61 XX` for commands where `CryptoTokenKit` automatically executes `GET RESPONSE`.
  - The card command succeeded completely—the target AID/file was selected and the card is ready for subsequent APDU commands.

---

### Smart Card Status Word (SW1 SW2) Cheat Sheet
When transmitting APDUs, the card always returns two hex status bytes at the end of the response:

| Status Word | Name | Meaning & What to Do |
| :--- | :--- | :--- |
| `90 00` | **Success** | Command completed normally. |
| `61 XX` | **Response Bytes Available** | Normal in `T=0`. The card has `XX` bytes waiting. Send `00 C0 00 00 XX` (GET RESPONSE). *Note: On iOS, `TKSmartCard.send()` issues `GET RESPONSE` automatically under the hood and returns `90 00`.* |
| `6C XX` | **Wrong Le length** | The card says: *"Re-issue the exact same command, but set Le = XX"*. |
| `67 00` | **Wrong Length** | `Lc` or `Le` is invalid for this instruction. |
| `69 82` | **Security Condition Not Satisfied** | Authentication required (e.g. PIN must be verified first). |
| `6A 82` | **File / Application Not Found** | The AID or File ID you specified in the SELECT command does not exist on the card. |
| `6D 00` | **Instruction (INS) Not Supported** | The card does not recognize this instruction code. |
| `6E 00` | **Class (CLA) Not Supported** | The card does not support the class byte you provided. |

---

## 8. Summary & Next Steps

You now possess a complete 360-degree understanding of:
- How iOS interacts with USB smart card readers via `CryptoTokenKit` and CCID.
- How APDUs, TPDUs, and ATRs operate under ISO 7816 standards.
- How `ApduTool` is architected using SwiftUI and MVVM.
- How to set up continuous integration for cross-platform Apple builds in GitHub Actions.

Happy coding! If you're ready to extend the app, try adding support for reading standard NDEF NFC records or decoding EMV payment card directory structures!
