# Token Island 🏝️

A sleek, lightweight, multi-display native macOS Dynamic Island application for monitoring **Antigravity (Gemini, Claude 3.7 / Opus)** and **ChatGPT / Codex** quotas in real-time.

<p align="center">
  <img src="Resources/AppIcon.icns" width="128" height="128" alt="Token Island Icon" />
</p>

---

## ✨ Features

- 🏝️ **Native Dynamic Island Experience**: Sits unobtrusively inside the MacBook notch as an ultra-compact, pure OLED black pill (`92px × 26px`).
- ⚡ **Zero-Delay Live Quota Probing**:
  - **Antigravity**: Local LanguageServer gRPC/RPC HTTPS integration (`RetrieveUserQuotaSummary`) for 100% authoritative rate limit tracking.
  - **ChatGPT / Codex**: Direct real-time `wham/usage` session & weekly rate limit syncing.
- 🖥️ **Multi-Display Support**: Automatically creates and synchronizes dedicated Dynamic Islands across all connected external monitors and built-in Retina displays.
- 🛡️ **Pixel-Level Anti-Misclick**: Only triggers when the cursor physically hovers directly over the notch pill.
- 📐 **35px Safety Margin**: Gracefully expands below the macOS menu bar to prevent any notch camera occlusion.
- 🎨 **Provider-Specific Color Schemes**:
  - 🟢 **ChatGPT / Codex**: OpenAI Emerald Green
  - 🔵 **Gemini**: Google Electric Cyan
  - 🟠 **Claude / GPT**: Anthropic Warm Amber
- 🛑 **Right-Click Context Menu**: Right-click the island anytime to manually refresh or quit.

---

## 🚀 Installation & Build from Source

### Prerequisites
- macOS 14.0 (Sonoma) or later
- Swift 5.9+ / Xcode Command Line Tools

### Build & Run
```bash
git clone https://github.com/your-username/token_island.git
cd token_island
swift build -c release

# Package into macOS .app
mkdir -p token_island.app/Contents/MacOS token_island.app/Contents/Resources
cp .build/release/token_island token_island.app/Contents/MacOS/
cp Resources/AppIcon.icns token_island.app/Contents/Resources/
codesign --force --deep --sign - token_island.app
open token_island.app
```

---

## 🔒 Privacy & Security

`Token Island` is 100% local and open-source. It does not collect any telemetry, send external logs, or hardcode private keys. All credentials are read dynamically from standard local session caches.

---

## 💡 Acknowledgments

- Quota protocol insights inspired by [mimir](https://github.com/erayendes/mimir).
- Built with ❤️ using native Swift & SwiftUI.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
