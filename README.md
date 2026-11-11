# Keycheat

An Omarchy shell plugin that keeps the keybinding cheat sheet at the right edge
of the screen. It stays hidden until the pointer touches the edge, then slides
out, themed by the running Omarchy theme. Pin it to keep it open.

It reads `omarchy menu keybindings --print`, so it shows every binding the
`SUPER + K` panel shows, including your own additions in
`~/.config/hypr/bindings.lua`, and reloads when Hyprland reloads its config.

## Requirements

- Omarchy Quattro (the shell plugin system and `omarchy-shell` IPC)
- Nothing else: the panel runs inside the existing `omarchy-shell` process.

## Install

```bash
cp -r ~/Work/keycheat ~/.config/omarchy/plugins/jr.keycheat
omarchy-shell shell rescanPlugins
omarchy plugin enable jr.keycheat
```

Enabling writes the plugin into `~/.config/omarchy/shell.json`. To turn it off
again without deleting it:

```bash
omarchy plugin disable jr.keycheat
```

## Usage

- Move the pointer to the right edge of the screen: the panel slides out.
- Move away: it slides back after a moment.
- **Search** (top of the panel): click the field, or press the keybind below, and
  type. It filters on the modifier, the key and the description. `Escape` clears
  the text, then closes the panel. The query is kept if the panel hides, so
  hovering it again brings the same results back.
- **Pin**: keeps the panel open **on that screen only** and reserves its width,
  so the tiling layout makes room instead of covering the windows. Other
  screens are untouched.
- **Hide**: unpins that screen and lets the panel slide away.

Hovering a row wraps its description instead of truncating it.

The card uses the same inset as the tiled windows (`gaps_out + border_size`), so
its outline lines up with theirs instead of floating over the edge.

### Keybind

Hyprland's directional focus (`SUPER + arrow`) only moves between windows; layer
surfaces such as this panel are not in that list, so they cannot be selected
that way. Bind the IPC command instead:

```lua
o.bind("SUPER + SHIFT + K", "Keycheat search", "omarchy-shell jr.keycheat search")
```

Add it to `~/.config/hypr/bindings.lua`. The panel on the focused screen slides
out with the search field ready, so you can type immediately. While the field
has the keyboard the panel takes it exclusively; `Escape` (twice if there is
text) gives it back, and focusing another window does too.

## Configuration

Optional overrides in `~/.config/omarchy/shell.json`, under a `keycheat` key:

```json
{
  "keycheat": {
    "width": 360,
    "opacity": 0.94,
    "pinned": false
  }
}
```

| Key | Default | Meaning |
|---|---|---|
| `width` | `360` | Panel width in pixels (clamped 240–640) |
| `opacity` | `0.94` | Background opacity (clamped 0.4–1) |
| `pinned` | `false` | Start pinned on every screen |

The file hot-reloads on save. `pinned` is only read at startup; pinning from the
panel or IPC lasts for the session.

## IPC

```bash
omarchy-shell jr.keycheat toggle     # pin / unpin the focused screen
omarchy-shell jr.keycheat pin        # pin the focused screen
omarchy-shell jr.keycheat unpin      # unpin the focused screen
omarchy-shell jr.keycheat pinAll     # pin every screen
omarchy-shell jr.keycheat unpinAll   # unpin every screen
omarchy-shell jr.keycheat search     # reveal the focused screen and focus search
omarchy-shell jr.keycheat refresh    # re-read the bindings
```

## How it works

- `manifest.json` declares `kinds: ["service"]`; the shell mounts `Service.qml`
  at startup.
- `Service.qml` reads the bindings once, parses them with `Binds.js`, and owns
  the per-screen pin state. It listens for Hyprland's `configreloaded` event so
  a binding edit shows up without a restart, and for `activewindow` so a search
  stops holding the keyboard when another window takes the focus.
- `Panel.qml` is one `PanelWindow` per screen: anchored right/top/bottom, layer
  `Top`, `exclusiveZone` equal to its width while pinned and `0` while hidden.
  The surface stays mapped and only slides its card off-screen, so revealing it
  is instant.
- While hidden, the layer surface's input region (`mask`) is a thin strip at the
  edge, so clicks and scrolls reach the windows underneath. No screen space is
  reserved and tiled windows keep their width.
- The search field filters in `Binds.js` (`filter`). Keyboard focus
  (`WlrKeyboardFocus.Exclusive`) is only taken while a search is active, because
  `OnDemand` cannot be granted to a programmatic request; a short retry timer
  nudges focus once the compositor hands the keyboard over.

## Development

```bash
node --test test/                     # Binds.js parsing and grouping
omarchy plugin validate .             # manifest against the shell's schema
```

Saving a file under `~/.config/omarchy/plugins/jr.keycheat/` reloads the plugin.
If a change does not apply, force it:

```bash
omarchy-shell shell rescanPlugins
```

## Limitations

- One panel per screen, with the pin tracked per screen.
- Layer surfaces cannot be reached with `SUPER + arrow`; use the `search` IPC
  (see Keybind above).
- While a search holds the keyboard it is exclusive, so `Escape` or focusing
  another window is what gives it back.
- Rows are read from `omarchy menu keybindings --print`; a bind without a
  description is not listed there either.

## License

MIT
