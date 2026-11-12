# Keycheat

An Omarchy shell plugin that keeps the keybinding cheat sheet at the right edge
of the screen. It stays hidden until the pointer touches the edge, then slides
out, themed by the running Omarchy theme. Pin it to keep it open.

Two tabs share the panel: **Omarchy** (the compositor's bindings) and **Tmux**.
It reads `omarchy menu keybindings --print` and
`omarchy-menu-tmux-keybindings --print`, so it shows every binding those menus
show, including your own additions in `~/.config/hypr/bindings.lua` and
`~/.config/tmux/tmux.conf`, and reloads when either changes.

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
- **Tabs** (under the search field): `Omarchy` shows the compositor's bindings,
  `Tmux` shows tmux's. The search only looks inside the tab you are on.
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
out with the search field ready, so you can type immediately. Press it again to
close it: on a pinned screen that also unpins, exactly like **Hide**. While the
field has the keyboard the panel takes it exclusively; `Escape` (twice if there
is text) gives it back, and focusing another window does too.

`SUPER + arrow` keeps working while the field has the keyboard, so a search never
traps you on that screen. Hyprland refuses focus changes while a layer surface
holds the keyboard exclusively, so the panel lets go first and the move is
dispatched right after. That needs one extra bind per direction, in the same
file, next to the search bind:

```lua
-- Sem descrição, para não aparecerem na lista de atalhos.
for _, direction in ipairs({ "left", "right", "up", "down" }) do
  o.bind("SUPER + " .. direction:upper(), nil,
    "omarchy-shell jr.keycheat leave " .. direction, { non_consuming = true })
end
```

They do not consume the key: the normal `SUPER + arrow` bind still runs, and with
no search open these do nothing. An unpinned panel slides away when you leave it
this way; a pinned one stays and keeps its reserved space.

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
omarchy-shell jr.keycheat search     # open the focused screen's search, or close it
omarchy-shell jr.keycheat leave DIR  # give the keyboard back, then focus DIR (left/right/up/down)
omarchy-shell jr.keycheat refresh    # re-read the bindings
```

## How it works

- `manifest.json` declares `kinds: ["service"]`; the shell mounts `Service.qml`
  at startup.
- `Service.qml` reads the bindings once, parses them with `Binds.js`, and owns
  the per-screen pin state. It listens for Hyprland's `configreloaded` event so
  a binding edit shows up without a restart, and for `activewindow` so a search
  stops holding the keyboard when another window takes the focus.
- The Tmux tab runs `omarchy-menu-tmux-keybindings --print`, which parses the
  config in a throwaway tmux server, and watches `$TMUX_CONF` (default
  `~/.config/tmux/tmux.conf`) so an edit refreshes the tab. It reuses the same
  row renderer: `Binds.parseTmux` and `Binds.groupTmux` only differ in ordering,
  with the prefix table first, the root-table binds next and copy mode last.
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
- Because `Exclusive` also makes Hyprland refuse every window focus change, the
  `leave` IPC releases the keyboard and only then dispatches
  `hl.dsp.focus({ direction = … })`. The `non_consuming` binds are what call it,
  so the user's own `SUPER + arrow` bind keeps working when no search is open.

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
- Layer surfaces cannot be selected with `SUPER + arrow`; use the `search` IPC
  (see Keybind above).
- Leaving a search with `SUPER + arrow` needs the extra `leave` bind in
  `~/.config/hypr/bindings.lua`; without it the arrow is swallowed while the
  field holds the keyboard.
- While a search holds the keyboard it is exclusive, so `Escape`, `SUPER + arrow`
  or focusing another window is what gives it back.
- Rows are read from `omarchy menu keybindings --print`; a bind without a
  description is not listed there either.
- The Tmux tab shows what `omarchy-menu-tmux-keybindings --print` shows, so a
  tmux bind needs a note (`bind -N "…"`) to be listed, and binds from plugins or
  a live server's runtime changes are not picked up — only what the config file
  declares.

## License

MIT
