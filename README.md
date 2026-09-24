# roblox-game

Luau source for the game, synced into Roblox Studio with [Rojo](https://rojo.space).

## Project layout

| Folder        | Appears in Studio as                              | Use for                          |
| ------------- | ------------------------------------------------- | -------------------------------- |
| `src/server`  | `ServerScriptService.Server`                      | Server-only scripts and modules  |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`       | Client scripts and modules       |
| `src/shared`  | `ReplicatedStorage.Shared`                        | Modules used by server and client |

Rojo turns files into instances based on their names:

| File name              | Instance created                               |
| ---------------------- | ---------------------------------------------- |
| `Name.server.luau`     | `Script`                                       |
| `Name.client.luau`     | `LocalScript`                                  |
| `Name.luau`            | `ModuleScript`                                 |
| `Folder/`              | `Folder`                                       |
| `Folder/init.luau`     | The folder becomes a `ModuleScript` (children stay inside it) |

The `.gitkeep` files only keep the empty folders in git. Rojo ignores them, and you can delete them once a folder has real files.

## Connecting to Roblox Studio

1. **Install Rojo 7.** Use one of these:
   - The **Rojo** extension for VS Code. It installs the CLI and can install the Studio plugin for you.
   - The CLI through a toolchain manager, for example `rokit add rojo-rbx/rojo`.
   - A download from the [Rojo releases page](https://github.com/rojo-rbx/rojo/releases).
2. **Install the Studio plugin** by running `rojo plugin install`. You can also install it from the VS Code extension or the Creator Store.
3. **Start the sync server** from the repo root:
   ```sh
   rojo serve
   ```
   It reads `default.project.json` and listens on `localhost:34872`.
4. **Connect from Studio.** Open your place, go to **Plugins → Rojo**, and click **Connect**. When you save a file in `src/`, the change shows up in Studio right away.

To build a standalone place file without Studio, run `rojo build -o game.rbxlx`. `.gitignore` excludes built place files.

## Bringing in the existing game

Rojo manages only the three folders above. It doesn't touch anything else in your place: Workspace, Lighting, UI and any scripts outside those folders stay as they are.

To move a script into the repo:

1. Create a file in the matching `src/` folder, using the naming rules above.
2. Paste the script's source into the file.
3. Delete the original script in Studio, or it will run twice.

Rojo mostly syncs one way, from files into Studio. Edits made to synced scripts inside Studio are overwritten the next time the file changes, so edit synced scripts in the repo instead.
