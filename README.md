# D-Tree

A macOS disk scanner. It adds up how much space every folder takes, then shows the folders as a tree, largest first, so you can see where your disk space has gone.

## Using it

- **Scan** — choose **Scan Macintosh HD** (the whole startup disk), **Scan Home Folder**, or **Choose Folder…** (any folder or disk). The same options are in the toolbar's disk menu and the **File** menu (⌘1, ⌘2, ⌘O). **Rescan** (⌘R) scans the same place again.
- **The tree** — each row is a folder with its total size (everything inside it, including subfolders), a bar and its share of the folder you're viewing. Only folders are listed, not files. Click a folder's arrow to expand it in place and see its subfolders.
- **Look inside** — double-click a folder (or right-click › **Show Folders Inside**) to make it the folder you're viewing; its subfolders are then listed with their sizes and shares of it. The breadcrumb at the top goes back to any folder above, as does **Go › Enclosing Folder** (⌘↑) or the toolbar's up arrow.
- **Heat map** — the right-hand pane shows the same folders as coloured tiles, each sized by how much space it uses and coloured from cool blue (smaller) to hot red (larger). It follows the tree: clicking or expanding a folder shows that folder's subfolders; with nothing selected it shows the folder you're viewing. Hover over a tile for its name, size and share; click a tile to look inside that folder, as double-clicking does in the tree. Beyond 300 subfolders, the smallest are grouped into one grey tile.
- Right-click a folder to **Show in Finder** or **Copy Path**.
- The footer shows how much the files directly in the current folder use (so the folder sizes plus that add up to the total), how many folders were scanned and how long it took — or how old the saved scan is.

## Saved scans

Looking inside folders never rescans: one scan holds the whole tree. Finished scans are also saved for a while (1 hour by default; choose 15 minutes to 1 week, or off, in **Settings**, ⌘,). Scanning a folder that a saved scan covers — the same folder or one it's inside — opens it instantly, even after quitting D-Tree, and the footer says how old the scan is. **Rescan** (⌘R) always scans afresh and keeps you on the folder you're viewing. **Settings › Clear Saved Scans** deletes them.

Saved scans are stored in `~/Library/Caches/com.damonmatthews.dtree/` (folder names and sizes only, no file contents); a new scan of a folder replaces older ones of it and of the folders inside it.

## How sizes are counted

- Sizes are the space files actually take on disk (allocated blocks), the same as `du`. A hard-linked file is counted once.
- Symlinks aren't followed, and the scan stays on one disk: other disks, network drives and disk images mounted inside the folder aren't counted.
- Scanning the startup disk (`/`) includes the Data volume, where your home folder and apps really live, and skips `/System/Volumes`, which holds a second view of the same data.
- App bundles (`.app`) and other packages are treated as ordinary folders, so you can expand them.

## Full Disk Access

macOS protects some folders (Mail, Messages, Safari, other apps' data, and on some versions Desktop, Documents and Downloads). Without permission, D-Tree can't read them: they're shown with a lock and their sizes come out low, and macOS may ask for access to some of them during a scan. For complete totals, add D-Tree in **System Settings › Privacy & Security › Full Disk Access** (the start screen and footer link there), then scan again.

Because the app is signed ad hoc, macOS treats each new build as a different app, so you may need to grant access again after updating.

## Build

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
./build.sh          # builds a universal build/D-Tree.app
./build.sh --open   # builds and launches
./build.sh --dmg    # also packages dist/D-Tree-<version>.dmg (version from Resources/Info.plist)
```

Copy `build/D-Tree.app` to `/Applications` to install it.

For testing, set `DTREE_SCAN` to scan a folder at launch, e.g. `open --env DTREE_SCAN=/Applications build/D-Tree.app`.
