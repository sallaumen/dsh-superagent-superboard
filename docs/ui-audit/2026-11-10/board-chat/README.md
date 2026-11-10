# The reply box and a message's images, 2026-11-10

Workflow: `direct-interactions` (Elixir Agent Kit 0.8.0), medium.

## What the owner reported

- Send sat on its own row under the text box.
- No task showed an image, so nobody had seen how one opens.
- Wanted: click an image, see it in the app, close it, and download it from there.

## What was true in the code

| Question | Before | Now |
|---|---|---|
| Where is Send? | A separate bar under the textarea | Inside the box, on the row of the words |
| What does a thumbnail do? | Opens the file in another tab | Opens over the board; Esc, Close, a click on the image or outside close it |
| Download? | Only from the other tab | A Download button in the viewer, beside "Open in a new tab" |
| Links in a reply | Plain text | Links (http and https only), opened in another tab |
| Files named in a reply | Not shown | The same thumbnails and file links the task's own text gets |
| `**strong**` and `` `code` `` in a message | All strong parts first, then code, then the rest | In the order written |

The viewer keeps no URL of its own: it is a look at one file, and closing it
returns to the conversation, with the draft in the reply box untouched. A
modified click (Cmd, Ctrl, middle button) still opens the file in another tab.

## How it was checked

No task in the real data has a stored file (0 of the copied database), so the
captures use an isolated server on a copy of the development database, with one
task given three files and a reply with links, and a stand-in GitHub that
serves two generated images. Nothing touched the live board or GitHub.

| Capture | Shows |
|---|---|
| [01](01-inspector-1920-dark-en.png) | Inspector at 1920, dark, English: thumbnails, file chip, reply box |
| [02](02-reply-box-dark-en.png) | The reply box with focus: one ring around words and Send |
| [03](03-viewer-1920-dark-en.png) | The viewer with a wide image |
| [04](04-viewer-tall-image-dark-en.png) | The viewer with a tall image |
| [05](05-inspector-3440-light-pt.png) | 3440, light, Portuguese |
| [06](06-viewer-3440-light-pt.png) | The viewer at 3440 |
| [07](07-inspector-390-light-pt.png) | Phone: links and a reply's image |
| [08](08-viewer-390-light-pt.png) | Phone: the viewer, 44 px buttons |

Measured in WebKit: Send is 44 px tall and on the textarea's row at 1920 and
390; the image fits the window in all three sizes; the download event delivers
`hud-desktop.png`; Escape closes the viewer and leaves the inspector open; `J`
does not move the board while the viewer is open; no console errors.

## Not done

- Attaching a file from the reply box (needs the upload and the GitHub store
  the composer has; a delivery of its own).
- Images hosted outside the board (a reply's `![alt](https://…)`) stay links:
  the page loads images only from the board itself.
- Markdown headings and lists in the agent's replies still read as typed.
