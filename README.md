# splitasm.nvim

In some cases, inspecting the source is not sufficient; the relevant behavior
is only visible in the generated machine code.

`splitasm.nvim` supports that workflow inside Neovim by opening `objdump`
output beside the current file and keeping source and assembly aligned during
navigation.

![splitasm preview](./doc/assets/splitasm_preview.gif)

## Overview

Assembly inspection often requires repeatedly switching between source code and
disassembled output. SplitAsm keeps both views in a single workspace:

- source on one side
- disassembly on the other
- optional build step before loading
- cursor sync between both buffers
- line number and address column display controls
- stable row coloring for asm lines that map back to source

## Typical workflow

1. Open a source file.
2. Run `:SplitAsmOpen`.
3. Read both sides together.

If SplitAsm already knows the executable path, no further setup is required.

Otherwise, it attempts to locate a nearby executable. If that fails, it directs
you to `:SplitAsmSetup`, `:SplitAsmConfig`, or a one-time explicit path.

Within the assembly split:

- `q` closes the split
- `r` refreshes the assembly view
- `s` toggles synchronization

The same `s` mapping is also added to source buffers while a SplitAsm session
is active.

## Requirements and backend behavior

SplitAsm depends on the following conditions:

- Neovim 0.9+
- A supported disassembler backend on your `PATH`:
  - GNU `objdump` / `objdump.exe`
  - LLVM `llvm-objdump` / `llvm-objdump.exe`
- Any external build tool referenced by `compiler_cmd` must already be
  installed and runnable from Neovim's current working directory
- A compiled executable with debug line info for best source mapping

SplitAsm reads assembly through one of these backend-specific commands:

- GNU `objdump -d -Mintel --no-show-raw-insn -l -C`
- LLVM `llvm-objdump -d -M intel --no-show-raw-insn -l -C`


## Installation

### lazy.nvim

```lua
{
  "NickTsaizer/splitasm.nvim",
  cmd = {
    "SplitAsm",
    "SplitAsmOpen",
    "SplitAsmSetup",
    "SplitAsmConfig",
    "SplitAsmToggleSync",
    "SplitAsmToggleLineNumbers",
    "SplitAsmToggleHideAddress",
  },
  opts = {},
}
```

### Minimal setup

```lua
require("splitasm").setup()
```

### Example setup

```lua
require("splitasm").setup({
  compiler_cmd = "cargo build --release",
  executable_path = "./target/release/myapp",
  source_path_mappings = {
    { from = "/work/src", to = vim.fn.getcwd() },
  },
  auto_sync = true,
  hide_address = false,
  source_row_colors = true,
  show_line_numbers = true,
})
```

## Opening an executable

Use the configured or auto-detected executable:

```vim
:SplitAsmOpen
```

Use a specific executable for a single invocation:

```vim
:SplitAsmOpen ./build/myapp
```

Windows example:

```vim
:SplitAsmOpen .\build\myapp.exe
```

When `executable_path` is unset, SplitAsm searches in:

- `.`
- `./build`
- `./bin`
- `./out`
- `./dist`

On Windows, auto-detection also tries `.exe` variants.

## Configuration

```lua
require("splitasm").setup({
  compiler_cmd = nil,
  executable_path = nil,
  source_path_mappings = {},
  auto_sync = true,
  hide_address = false,
  source_row_colors = true,
  show_line_numbers = true,
})
```

| Option | Default | Description |
| --- | --- | --- |
| `compiler_cmd` | `nil` | Command to run before loading assembly |
| `executable_path` | `nil` | Executable to inspect; when unset, SplitAsm auto-detects one, including `.exe` candidates on Windows |
| `source_path_mappings` | `{}` | Remap debug-info source prefixes to local paths, e.g. `{ from = "/work/src", to = vim.fn.getcwd() }` for container builds |
| `auto_sync` | `true` | Keep source and assembly cursors aligned on movement |
| `hide_address` | `false` | Strip address column from assembly output |
| `source_row_colors` | `true` | Apply stable subtle line highlights to asm rows that map back to a source line |
| `show_line_numbers` | `true` | Show line number column in the assembly split |

`require("splitasm").setup()` remains intentionally small. SplitAsm validates
option types up front and reports invalid values immediately.

## Commands

| Command | Description |
| --- | --- |
| `:SplitAsmOpen [path]` | Open the assembly view for the configured executable or an explicit path |
| `:SplitAsm [path]` | Alias for `:SplitAsmOpen` |
| `:SplitAsmSetup` | Guided setup for build command and executable path |
| `:SplitAsmConfig` | Show current settings, then prompt for updates |
| `:SplitAsmToggleSync` | Toggle automatic source/assembly sync |
| `:SplitAsmToggleLineNumbers` | Toggle line number column |
| `:SplitAsmToggleHideAddress` | Toggle address column visibility |

## Docker / remote build path mapping

If your binary is built in a container or remote environment, the debug markers
inside `objdump` may point at paths that do not exist on your host machine.
Use `source_path_mappings` to rewrite those prefixes before SplitAsm syncs
between source and assembly.

```lua
require("splitasm").setup({
  executable_path = "./out/demo",
  source_path_mappings = {
    { from = "/work/src", to = vim.fn.getcwd() .. "/src" },
  },
})
```

This is especially useful when you compile in Docker with a different in-
container working directory than your local checkout.

When `source_path_mappings` is empty or does not match, SplitAsm also tries a
best-effort session-local fallback based on the current file and the debug path
suffix. Explicit mappings always win.

## Limitations

- Source-to-assembly mapping depends on debug line markers in the binary
- Container or remote builds may need `source_path_mappings` when debug paths do
  not match local source paths
- Auto-detection is heuristic and may not fit every project layout
- `hide_address = true` improves readability, but removes address and label detail
- Build failures and missing executables are reported clearly, but SplitAsm
  does not infer project-specific build steps for you
- SplitAsm only supports GNU/LLVM `objdump`-style backends
- Mixed shell environments on Windows may still require manual `PATH` or
  executable-path configuration

## Help

After installation, see `:help splitasm`.
