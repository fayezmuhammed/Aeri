<p align="center"><img src="Assets/aeri_logo.png" width="240" alt="Aeri"></p>

# Aeri

A lightweight macOS app that turns the MacBook notch into a small, useful space. Hover over the notch to expand it.

- **Now Playing**: track, artwork, progress and controls for Music, Spotify and browser media
- **Shelf**: drop files on the notch to hold them, then drag them out where you need them
- **Clipboard**: recent copies, with color swatches for hex codes, thumbnails for images and the host for links
- **Weather**: current conditions from [Open-Meteo](https://open-meteo.com), with no API key or account

Requires macOS 14 or later on Apple Silicon.

## Install

1. Download `Aeri-<version>.zip` from [Releases](https://github.com/fayezmuhammed/Aeri/releases) and unzip it.
2. Move `Aeri.app` to your Applications folder and open it.
3. Aeri isn't notarized by Apple, so macOS blocks the first launch. Open **System Settings › Privacy & Security**, scroll down, click **Open Anyway** and confirm. You only need to do this once.

   Alternatively, in Terminal: `xattr -dr com.apple.quarantine /Applications/Aeri.app`

Hover over the notch to open Aeri. Use the gear menu to turn on **Launch at Login** or quit.

When Aeri first shows what's playing, macOS asks whether it may control Music, Spotify or your browser. Click OK. After updating Aeri you may be asked again.

## Build from source

```bash
swift build --build-system native
swift run --build-system native
```

To package `dist/Aeri.app` and a release zip: `scripts/package.sh 0.1.0`

Browser media needs "Allow JavaScript from Apple Events" turned on in each browser (Safari: Develop menu; Chrome-based browsers: View › Developer).

## License

[MIT](LICENSE)
