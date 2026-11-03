# Exercise media

Decided 2026-11-03 from measurements of the snapshot at
`~/Server/docker-volumes/workouts/snapshot/media/<sourceId>/` (1,029 exercises with media):

| File | Each | All | Decision |
|---|---|---|---|
| `start.png`, `end.png` (178×100) | ~9.6 KB | 19 MB | **Bundled** with the library, folder reference `Resources/Library/thumbs/<id>-{start,end}.png` |
| `video-light.mp4` (6 s, 1080p) | ~1.05 MB | 1.06 GB | **Streamed on demand + cached** |
| `video-dark.mp4` | ~0.9 MB | 0.9 GB | Streamed on demand when the colour scheme is dark |
| `animation.gif` | ~1.8 MB | 1.8 GB | **Dropped**; the video replaces it |

## Delivery

- Base URL `https://workouts.traefik.ca/media/` (the web app already serves the snapshot read-only at
  `/media/<sourceId>/<file>`). It lives in one place, `MediaStore.baseURL`, read from
  `Info.plist` key `WorkoutsMediaBaseURL` so a TestFlight build can be repointed without code.
- `MediaStore` (WorkoutsKit): `thumbnailURL(for:phase:)` → bundled file; `video(for:scheme:)` →
  `URL` of a cached file, downloading with `URLSession` into
  `Caches/media/<sourceId>/<file>` when missing. Never blocks UI: callers get the thumbnail at
  once and the video when ready. Cache cap 2 GB by LRU (plenty for everything); "Download all
  videos" in Settings prefetches the light set; opening a template prefetches its exercises.
- Playback: `AVPlayer` looping, muted, from the local file. Thumbnail shown until ready; the
  start/end pair cross-fades as a poor-man's animation when offline.
- When the web app is retired: keep a static file server on the same path, or upload the files
  to CloudKit's public database (`xcrun cktool`) and swap the base URL. The client never
  changes shape.

Media is scraped third-party content; it stays on Eric's host and is never bundled or uploaded to
Apple, which is also why the videos aren't in the binary.
