# splitasm.nvim

View `objdump` output beside your source and keep both sides in sync while you read compiled code.

![shaderdebug preview](./doc/assets/splitasm_preview.gif)


## Features

- Open a vertical assembly split for the current source file
- Auto-detect a nearby executable or use an explicit path
- Optionally run a build command before loading assembly
- Sync cursor movement between source and assembly
- Optionally clean `objdump` output for a smaller view
- Stable subtle row colors for mapped source-backed assembly lines
- Guided `:SplitAsmSetup` / `:SplitAsmConfig` flows for first-run setup and recovery
- Clear validation errors when `setup()` receives unsupported option types

## Requirements

- Neovim 0.9+
- A supported disassembler backend on your `PATH`:
  - GNU `objdump` / `objdump.exe`
  - LLVM `llvm-objdump` / `llvm-objdump.exe`
- Any external build tool referenced by `compiler_cmd` must already be installed and runnable from Neovim's current working directory
- A compiled executable with debug line info for best source mapping

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
  },
  opts = {},
}
```

### Setup with defaults

```lua
require("splitasm").setup()
```

### Setup with a build command

```lua
require("splitasm").setup({
  compiler_cmd = "cargo build --release",
  executable_path = "./target/release/myapp",
  auto_sync = true,
  clean_asm = false,
  source_row_colors = true,
})
```

## Quick Start

1. Open a source file.
2. Run `:SplitAsmOpen`.
3. Move the cursor in either split.

If no executable is configured, SplitAsm looks in:

- `.`
- `./build`
- `./bin`
- `./out`
- `./dist`

After-MVP improvements add guided recovery messaging here too: if auto-detection fails, SplitAsm points you back to `:SplitAsmSetup`, `:SplitAsmConfig`, or a one-off `:SplitAsmOpen ./path/to/program` call.

## Commands

| Command | Description |
| --- | --- |
| `:SplitAsmOpen [path]` | Open the assembly view for the configured executable or an explicit path |
| `:SplitAsm [path]` | Alias for `:SplitAsmOpen` |
| `:SplitAsmSetup` | Guided setup for build command and executable path |
| `:SplitAsmConfig` | Show current settings, then prompt for updates |
| `:SplitAsmToggleSync` | Toggle automatic source/assembly sync |

## Usage

Open the detected executable:

```vim
:SplitAsmOpen
```

Open a specific executable once:

```vim
:SplitAsmOpen ./build/myapp
```

Windows example:

```vim
:SplitAsmOpen .\build\myapp.exe
```

Use the split buffer keys:

- `q` — close the assembly split
- `r` — refresh the assembly view
- `s` — toggle sync

`SplitAsmConfig` is the main after-MVP recovery path: it shows runtime status first, then the saved configuration, then prompts for updates.

## Configuration

```lua
require("splitasm").setup({
  compiler_cmd = nil,
  executable_path = nil,
  auto_sync = true,
  clean_asm = false,
  source_row_colors = true,
})
```

| Option | Default | Description |
| --- | --- | --- |
| `compiler_cmd` | `nil` | Command to run before loading assembly |
| `executable_path` | `nil` | Executable to inspect; when unset, SplitAsm auto-detects one, including `.exe` candidates on Windows |
| `auto_sync` | `true` | Keep source and assembly cursors aligned on movement |
| `clean_asm` | `false` | Remove source markers and normalize instruction text |
| `source_row_colors` | `true` | Apply stable subtle line highlights to asm rows that map back to a source line |

`require("splitasm").setup()` stays the thin public entrypoint. SplitAsm validates option types up front and reports invalid values such as non-string paths or non-boolean toggles immediately.

## Release Expectations

- SplitAsm is designed for local native executables that can be inspected with `objdump`.
- SplitAsm supports GNU `objdump` and LLVM `llvm-objdump`, and selects the first available backend on your `PATH`.
- If you set `compiler_cmd`, SplitAsm runs it exactly as provided before loading assembly, so shell availability and project-local tooling are your responsibility on Unix-like systems and Windows.
- Status and recovery messages are part of the supported UX; release builds should keep README/help guidance aligned with those notifications.

## Limitations

- SplitAsm reads assembly through one of these backend-specific commands:
  - GNU `objdump -d -Mintel --no-show-raw-insn -l -C`
  - LLVM `llvm-objdump -d -M intel --no-show-raw-insn -l -C`
- Source-to-assembly mapping depends on debug line markers in the binary
- Auto-detection is heuristic and may not find every build layout
- Windows auto-detection tries `.exe` variants, but you may still need to pass an explicit executable path for unusual build outputs
- `clean_asm = true` improves readability, but slightly changes the raw `objdump` presentation
- Build failures and missing executables are reported clearly, but SplitAsm does not infer project-specific build steps for you
- SplitAsm only supports GNU/LLVM objdump-style backends; other disassemblers are not supported
- Mixed shell environments on Windows (for example MSYS2 or Git Bash driving native `.exe` tools) may still require manual PATH and executable-path configuration

## Help

After installation, see `:help splitasm`.
