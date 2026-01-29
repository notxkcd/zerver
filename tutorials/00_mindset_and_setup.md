# Part 0: The Mindset and the Workshop

Before we write a single line of code, we need to talk about the "Mindset." Modern development is a psychological operation designed to make you dependent on corporate tools. If your editor has a "Start Free Trial" button, you aren't developing; you're being harvested.

## The Toolchain

We use **Zig 0.15.2**. Not the "stable" release from three years ago, but the cutting edge. 

### Why Zig?
1.  **No Hidden Control Flow:** No `try...catch` exceptions that jump around behind your back. If a function can fail, it's right there in the signature.
2.  **No Hidden Memory Allocations:** If a function needs memory, you have to hand it an allocator. This is the ultimate "suckless" feature.
3.  **The Build System is Zig:** You use the same language to build the tool as you do to write the tool.

### Your Environment
Stop using VS Code. Use a terminal. Use Vim or Neovim. Use something that doesn't have a built-in telemetry suite. 

1.  **Download Zig:** Get the binary for your OS (Linux, obviously) from `ziglang.org`. 
2.  **Set your PATH:** Ensure `zig` is in your environment.
3.  **Project Structure:**
    ```text
    zerver/
    ├── build.zig
    ├── src/
    │   ├── main.zig
    │   ├── options.zig
    │   ├── http.zig
    │   ├── tcp.zig
    │   └── style.css
    ```

## The Mental Shift: Go vs. Zig

The original project was in Go. Go is fine for people who want to get things done quickly but don't care about the cost. Go has a "Runtime." That means when your Go program starts, it brings a whole circus of background tasks with it—garbage collection, scheduler, stack management.

In Zig, there is no runtime. There is only the code you wrote and the Standard Library. When your program starts, it jumps to `main`, and when `main` finishes, the program ends. Period.

This requires a shift in how you think about data. You don't "create an object." You "allocate memory for a struct." You don't "let the GC handle it." You "defer deinit."

If you can't handle that, go back to Python. If you can, keep reading.
