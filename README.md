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
- **Pin**: keeps it open on every screen until unpinned.
- **Hide**: unpins and lets it slide away.

Hovering a row wraps its description instead of truncating it.

The panel never takes keyboard focus, so it can stay open while you type in
another window.

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
| `pinned` | `false` | Start pinned |

The file hot-reloads on save. `pinned` is only read at startup; pinning from the
panel or IPC lasts for the session.

## IPC

```bash
omarchy-shell jr.keycheat toggle    # pin / unpin
omarchy-shell jr.keycheat pin
omarchy-shell jr.keycheat unpin
omarchy-shell jr.keycheat refresh   # re-read the bindings
```

## How it works

- `manifest.json` declares `kinds: ["service"]`; the shell mounts `Service.qml`
  at startup.
- `Service.qml` reads the bindings once, parses them with `Binds.js`, and owns
  the shared pin state. It listens for Hyprland's `configreloaded` event so a
  binding edit shows up without a restart.
- `Panel.qml` is one `PanelWindow` per screen: anchored right/top/bottom, layer
  `Top`, `keyboardFocus: None`, `exclusiveZone: 0`. The surface stays mapped and
  only slides its card off-screen, so revealing it is instant.
- While hidden, the layer surface's input region (`mask`) is a thin strip at the
  edge, so clicks and scrolls reach the windows underneath. No screen space is
  reserved and tiled windows keep their width.

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

- One panel per screen, all sharing the same pin state.
- No search field: the panel cannot take keyboard focus without stealing it from
  the window you are working in.
- Rows are read from `omarchy menu keybindings --print`; a bind without a
  description is not listed there either.

## License

MIT
