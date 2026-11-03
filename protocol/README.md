# DroidLink Protocol

This directory contains the protocol definitions for communication between the macOS app and the Android companion app.

## Protocol Overview

DroidLink uses a multi-channel communication architecture:

### 1. Video Channel (High-throughput, one-way)
- **Direction:** Android → Mac
- **Transport:** Raw TCP socket
- **Port:** 27183 (default)
- **Codec:** H.264 / H.265 / AV1 (configurable)
- **Format:** Raw NAL units with length-prefixed framing

### 2. Audio Channel (Medium-throughput, one-way)
- **Direction:** Android → Mac
- **Transport:** Raw TCP socket  
- **Port:** 27184 (default)
- **Codec:** Opus
- **Format:** Length-prefixed Opus packets

### 3. Control Channel (Low-throughput, bidirectional)
- **Direction:** Bidirectional
- **Transport:** WebSocket
- **Port:** 27185 (default)
- **Format:** JSON messages (see message types below)

## Message Types

All control messages follow this envelope format:

```json
{
  "type": "message_type",
  "id": "unique-message-id",
  "timestamp": 1699000000000,
  "payload": { ... }
}
```

### Handshake Messages

#### `handshake_request` (Mac → Android)
```json
{
  "type": "handshake_request",
  "payload": {
    "protocol_version": 1,
    "app_version": "1.0.0",
    "device_name": "MacBook Air",
    "capabilities": ["mirror", "clipboard", "notifications", "files", "sms"]
  }
}
```

#### `handshake_response` (Android → Mac)
```json
{
  "type": "handshake_response",
  "payload": {
    "protocol_version": 1,
    "app_version": "1.0.0",
    "device_name": "Pixel 9",
    "device_model": "google/pixel9",
    "android_version": "15",
    "sdk_level": 35,
    "screen_width": 1080,
    "screen_height": 2400,
    "capabilities": ["mirror", "clipboard", "notifications", "files", "sms", "calls"]
  }
}
```

### Mirror Messages

#### `mirror_start` (Mac → Android)
```json
{
  "type": "mirror_start",
  "payload": {
    "max_width": 1920,
    "max_height": 1080,
    "max_fps": 60,
    "codec": "h265",
    "bitrate": 8000000,
    "audio_enabled": true
  }
}
```

#### `mirror_stop` (Mac → Android)
```json
{
  "type": "mirror_stop"
}
```

### Input Messages

#### `touch_event` (Mac → Android)
```json
{
  "type": "touch_event",
  "payload": {
    "action": "down|move|up",
    "x": 540.0,
    "y": 960.0,
    "pointer_id": 0,
    "pressure": 1.0
  }
}
```

#### `key_event` (Mac → Android)
```json
{
  "type": "key_event",
  "payload": {
    "action": "down|up",
    "keycode": 66,
    "meta_state": 0
  }
}
```

#### `text_input` (Mac → Android)
```json
{
  "type": "text_input",
  "payload": {
    "text": "Hello, World!"
  }
}
```

### Clipboard Messages

#### `clipboard_sync` (Bidirectional)
```json
{
  "type": "clipboard_sync",
  "payload": {
    "content_type": "text|image",
    "text": "copied text",
    "image_base64": null,
    "source": "android|mac"
  }
}
```

### Notification Messages

#### `notification_posted` (Android → Mac)
```json
{
  "type": "notification_posted",
  "payload": {
    "notification_id": "12345",
    "app_package": "com.whatsapp",
    "app_name": "WhatsApp",
    "title": "John Doe",
    "text": "Hey, how are you?",
    "timestamp": 1699000000000,
    "can_reply": true,
    "icon_base64": "..."
  }
}
```

#### `notification_reply` (Mac → Android)
```json
{
  "type": "notification_reply",
  "payload": {
    "notification_id": "12345",
    "reply_text": "I'm good, thanks!"
  }
}
```

#### `notification_dismiss` (Mac → Android)
```json
{
  "type": "notification_dismiss",
  "payload": {
    "notification_id": "12345"
  }
}
```

### File Transfer Messages

#### `file_transfer_offer` (Bidirectional)
```json
{
  "type": "file_transfer_offer",
  "payload": {
    "transfer_id": "uuid",
    "file_name": "photo.jpg",
    "file_size": 2048576,
    "mime_type": "image/jpeg",
    "checksum": "crc32-value"
  }
}
```

#### `file_transfer_accept` (Bidirectional)
```json
{
  "type": "file_transfer_accept",
  "payload": {
    "transfer_id": "uuid",
    "port": 27186
  }
}
```

#### `file_transfer_progress` (Bidirectional)
```json
{
  "type": "file_transfer_progress",
  "payload": {
    "transfer_id": "uuid",
    "bytes_transferred": 1024000,
    "total_bytes": 2048576
  }
}
```

### Device Status Messages

#### `device_status` (Android → Mac)
```json
{
  "type": "device_status",
  "payload": {
    "battery_level": 85,
    "is_charging": true,
    "storage_total_mb": 128000,
    "storage_free_mb": 64000,
    "wifi_ssid": "HomeNetwork",
    "wifi_signal_strength": -45
  }
}
```

#### `find_phone` (Mac → Android)
```json
{
  "type": "find_phone",
  "payload": {
    "action": "ring|stop"
  }
}
```

### SMS Messages

#### `sms_received` (Android → Mac)
```json
{
  "type": "sms_received",
  "payload": {
    "from": "+1234567890",
    "contact_name": "John Doe",
    "body": "Hello!",
    "timestamp": 1699000000000
  }
}
```

#### `sms_send` (Mac → Android)
```json
{
  "type": "sms_send",
  "payload": {
    "to": "+1234567890",
    "body": "Hi there!"
  }
}
```

## Port Assignments

| Port | Channel | Protocol |
|------|---------|----------|
| 27183 | Video Stream | TCP |
| 27184 | Audio Stream | TCP |
| 27185 | Control Channel | WebSocket |
| 27186+ | File Transfer | TCP (dynamic) |

## Security

- All Wi-Fi connections use TLS 1.3
- First-time pairing requires user confirmation on both devices
- Optional PIN-based authentication
- USB connections are inherently secure (physical access)
