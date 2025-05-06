# Zig-Graphics

This repository contains my attempt at learning OpenGL using the Zig programming language.

---

## 🛠 How to Run

To run a specific program:

1. **Copy the desired program** to `main.zig`.
2. **Make a backup** of the current `main.zig` beforehand, if needed.

---

### 🔧 Debug Mode (without Tracy)

```bash
zig build run
```

### 🧪 Debug Mode (with Tracy)

```bash
zig build -Denable_ztracy=true run
```

---

### 🚀 ReleaseFast Mode (without Tracy)

```bash
zig build -Doptimize=ReleaseFast run
```

### 🚀 ReleaseFast Mode (with Tracy)

```bash
zig build -Doptimize=ReleaseFast -Denable_ztracy=true run
```

