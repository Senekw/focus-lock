# Focus Lock

A small Mac app that blocks distracting sites and apps while you study. Pick a timer, hit **Lock in**, and it cannot be turned off until the timer ends.

- Blocks sites in every browser (Chrome, Safari, Opera, Brave, Edge, Arc) through `/etc/hosts`
- Replaces already-open tabs of blocked sites with a "Locked in" page
- Quits blocked apps (for example the Instagram desktop app) while locked
- Signs you out of blocked sites by clearing their cookies whenever the browser is closed during a lock
- Timer choices: 30m, 1h, 2h, 3h, or no timer (free toggle)

Requires macOS 13 or later. Works on Apple Silicon and Intel.

## Install

### Option 1: build it yourself (recommended)

Needs Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/Senekw/focus-lock.git
cd focus-lock
# edit blocklist.txt now: the list is fixed once installed
bash build.sh
cp -R "build/Focus Lock.app" /Applications/
open "/Applications/Focus Lock.app"
```

Click **Finish setup** and enter your Mac password once. A locally built app opens without any Gatekeeper warning.

### Option 2: download

Grab `FocusLock.zip` from [Releases](https://github.com/Senekw/focus-lock/releases), unzip, and move the app to Applications. The app is not notarized, so the first launch is refused: go to System Settings > Privacy & Security and click **Open Anyway**. The download ships with the default blocklist.

### First lock

The first time you lock in, macOS asks whether Focus Lock may control your browser. Click **Allow** so it can replace open tabs of blocked sites.

## Blocklist

Edit `blocklist.txt` before building:

```
domain youtube.com        # blocks the site and all its subdomains
host m.youtube.com        # extra exact hostname for /etc/hosts
app Instagram             # app name or bundle id to quit while locked
```

To change the list later, edit the file, rebuild, copy the app to Applications again, and rerun the installer:

```sh
sudo bash "/Applications/Focus Lock.app/Contents/Resources/install.sh"
```

## How it works

One binary runs in three modes:

| Mode | Runs as | Job |
| --- | --- | --- |
| App | you | The window with the toggle. It only writes a request file. |
| `--daemon` | root (LaunchDaemon) | Owns the lock state and timer, writes the block section of `/etc/hosts`, restarts the agent if it is stopped. |
| `--agent` | you (LaunchAgent) | Redirects blocked tabs, quits blocked apps, clears cookies. |

The daemon ignores "off" requests until the timer ends, and everything it uses lives in root-owned folders, so getting around the lock takes an admin password and real effort. It is friction, not a security boundary: anyone with admin rights can remove it.

## Limits

- Blocking YouTube also blocks YouTube videos embedded in other sites.
- A YouTube sign-out does not stick if you are signed into Google in the same browser.
- Safari cookies are not cleared (macOS protects them).
- Sites reached through a VPN browser extension or a proxy may slip past the hosts block; the tab redirect still catches them in supported browsers.

## Uninstall

```sh
sudo bash uninstall.sh
rm -rf "/Applications/Focus Lock.app"
```

## License

MIT
