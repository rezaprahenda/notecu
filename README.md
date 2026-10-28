<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="notecu icon">
</p>

<h1 align="center">notecu</h1>

<p align="center">
  <i>notes lucu</i> — a little notes app that peeks in from the edge of your Mac's screen.<br>
  <b>note it, cu later.</b>
</p>

---

Push your cursor against the edge of the screen (or press **⌃⌥N**) and notecu slides in, so you can jot
something down without leaving the app you're in. Everything stays **on your Mac**: no account,
no server, no internet needed.

> The app's interface is in Indonesian 🇮🇩.

## Features

**Notes**
- Titles, folders, color markers, pinning and `#tags`
- Checklists `- [ ]`, bullets, numbered lists, `# headings`, **bold**, *italic*, `code` and clickable links
- **Links between notes** with `[[Title]]` — type `[[` for suggestions, and every note shows where it's *mentioned*
- **Secrets 🔒**: select text and press ⌘L, or lock a whole note.
  AES-256-GCM, key derived with PBKDF2-SHA256 (210,000 rounds); the password is never stored

**Daily agenda**
- One card per meeting topic, grouped by day → month → year
- New agendas start with a *Participants / Discussion / Conclusion / Follow-up* outline
- To-dos created from a note stay linked to it

**To-dos**
- Due dates and times, ★ important, folders, tags, reminders in Notification Center
- **Smart sentences** — `Surati Kapusdatin besok 10:00 ! #kementan` becomes
  *due tomorrow 10:00, important, tagged #kementan*
- **Repeating to-dos** (`tiap senin`, `tiap tgl 25`…): checking one off schedules the next
- Undo right after checking off, and a full history grouped by month

**Monthly summary**
- Agendas, finished and ongoing to-dos for any month, grouped by type or by tag
- Copy as Markdown or save it as a note — handy for monthly reports

**Stays out of the way**
- Lives in the menu bar, slides in from the left or right edge, closes when you click away
- Trash keeps things for 30 days; JSON backup & restore; launch at login

## Requirements

- macOS 14 Sonoma or later
- Command Line Tools (`xcode-select --install`) — Xcode itself is not needed

## Build & install

```bash
git clone https://github.com/rezaprahenda/notecu.git
cd notecu
./build.sh install     # build, copy to /Applications and launch
```

`./build.sh` only builds; `./build.sh run` builds and launches from `build/`.

The app is signed ad-hoc. If macOS refuses to open it the first time, right-click **notecu.app → Open**.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥N | Show / hide the panel from anywhere |
| ⌃⌥⇧N | New note from anywhere |
| ⌃⌥T | New to-do from anywhere |
| ⌘N / ⌘D / ⌘T | New note / agenda / to-do (inside the panel) |
| ⌘F | Search |
| ⌘L | Turn the selected text into a secret |
| ⌘[ | Back to the list |
| Esc / ⌘W | Close the panel |

## Writing to-dos

Words are recognized in Indonesian and removed from the title:

| Write | Means |
|---|---|
| `hari ini`, `besok`, `lusa` | today, tomorrow, the day after |
| `jumat`, `senin depan`, `hari minggu`, `minggu depan` | a weekday, next Monday, Sunday, next week |
| `tgl 5`, `3/11`, `akhir bulan`, `awal bulan depan` | the 5th, 3 Nov, end of month, start of next month |
| `3 hari lagi`, `2 minggu lagi`, `sebulan lagi` | in 3 days, in 2 weeks, in a month |
| `10:00`, `jam 14`, `9.30`, `besok sore`, `nanti malam` | a time (pagi 09:00, siang 12:00, sore 15:00, malam 19:00) |
| `tiap hari`, `tiap hari kerja`, `tiap senin`, `tiap tgl 25`, `tiap bulan` | repeats |
| `!` | important |
| `#tag` | tag |

## Your data

- Stored in `~/Library/Application Support/notecu/cache.json`
- **Settings → Umum → Data** to back up to JSON, restore, or reveal the folder in Finder
- The secrets password is not saved anywhere — **if you forget it, locked content can't be recovered**

## Project layout

```
Sources/
  App.swift             menu bar item, global hotkeys, settings window
  PanelController.swift edge panel, in-panel shortcuts
  PanelViews.swift      list, editor, agenda, links
  NoteStore.swift       data & local storage
  Models.swift          data model, text rules
  Tasks.swift           to-dos, smart sentences, repeating to-dos
  TaskViews.swift       to-do views
  Tags.swift            #tags
  Vault.swift           secrets & locked notes
  Summary.swift         monthly summary
  Reminders.swift       Notification Center reminders
  NoteTextView.swift    text editor (NSTextView)
  SettingsView.swift    settings
build.sh                builds without Xcode
```

## License

[MIT](LICENSE) © 2026 Reza Prahenda

---

<p align="center">made with ♥ by <a href="https://instagram.com/rezaprahenda">@rezaprahenda</a></p>
