# Zerver-Zig Documentation

A high-performance, multithreaded, and secure file-serving machine rewritten from Go to pure Zig 0.15.2.

## Table of Contents
1. [Installation and Building](#1-installation-and-building)
2. [Quick Start](#2-quick-start)
3. [CLI Reference](#3-cli-reference)
4. [Core Features](#4-core-features)
    - [HTTP File Server](#http-file-server)
    - [TCP Rule Server](#tcp-rule-server)
    - [Security & Sandboxing](#security--sandboxing)
5. [Internal Architecture](#5-internal-architecture)
6. [Troubleshooting](#6-troubleshooting)

---

## 1. Installation and Building

### Requirements
- **Zig Compiler**: Version 0.15.2 or higher.

### Build Commands
The project uses the standard Zig build system.

- **Standard Build** (Current Host):
  ```bash
  zig build
  ```
  Generates two binaries in `zig-out/bin/`:
  - `zerver-static`: Pure Zig standalone binary.
  - `zerver-dynamic`: Linked against system `libc`.

- **Cross-Compilation** (Build for Linux, Windows, macOS):
  ```bash
  zig build build-all
  ```
  This will generate static and dynamic binaries for x86_64 and aarch64 across all three major operating systems in the `zig-out/bin/` directory.

- **Optimized for Size (Production)**:
  ```bash
  zig build -Doptimize=ReleaseSmall
  ```

- **Generate Built-in HTML Docs**:
  ```bash
  zig build docs
  ```
  Docs will be in `zig-out/docs/`.

---

## 2. Quick Start
...
---

## 4. Core Features

### HTTP File Server
- **MIME Detection**: Automatically detects file extensions (.html, .js, .css, .png, etc.) and sets the correct `Content-Type` header so browsers render files instead of downloading them.
- **Directory Listing**: Automatically generates a Material Design UI with embedded CSS.
- **PUT Method**: If `-upload` is enabled, files can be uploaded via `curl -T file.txt http://server:8000/`.
- **Base64 Auth**: Verifies `Authorization: Basic <blob>` against the `-basic-auth` flag.

### TCP Rule Server
Allows responding to raw TCP packets based on content matching.
- **Hot Reloading**: Watches the `-rules` file for changes every 2 seconds and reloads them without downtime.
- **Match Types**: Supports `match` (exact) and `match-contains`.

### Security & Sandboxing
- **Path Canonicalization**: All paths are resolved using `realpath` to prevent `../` traversal attacks.
- **Sandbox Mode**: When enabled, the server strictly validates that the resolved path is a child of the root `-path`.

---

## 5. Internal Architecture

### Memory Management
- **GeneralPurposeAllocator**: Used throughout the application to ensure zero memory leaks.
- **Thread Safety**: The TCP rule engine uses a `std.Thread.RwLock` to allow multiple concurrent readers while the file watcher reloads rules.

### I/O System
- **Buffered Readers**: Utilizes the Zig 0.15 `std.Io.Reader` pattern with pre-allocated 8KB buffers per connection.
- **Streaming**: Responses use `respondStreaming` to pipe data directly from the disk to the network, keeping RAM usage low even for large files.

### Assets
- **Style.css**: Embedded into the binary using `@embedFile`. This ensures the server remains a single, portable executable.

---

## 6. Troubleshooting

### "Address already in use"
The server features **Dynamic Port Binding**. If the requested port is busy, it will automatically try `port + 1` and notify you in the logs.

### "Forbidden" Error
If `-sandbox` is enabled, ensure your symlinks do not point to files outside of your served `-path`.

### String Literal Errors
If modifying the source, remember that Zig 0.15 does not allow literal newlines in double-quoted strings. Use `\n` or multi-line `\\` strings.
