# 🚀 Zerver Pro (Zig Edition)

A professional-grade, suckless, and ultra-fast file-serving machine rewritten from Go to pure Zig 0.15.2. This is not just a server; it's an elite development environment in a single tiny binary.

> **Note:** This project was completely **vibe coded using Gemini CLI**.

## 💎 Elite Features

1.  **💡 Highlight & Scroll**: Automatically pulses the section of the page you just edited in the browser. Never lose your place again.
2.  **🚀 Aggressive Live Server**: Ultra-low latency 100ms file watching with instant SSE-based browser reload.
3.  **🔊 Remote Logging**: Real-time browser `console.log` proxying—see your JavaScript logs directly in your server's terminal in vibrant colors.
4.  **🐘 PHP Support**: Execute PHP scripts natively without a separate server setup (requires `php` in PATH).
5.  **🎨 Elite UI**: Modern, Material Design directory listing with hand-crafted SVG icons for 10+ programming languages.
6.  **📦 Zero Dependencies**: Built entirely with the Zig Standard Library. No external bloat, no DLL hell.
7.  **🌍 Multi-Platform**: Statically linked, ultra-compressed binaries for Linux, Windows, and macOS (x86_64 and aarch64).

## 📚 Masterclass Tutorials

Go from Go-developer to Zig-expert with our step-by-step masterclass:

- [Chapter 0: Mindset and Setup](tutorials/00_mindset_and_setup.md)
- [Chapter 1: The Foundations of Zig](tutorials/01_introduction.md)
- [Chapter 2: Memory & CLI Mastery](tutorials/02_memory_and_cli.md)
- [Chapter 3: HTTP I/O Internals](tutorials/03_http_io_internals.md)
- [Chapter 4: Security & Sandboxing](tutorials/04_security_and_sandbox.md)
- [Chapter 5: Pro Features & Auth](tutorials/05_features_and_auth.md)
- [Chapter 6: TCP & Hot Reloading](tutorials/06_tcp_and_hot_reloading.md)
- [Chapter 7: The Embedded Frontend](tutorials/07_embedded_frontend.md)
- [Chapter 8: The String Incident (Advanced Troubleshooting)](tutorials/08_the_string_incident.md)
- [Chapter 9: The Verdict: Go vs Zig](tutorials/09_comparison_go_vs_zig.md)
- [Chapter 10: Final Source Review](tutorials/10_final_source_review.md)

## 📖 Documentation
Detailed API documentation is available at [https://notxkcd.github.io/zerver-zig/](https://notxkcd.github.io/zerver-zig/)

## 🛠️ Performance & Security
- **Multithreaded**: One OS thread per connection for maximum throughput.
- **Suckless**: Optimized for `ReleaseSmall`, resulting in binaries as small as **130KB**.
- **Security-First**: Optional **Sandbox Mode** to prevent path traversal and enforce strict filesystem isolation.
- **Smart Binding**: Automatically scans for the next available port if the requested one is occupied.

## 📦 Building

### Prerequisites
- Zig Compiler `0.15.2` or newer.

### Commands
```bash
# Standard build (Produces static and dynamic binaries)
zig build

# Build ultra-lean static release binaries for all targets
zig build build-all -Doptimize=ReleaseSmall

# Filter build by architecture
zig build build-all -Darch=x86_64
```

## 🚩 Command Line Flags

- `-ls, -live-server`: Enable the **Elite Live Server** (Reload + Highlighting + Logging)
- `-path <path>`: Root folder to serve (default: `.`)
- `-port <port>`: Listen port (default: `8000`)
- `-proxy <url>`: Reverse proxy to a backend (SSR support)
- `-upload`: Enable file uploads via `PUT`
- `-cors`: Enable permissive CORS headers
- `-basic-auth <u:p>`: Enable Basic Authentication
- `-file <path>`: Fallback file for SPA routing (e.g., `index.html`)
- `-verbose`: Show request logs and debug info
- `-silent`: Suppress all terminal output
- `-help`, `-h`: Show help menu

## 📜 License
[Suckless / MIT]
