# Tools reference

These are the 31 tools the EffectCraft MCP server exposed in bridge mode with EffectCraft 0.6.0. The full upstream reference is [docs/agents.md](https://github.com/storytold/effectcraft/blob/main/docs/agents.md) in the EffectCraft repo.

## Finding your way

| Tool | Use |
|---|---|
| `get_state` | The active comp, current time, selections and tool, plus app info (version, command and effect counts, export formats). It's cheap, so call it first. |
| `get_project` | Project items such as comps, footage and folders. |
| `get_comp` | Comp settings and its layer list. |
| `get_layer` | A layer's full property tree. Every node has a `path` you can pass to the other tools. |
| `get_property` | A property's value at a given time, plus its keyframes and expression. |
| `list_commands` / `describe_command` | Search the 665 commands and get one command's parameters, JSON schema, and whether it can run right now. |
| `list_effects` | Effect ids, categories and parameters (306 effects). |
| `list_fonts` | Fonts available to text layers. |

## Making changes

| Tool | Use |
|---|---|
| `execute_command` | Run any command by id, such as `comp.new`, `layer.newText` or `renderQueue.add`. |
| `batch` | Several commands as **one undo step**. A later step can use an earlier step's result with `"$1.layer"`. |
| `set_property` | Set a static value. Add `time` to set a keyframe, or `expression` to set an expression. |
| `add_keyframe` | Add several keys and apply `linear`, `bezier`, `hold` or `easyEase` interpolation. |
| `add_effect` | Apply an effect and set its values in one call. |
| `run_script` | Run AE-style JavaScript, e.g. `app.project`, `comp.layers.addText()`, `setValueAtTime()`. |
| `script_ui` | Operate ScriptUI dialogs and panels that scripts open. |
| `open_project` / `save_project` | Open or save a `.ecproj` (versioned JSON), open the demo, or start a new project. |
| `undo` / `redo` / `history` | Step back and forward, or jump to any branch of the undo history. |

## Seeing the result

| Tool | Use |
|---|---|
| `render_frame` | Render a PNG of a frame of the comp. `transparent: true` keeps the alpha. |
| `screenshot` | Capture the live window, or a single panel such as `Timeline`, `Composition` or `EffectControls`. *(Bridge only.)* |

## Operating the UI directly *(bridge only)*

`ui_elements`, `ui_inspect`, `ui_click`, `ui_drag`, `ui_key`, `ui_type`, `ui_set` and `control` act on widgets by their automation id, the same way you would with a mouse and keyboard. They're only needed for things that have no command.

## How things are addressed

- **Layers:** by id, by `"#n"` (1-based, counted from the top), or by name. Naming layers when you create them makes later calls easier to read.
- **Comps:** by id or name. If you leave it out, the active comp is used.
- **Properties:** by the path from `get_layer`, e.g. `transform/position`, `transform/opacity`, `effects/#1/blurriness`, `contents/trim/end`.
- **Times:** in seconds, measured in layer time. That's the same as comp time unless the layer is offset or stretched.

## Example: a title card

```text
execute_command  comp.new        {"name":"Intro","width":1920,"height":1080,"frameRate":30,"duration":4}
execute_command  layer.newText   {"text":"Hello","size":160,"fill":"#ffffff","name":"Title"}
add_keyframe     {"layer":"Title","path":"transform/position",
                  "keys":[{"time":0,"value":[-300,540]},{"time":1.5,"value":[960,540]}],
                  "interpolation":"easyEase"}
add_effect       {"layer":"Title","effect":"Glow","values":{"threshold":40,"radius":30}}
set_property     {"layer":"Title","path":"transform/rotation","expression":"wiggle(2,3)"}
render_frame     {"time":1.0}
save_project     {"path":"intro.ecproj"}
```

## Coming from After Effects

- Expressions use the AE object model: `wiggle`, `loopOut`, `thisComp.layer("…")`, and vector maths on arrays.
- `run_script` and `effectcraft-cli script` run code written against AE's documented scripting API, so many existing `.jsx` scripts may run unchanged. Test them first.
- EffectCraft can't open `.aep` or `.aepx` files, and AE plug-ins don't run in it. Rebuild projects natively, or bring edits across with `file.importTimeline` (FCP XML, OTIO, EDL or AAF).
