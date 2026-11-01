# Aeri

A lightweight macOS app that turns the MacBook notch into a small, useful space. Hover over the notch to expand it.

- **Now Playing**: track, artwork, progress and controls for Music, Spotify and browser media
- **Shelf**: drop files on the notch to hold them, then drag them out where you need them
- **Clipboard**: recent copies, with color swatches for hex codes, thumbnails for images and the host for links
- **Weather**: current conditions from [Open-Meteo](https://open-meteo.com), with no API key or account

Requires macOS 14 or later.

## Build

```bash
swift build --build-system native
swift run --build-system native
```

Browser media needs "Allow JavaScript from Apple Events" turned on in each browser (Safari: Develop menu; Chrome-based browsers: View › Developer).
