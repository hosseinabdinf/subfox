# subfox

A small Bash tool that tidies up subtitles for TV series.

1. **List** the episodes in a folder (file names without extension).
2. **Rename** the `.srt` subtitle files so each one matches its episode's file name, plus a suffix of your choice.

Before renaming, subfox checks that the subtitle really belongs to that episode by comparing the season/episode number and the series title, so messy names still work:

| Subtitle file name                | Detected as |
|-----------------------------------|-------------|
| `snowy S01E12.srt`                | S01E12      |
| `Snowy S01 E12 WEB.SRT`           | S01E12      |
| `snowy.s01.e12.srt`               | S01E12      |
| `snowy 1x12.srt`                  | S01E12      |
| `snowy.season.1.episode.12.srt`   | S01E12      |

**Example result**

```
Video:     snowy.S01E12.HDTV.mkv
Subtitle:  snowy S01 E12.srt
Renamed:   snowy.S01E12.HDTV.en.1.srt
```

## Requirements

- Linux (or any system with Bash 4+ and GNU `find`/`sort`)
- Nothing else to install

> macOS ships with Bash 3.2, which is too old. Install a newer one with `brew install bash`.

## Installation

### 1. Get the script

```bash
git clone https://github.com/YOUR-USERNAME/subfox.git
cd subfox
chmod +x subfox
```

### 2. Make it callable from anywhere

Pick **one** of the options below.

#### Option A: system-wide (needs sudo)

```bash
sudo cp subfox /usr/local/bin/subfox
```

Open a new terminal and run `subfox -h` to test. Nothing else is needed, because `/usr/local/bin` is already in your `PATH`.

#### Option B: only for your user (no sudo)

```bash
mkdir -p ~/.local/bin
cp subfox ~/.local/bin/subfox
```

Most distros already include `~/.local/bin` in `PATH`. If `subfox -h` says "command not found", add it permanently:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Using zsh? Use `~/.zshrc` instead of `~/.bashrc`.

#### Option C: keep the script where it is and add its folder to PATH

```bash
echo 'export PATH="$PATH:/path/to/subfox-folder"' >> ~/.bashrc
source ~/.bashrc
```

#### Option D: use an alias

```bash
echo "alias subfox='bash /path/to/subfox'" >> ~/.bashrc
source ~/.bashrc
```

The `>> ~/.bashrc` part is what makes it **permanent**: the line is loaded every time you open a terminal. `source ~/.bashrc` applies it to the current terminal right away.

## Usage

```
subfox -s DIR [-o FILE]
subfox -r DIR [-f LIST] -suf SUFFIX [options]
```

### Options

| Option            | Description                                                                 |
|-------------------|-----------------------------------------------------------------------------|
| `-s DIR`          | Scan `DIR` for video files and print their names without extension          |
| `-o FILE`         | Used with `-s`: write the list to `FILE` instead of printing it            |
| `-r DIR`          | Folder containing the `.srt` files to rename                                |
| `-f FILE`         | Episode list created by `-s`. If omitted, the list is built from `DIR` itself |
| `-suf SUFFIX`     | Suffix added before `.srt`, e.g. `en.1` gives `name.en.1.srt`               |
| `-n`              | Dry run: show what would be renamed, change nothing                         |
| `--force`         | Overwrite target files that already exist                                   |
| `--no-title`      | Match by season/episode number only, ignore the series title                |
| `-h`              | Show help                                                                   |

Supported video extensions: `mkv mp4 avi mov wmv m4v ts flv webm mpg mpeg`

### Examples

**1. List the episodes in a folder**

```bash
subfox -s /home/series/snowy/
```

```
snowy.S01E11.HDTV
snowy.S01E12.HDTV
snowy.S01E13.HDTV
```

**2. Save the list to a file**

```bash
subfox -s /home/series/snowy/ -o items.txt
# or
subfox -s /home/series/snowy/ > items.txt
```

**3. Preview the renaming first (recommended)**

```bash
subfox -r /home/series/snowy/ -f items.txt -suf en.1 -n
```

```
[dry] snowy S01E12.srt -> snowy.S01E12.HDTV.en.1.srt
[dry] Snowy S01 E13 WEB.SRT -> snowy.S01E13.HDTV.en.1.srt
```

**4. Rename for real**

```bash
subfox -r /home/series/snowy/ -f items.txt -suf en.1
```

**5. One step, no list file**

If the subtitles and videos are in the same folder, skip `-f`:

```bash
subfox -r /home/series/snowy/ -suf en
```

**6. Videos and subtitles in different folders**

```bash
subfox -s /home/series/snowy/ -o items.txt
subfox -r /home/downloads/snowy-subs/ -f items.txt -suf fi
```

**7. Ignore the title, use the episode number only**

Useful when the subtitle uses a different name for the show:

```bash
subfox -r /home/series/snowy/ -suf en --no-title
```

**8. Several languages**

Run it once per subtitle folder with a different suffix:

```bash
subfox -r ./subs-english/ -f items.txt -suf en
subfox -r ./subs-finnish/ -f items.txt -suf fi
```

### Paths with spaces

Always put the path in quotes:

```bash
subfox -s "/mnt/mvi/02 Videos/Series/Gilmore.Girls.Complete/S01/" -o items.txt
subfox -r "/mnt/mvi/02 Videos/Series/Gilmore.Girls.Complete/S01/" -f items.txt -suf en.1
```

Without quotes the shell splits the path into separate arguments and subfox stops with `unknown option`. Nothing is renamed in that case.

## How matching works

1. The season and episode are read from every file name and converted to a standard key such as `S01E12`. Supported forms: `S01E12`, `S01 E12`, `S01.E12`, `1x12`, `Season 1 Episode 12`.
2. The text before that tag is treated as the series title, lowercased with punctuation removed. A subtitle passes when its title and the video's title contain one another (`gilmore girls` matches `Gilmore.Girls`). If the subtitle has no title, the episode key alone decides.
3. The subtitle is renamed to `<video name>.<suffix>.srt`.

subfox is careful by design:

- It never overwrites an existing file unless you use `--force`.
- If two subtitles match the same episode, the first one is renamed and the other is reported and left untouched.
- Subtitles that don't match anything (no tag, unknown episode, different series) are reported and left as they are.
- It only touches `.srt` files (case-insensitive) directly inside the folder you give it, not subfolders.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `subfox: command not found` | The folder is not in your `PATH`. See the installation options above and open a new terminal. |
| `Permission denied` | Run `chmod +x subfox`. |
| `unknown option: ...` | Quote paths that contain spaces. |
| `declare: -A: invalid option` | Your Bash is older than 4.0. Update Bash. |
| A subtitle shows `title mismatch` | Its series name differs too much from the video. Check the name or use `--no-title`. |
| Nothing renamed, all `no such episode` | The list in `-f` is from a different season or folder. Recreate it with `-s`. |

## License

MIT. Use it, change it, share it.
