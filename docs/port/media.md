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

**Changed 2026-11-04 (Eric): videos go to CloudKit's public database.** The app is single-user forever, so the
licensing concern that kept them off Apple's servers no longer applies. Plan: container `iCloud.com.ericribeiro.Workouts`
(task 7.1); record type `ExerciseMedia` (`sourceId`, `videoLight`, `videoDark` assets); a one-time upload script on this Mac
using a CloudKit **server-to-server key** (public database, Web Services) into Development, then the schema deployed and the
same upload run against Production (TestFlight builds read Production); `MediaStore` fetches the record by `sourceId` and
caches the asset as today. Thumbnails stay bundled. The web app's `/media/` URL remains the interim source until then.

**Built 2026-11-04:** `MediaStore` takes an injected `MediaSource` (`fetchVideo(sourceId:scheme:)` -> local file URL or nil); the
HTTP base-URL path and `WorkoutsMediaBaseURL` are gone. The app's `CloudKitMediaSource` reads the public database record
`ExerciseMedia/<sourceId>` (`records(for:desiredKeys:)`, one asset field at a time; dark falls back to `videoLight`). The store
copies the asset into `Caches/media/<id>/video-<scheme>.mp4` as before. A missing record gives nil (thumbnails cross-fade);
network errors give nil plus a log line, with no retry. Public reads need no iCloud account, so `accountStatus` is not checked.

**Uploaded 2026-11-04:** `./dev media-upload --env development|production [--limit N] [--only <sourceId>] [--lookup]`
(`scripts/media-upload.py`, stdlib only). Server-to-server keys are per environment; the key id and private key come from
the `development` / `production` sections of the 1Password item "Apple Cloud Kit for Workouts Duo" and only ever reach a
trapped mode-600 temp file. The record type had to be created by hand in the Console (Development does not create types for
server-to-server writes), then deployed. All 1,029 records are in both environments; re-runs skip existing records.
