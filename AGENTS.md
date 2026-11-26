# learncpp.nvim

Neovim plugin (Lua, Neovim >= 0.10, needs `curl`) that caches learncpp.com lessons as Markdown and shows them in
buffers. No build step and no dependencies; snacks.nvim's picker is used when present, `vim.ui.select` otherwise.

## Layout

- `lua/learncpp/html.lua` - HTML tokenizer and HTML -> Markdown converter (pure, no I/O)
- `lua/learncpp/store.lua` - sync over the WordPress REST API, table of contents and site index parsing, cache files
- `lua/learncpp/search.lua` - symbol under cursor, symbol -> lessons lookup, full-text search
- `lua/learncpp/reader.lua` - lesson buffers: folded solutions, link following, next/previous
- `lua/learncpp/run.lua` - code block under the cursor, compile-and-run in a terminal split, scratch files, sandbox
- `lua/learncpp/style.lua` - look of lesson buffers: per-buffer render-markdown.nvim options, box highlights
- `lua/learncpp/picker.lua`, `init.lua`, `plugin/learncpp.lua` - picker, public API, `:LearnCpp`

## Tests

Headless, offline, one file per module; a failing check exits non-zero:

```sh
nvim --headless -u NONE -l tests/html.lua
nvim --headless -u NONE -l tests/store.lua
nvim --headless -u NONE -l tests/search.lua
nvim --headless -u NONE -l tests/reader.lua
nvim --headless -u NONE -l tests/run.lua
```

`tests/run.lua` also compiles and runs one program for real when a C++ compiler is on PATH.

The look is checked by eye, or by attaching to `nvim --embed` as a UI and reading back cell backgrounds; headless
`screenstring()` output does not show colours.

Changing what `html.convert` emits needs a bump of `VERSION` in `store.lua`, which makes every cache re-sync.

Fixtures are hand-written in the shape of the site's markup. Do not commit lesson content or the cache: the site
allows private copies only.

## Showcase

`vhs demo/demo.tape` (from the repository root) re-records `demo/demo.gif` using `demo/init.lua`, a minimal config
that borrows catppuccin, snacks.nvim, mini.icons, render-markdown.nvim and nvim-treesitter from a lazy.nvim install.
VHS only accepts relative paths. Re-record after changing how lessons look.

## Style

2-space indent, 120 columns (stylua defaults of the user's Neovim config), double quotes.
