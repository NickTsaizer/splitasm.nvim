# splitasm.nvim

View `objdump` output beside your source and keep both sides in sync while you read compiled code.

![splitasm preview](./docs/splitasm_preview.gif)

## Features

- Open a vertical assembly split for the current source file
- Auto-detect a nearby executable or use an explicit path
- Optionally run a build command before loading assembly
- Sync cursor movement between source and assembly
- Optionally clean `objdump` output for a smaller view
- Guided `:SplitAsmSetup` / `:SplitAsmConfig` flows for first-run setup and recovery
- Clear validation errors when `setup()` receives unsupported option types

## Requirements

- Neovim 0.9+
- GNU `objdump` from binutils on your `PATH`
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
})
```

| Option | Default | Description |
| --- | --- | --- |
| `compiler_cmd` | `nil` | Command to run before loading assembly |
| `executable_path` | `nil` | Executable to inspect; when unset, SplitAsm auto-detects one |
| `auto_sync` | `true` | Keep source and assembly cursors aligned on movement |
| `clean_asm` | `false` | Remove source markers and normalize instruction text |

`require("splitasm").setup()` stays the thin public entrypoint. SplitAsm validates option types up front and reports invalid values such as non-string paths or non-boolean toggles immediately.

## Release Expectations

- SplitAsm is designed for local native executables that can be inspected with `objdump`.
- If you set `compiler_cmd`, SplitAsm runs it exactly as provided before loading assembly, so shell availability and project-local tooling are your responsibility.
- Status and recovery messages are part of the supported UX; release builds should keep README/help guidance aligned with those notifications.

## Limitations

- SplitAsm reads assembly through `objdump -d -Mintel --no-show-raw-insn -l -C`
- Source-to-assembly mapping depends on debug line markers in the binary
- Auto-detection is heuristic and may not find every build layout
- `clean_asm = true` improves readability, but slightly changes the raw `objdump` presentation
- Build failures and missing executables are reported clearly, but SplitAsm does not infer project-specific build steps for you
- The plugin currently documents and tests Unix-like `objdump`/path behavior; other toolchains may need manual configuration

## Help

After installation, see `:help splitasm`.
