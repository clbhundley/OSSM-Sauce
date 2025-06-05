# OSSM-Sauce
App and firmware for controlling OSSM devices using WebSockets


# OSSM WebSocket Communication Protocol

## Overview

The OSSM (Open Source Sex Machine) uses a binary WebSocket protocol for real-time communication between the control application (Godot) and the ESP32 firmware. All multi-byte values are transmitted in **little-endian** byte order.

## Architecture

```
┌─────────────────┐                  ┌─────────────────┐
│   Godot App     │                  │   ESP32 OSSM    │
│                 │                  │                 │
│ WebSocket       │◄────────────────►│ WebSocket       │
│ Server          │   Binary Data    │ Client          │
│ (GDExtension)   │                  │                 │
└─────────────────┘                  └─────────────────┘
```

## Command Structure

All commands follow this pattern:
1. First byte: Command Type (enum)
2. Remaining bytes: Command-specific data

## Command Reference

### Command Type Enum
```
0x00 - RESPONSE
0x01 - MOVE
0x02 - LOOP
0x03 - POSITION
0x04 - VIBRATE
0x05 - PLAY
0x06 - PAUSE
0x07 - RESET
0x08 - HOMING
0x09 - CONNECTION
0x0A - SET_SPEED_LIMIT
0x0B - SET_GLOBAL_ACCELERATION
0x0C - SET_RANGE_LIMIT
0x0D - SET_HOMING_SPEED
0x0E - SET_HOMING_TRIGGER
```

### MOVE Command (0x01)
Controls point-to-point motion with easing curves.

**Packet Size:** 10 bytes

```
┌────┬───────────┬────────┬────────┬────────┬────────┐
│ 0  │    1-4    │  5-6   │   7    │   8    │   9    │
├────┼───────────┼────────┼────────┼────────┼────────┤
│CMD │  TIME_MS  │  POS   │ TRANS  │  EASE  │  AUX   │
│0x01│   (u32)   │ (u16)  │  (u8)  │  (u8)  │  (u8)  │
└────┴───────────┴────────┴────────┴────────┴────────┘

CMD     - Command type (MOVE = 0x01)
TIME_MS - Timestamp in milliseconds (u32)
POS     - Target position 0-10000 (u16)
TRANS   - Transition type (u8)
EASE    - Easing type (u8)
AUX     - Auxiliary functions bitmask (u8)
```

**Transition Types:**
- 0: LINEAR
- 1: SINE
- 2: CIRC
- 3: EXPO
- 4: QUAD
- 5: CUBIC
- 6: QUART
- 7: QUINT

**Easing Types:**
- 0: EASE_IN
- 1: EASE_OUT
- 2: EASE_IN_OUT
- 3: EASE_OUT_IN

### LOOP Command (0x02)
Defines a continuous back-and-forth motion pattern.

**Packet Size:** 19 bytes

```
┌────┬────────────────────┬───────────────────────┐
│ 0  │   1-9              │   10-18               │
├────┼────────────────────┴───────────────────────┤
│CMD │   PUSH_STROKE      │   PULL_STROKE         │
│0x02│   (9 bytes)        │   (9 bytes)           │
└────┴────────────────────┴───────────────────────┘

Each stroke contains:
┌─────────────┬────────┬────────┬────────┬────────┐
│   0-3       │  4-5   │   6    │   7    │   8    │
├─────────────┼────────┼────────┼────────┼────────┤
│ DURATION_MS │  POS   │ TRANS  │  EASE  │  AUX   │
│   (u32)     │ (u16)  │  (u8)  │  (u8)  │  (u8)  │
└─────────────┴────────┴────────┴────────┴────────┘
```

### POSITION Command (0x03)
Direct position control for manual operation.

**Packet Size:** 5 bytes

```
┌────┬────────────┐
│ 0  │    1-4     │
├────┼────────────┤
│CMD │  POSITION  │
│0x03│   (u32)    │
└────┴────────────┘

POSITION - Target position 0-10000 (u32)
```

### VIBRATE Command (0x04)
Configures vibration pattern with adjustable waveform.

**Packet Size:** 13 bytes

```
┌────┬─────────────┬─────────────┬────────┬────────┬────────┐
│ 0  │    1-4      │    5-8      │  9-10  │   11   │   12   │
├────┼─────────────┼─────────────┼────────┼────────┼────────┤
│CMD │ DURATION_MS │ HALF_PERIOD │  POS   │ RANGE  │ SMOOTH │
│0x04│   (s32)     │   (u32)     │ (u16)  │  (u8)  │  (u8)  │
└────┴─────────────┴─────────────┴────────┴────────┴────────┘

DURATION_MS  - Duration (-1=infinite, 0=stop) (s32)
HALF_PERIOD  - Half period in ms (frequency) (u32)
POS          - Origin position 0-10000 (u16)
RANGE        - Stroke range 0-100% (u8)
SMOOTH       - Waveform smoothing 100-200 (u8)
              100 = Square wave
              200 = Triangle wave
              101-199 = Interpolated
```

### PLAY Command (0x05)
Starts playback in specified mode.

**Packet Size:** 2 or 6 bytes

```
Basic (2 bytes):
┌────┬────────┐
│ 0  │   1    │
├────┼────────┤
│CMD │  MODE  │
│0x05│  (u8)  │
└────┴────────┘

With timestamp - start from given ms (6 bytes):
┌────┬────────┬────────────┐
│ 0  │   1    │    2-5     │
├────┼────────┼────────────┤
│CMD │  MODE  │  TIME_MS   │
│0x05│  (u8)  │   (u32)    │
└────┴────────┴────────────┘

MODE values:
0 - IDLE
1 - HOMING
2 - MOVE
3 - POSITION
4 - LOOP
5 - VIBRATE
```

### PAUSE Command (0x06)
Pauses current motion.

**Packet Size:** 1 byte

```
┌────┐
│ 0  │
├────┤
│CMD │
│0x06│
└────┘
```

### RESET Command (0x07)
Clears motion queue and resets playback.

**Packet Size:** 1 byte

```
┌────┐
│ 0  │
├────┤
│CMD │
│0x07│
└────┘
```

### HOMING Command (0x08)
Initiates homing to specified position.

**Packet Size:** 5 bytes

```
┌────┬────────────┐
│ 0  │    1-4     │
├────┼────────────┤
│CMD │  POSITION  │
│0x08│   (u32)    │
└────┴────────────┘

POSITION - Target home position 0-10000 (u32)
```

### CONNECTION Command (0x09)
Handshake/connection verification.

**Packet Size:** 1 byte

```
┌────┐
│ 0  │
├────┤
│CMD │
│0x09│
└────┘
```

### SET_SPEED_LIMIT Command (0x0A)
Sets maximum motor speed.

**Packet Size:** 5 bytes

```
┌────┬────────────┐
│ 0  │    1-4     │
├────┼────────────┤
│CMD │  SPEED_HZ  │
│0x0A│   (u32)    │
└────┴────────────┘

SPEED_HZ - Maximum speed in Hz (u32)
```

### SET_GLOBAL_ACCELERATION Command (0x0B)
Sets motor acceleration.

**Packet Size:** 5 bytes

```
┌────┬────────────┐
│ 0  │    1-4     │
├────┼────────────┤
│CMD │   ACCEL    │
│0x0B│   (u32)    │
└────┴────────────┘

ACCEL - Acceleration in steps/sec² (u32)
```

### SET_RANGE_LIMIT Command (0x0C)
Sets motion range limits.

**Packet Size:** 4 bytes

```
┌────┬────────┬────────┐
│ 0  │   1    │  2-3   │
├────┼────────┼────────┤
│CMD │ RANGE  │ LIMIT  │
│0x0C│  (u8)  │ (u16)  │
└────┴────────┴────────┘

RANGE - 0=MIN_RANGE, 1=MAX_RANGE (u8)
LIMIT - Position limit 0-10000 (u16)
```

### SET_HOMING_SPEED Command (0x0D)
Sets homing movement speed.

**Packet Size:** 5 bytes

```
┌────┬────────────┐
│ 0  │    1-4     │
├────┼────────────┤
│CMD │  SPEED_HZ  │
│0x0D│   (u32)    │
└────┴────────────┘

SPEED_HZ - Homing speed in Hz (u32)
```

### SET_HOMING_TRIGGER Command (0x0E)
Sets power spike threshold for sensorless homing.

**Packet Size:** 5 bytes

```
┌────┬────────────┐
│ 0  │    1-4     │
├────┼────────────┤
│CMD │ THRESHOLD  │
│0x0E│   (u32)    │
└────┴────────────┘

THRESHOLD - Voltage threshold for edge detection (u32)
```

## Response Protocol

The ESP32 sends responses using the RESPONSE (0x00) command:

```
┌────┬────────┐
│ 0  │   1    │
├────┼────────┤
│0x00│  TYPE  │
└────┴────────┘

TYPE - The command type being acknowledged
```

## Example Implementations

### Godot (GDScript) - Sending MOVE Command
```gdscript
func send_move_command(timestamp_ms: int, position: float, trans: int, ease: int):
    var command: PackedByteArray
    command.resize(10)
    command.encode_u8(0, CommandType.MOVE)
    command.encode_u32(1, timestamp_ms)
    command.encode_u16(5, round(remap(position, 0.0, 1.0, 0, 10000)))
    command.encode_u8(7, trans)
    command.encode_u8(8, ease)
    command.encode_u8(9, 0)  # auxiliary
    websocket.send(command)
```

### ESP32 (C++) - Receiving Commands
```cpp
void parseMessage(esp_websocket_event_data_t *data) {
    byte* message = (byte*)data->data_ptr;
    CommandType commandType = static_cast<CommandType>(message[0]);
    
    switch (commandType) {
        case MOVE: {
            if (data->data_len != 10) break;
            // Message bytes 1-9 contain the stroke data
            xQueueSend(moveQueue, &(message[1]), portMAX_DELAY);
            break;
        }
        // ... other commands
    }
}
```

## Motion Path Files

### .bx Format
JSON format containing timestamped positions with motion parameters:
```json
{
  "0": [0.0, 1, 2, 0],      // Frame 0: [depth, trans, ease, aux]
  "60": [1.0, 1, 2, 0],     // Frame 60
  "120": [0.5, 2, 1, 0]     // Frame 120
}
```

### .funscript Format
JSON format with millisecond timestamps:
```json
{
  "actions": [
    {"at": 0, "pos": 0},
    {"at": 1000, "pos": 100},
    {"at": 2000, "pos": 50}
  ]
}
```

## Notes

- All positions are normalized to 0-10000 range
- The ESP32 uses sensorless homing to detect motion limits via power consumption monitoring
- The WebSocket connection supports both binary and text protocols, but all motion commands use binary
- Motion smoothing and acceleration limits are applied in the ESP32 firmware for safety
