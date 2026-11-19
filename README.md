# Focus Lock

Blocks YouTube, Instagram, TikTok and other distractions on your computer while you study. Pick a timer, hit **Lock in**, and you cannot turn it off until the timer ends.

Free. Works on **Mac** and **Windows**.

## Install on Mac

1. Open **Terminal** (press Cmd + Space, type `Terminal`, press Enter).
2. Paste this line and press Enter:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Senekw/focus-lock/main/get.sh | bash
   ```

3. Focus Lock opens. Click **Finish setup** and type your Mac password.

Done. Focus Lock is in your Applications folder. Drag it to your Dock to keep it handy.

## Install on Windows

1. Click the Start button, type `PowerShell`, press Enter.
2. Paste this line and press Enter:

   ```powershell
   irm https://raw.githubusercontent.com/Senekw/focus-lock/main/windows/get.ps1 | iex
   ```

3. Click **Yes** when Windows asks for permission.

Done. Focus Lock opens, and there is a **Focus Lock** shortcut on your desktop and in the Start menu.

## How to use it

1. Open Focus Lock.
2. Pick a time: 30m, 1h, 2h or 3h. (Pick **No timer** if you want to be able to switch it off whenever.)
3. Click **Lock in**.

Focus Lock shows the exact time the lock ends (for example "Ends at 6:45 PM"), in your own time zone and clock format. Until then there is no off button. When it ends, blocking stays on until you click **Turn off**.

The first time you lock in on a Mac, it asks if Focus Lock can control your browser. Click **Allow** so it can close blocked tabs you already have open.

## What gets blocked

YouTube, Instagram, Threads, TikTok, LinkedIn, Facebook, X (Twitter), Reddit, Twitch and Netflix, in every browser. The Instagram, YouTube, TikTok and Netflix apps are closed while you are locked in.

Want a different list? See "Change the blocklist" below.

## Questions

**Why does it need my password (Mac) or admin permission (Windows)?**
Blocking websites for the whole computer needs it, and it is also what stops you from just switching the blocker off.

**I really need to get out of a lock early.**
Uninstall it (below). That takes your password on purpose.

**Chrome or Edge says "Managed by your organization" (Windows).**
That is Focus Lock's block rule. It goes away when the lock is off.

**A class video won't play.**
Blocking YouTube also blocks YouTube videos embedded in other sites, like Canvas. Use **No timer** for those sessions, or turn the lock off first.

## Uninstall

Mac, in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/Senekw/focus-lock/main/uninstall.sh | sudo bash
```

Then delete Focus Lock from Applications.

Windows, in PowerShell:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File "C:\Program Files\FocusLock\uninstall.ps1"'
```

---

## For the curious

### Other ways to install

- **Download instead of pasting a command:** get `FocusLock-Mac.zip` or `FocusLock-Windows.zip` from [Releases](https://github.com/Senekw/focus-lock/releases/latest).
  - Mac: unzip and move the app to Applications. The first launch is refused because the app is not notarized: go to System Settings > Privacy & Security and click **Open Anyway**.
  - Windows: unzip, then double-click **Install Focus Lock**. If Windows shows "Windows protected your PC", click **More info**, then **Run anyway**.
- **Build the Mac app yourself:** needs Xcode command line tools (`xcode-select --install`), then `bash build.sh` and copy `build/Focus Lock.app` to Applications.

### Change the blocklist

The list is fixed at install time, so edit it first. Clone this repo and edit `blocklist.txt`:

```
domain youtube.com
host m.youtube.com
app Instagram
```

- `domain` blocks a site and its subdomains
- `host` adds one extra exact hostname (hosts files have no wildcards)
- `app` is an app to close while locked (Mac: app name or bundle id. Windows: process name)

Then install from your copy: on Mac run `bash build.sh`, copy the app to Applications and click **Finish setup** (or rerun `sudo bash "/Applications/Focus Lock.app/Contents/Resources/install.sh"`). On Windows double-click `windows/Install Focus Lock.cmd`.

### How it works

| Part | Runs as | Job |
| --- | --- | --- |
| The window | you | Shows the toggle. It only writes a request file. |
| Background service | root (Mac LaunchDaemon) or SYSTEM (Windows scheduled task) | Owns the lock state and timer, writes the block section of the hosts file, ignores "off" until the timer ends. |
| Mac helper | you (LaunchAgent) | Replaces open tabs of blocked sites, closes blocked apps, clears their login cookies when the browser is closed. |

On Windows the service also sets the `URLBlocklist` policy for Chrome, Edge and Brave, and closes blocked apps itself.

The lock is friction, not a security boundary. Anyone with admin rights on the computer can remove it.

### Limits

- Mac: a YouTube sign-out does not stick if you are signed into Google in the same browser. Safari cookies are not cleared.
- Windows: you are not signed out of sites, and a video already playing in an open tab can keep going until the page reloads.
- Sites reached through a VPN extension or proxy can slip past the hosts block.

## License

MIT
