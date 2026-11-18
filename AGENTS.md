# AGENTS.md

Godot 4.7 third-person LAN shooter (GDScript). Listen server: the host also plays.
ENet over UDP 9999, up to 8 players, main scene `scenes/main_menu.tscn`.

## Verify

- There is no test suite, linter, CI, or export preset. Verification is manual: open
  the project in the Godot 4.7 editor and press F5.
- Multiplayer testing: Debug → Customize Run Instances → 2 instances, join `127.0.0.1`.
- Always launch through `main_menu.tscn`. Running `scenes/game.tscn` directly has no
  peer; it stays in the connecting state and never spawns players.

## Architecture that is not obvious

- `scripts/network_manager.gd` is the `NetworkManager` autoload and the only place that
  creates/closes `ENetMultiplayerPeer`. Menus call `create_server()` / `join_server()`;
  do not touch `multiplayer.multiplayer_peer` elsewhere.
- Server-authoritative: clients send only input (`receive_input`, `unreliable_ordered`,
  60 Hz); the server computes movement, shots, damage, medkits and score. Clients
  interpolate replicated position/yaw in `player.gd` `_process`; positions are never sent
  by clients.
- Player and bullet node names are protocol: players are named `str(peer_id)` (1 = host)
  and bullets `B<peer>_<n>`. RPC routing and `Players/<id>` lookups depend on them.
  New multiplayer nodes must also use server authority (`player.gd` calls
  `set_multiplayer_authority(1)`).
- The map, HUD, effects and most nodes are built in code. `scenes/game.tscn` only holds
  empty containers, spawners and a HUD skeleton. Change arena geometry in `game.gd`
  (`QUADRANT_WALLS` is mirrored into four quadrants) and HUD in `hud.gd`, not in the
  `.tscn`.
- Asset dimensions are hand-measured constants: `WALL_MODEL_SIZE` / `BOX_MODEL_SIZE` in
  `game.gd`, and `IDLE_SECTION` / `RUN_SECTION` in `player.gd` (all characters share one
  FBX skeleton and the single clip `Take 001`). Re-measure if models change.
- Replication is explicit: `scenes/player.tscn` `SceneReplicationConfig` lists every
  synced property (30 Hz). A new `@export` in `player.gd` will not replicate until it is
  added there.
- Spawning: players use the custom `spawn_function` in `game.gd` with data
  `[peer_id, slot, name]`; bullets use `add_spawnable_scene`. `main_menu.gd` loads the
  game scene before the ENet handshake finishes on purpose, so spawners exist when the
  server starts replicating.
- Input is mostly polled with `Input.is_key_pressed`; only default `ui_*` actions are
  used. There is no `[input]` section in `project.godot`, so define new actions there
  rather than assuming they exist.
- Reliability convention (see `docs/red.md`): per-frame input is `unreliable_ordered`,
  per-frame state is unreliable, one-shot events are `reliable` with `call_local`.

## Repo constraints

- Comments, UI strings, docs and commit messages are in Spanish. Match them.
- `project.godot` pins Godot 4.7 features, Forward+, Jolt Physics and D3D12 on Windows.
- `.uid` and `.import` files are tracked and required; `.godot/` is ignored. Never
  delete or hand-edit a `.uid` file.
- `addons/godot_ai/` is a vendored third-party MCP plugin (enabled editor plugin plus
  the `_mcp_game_helper` autoload), not game code. Do not modify it; if removing it,
  also remove the autoload and `editor_plugins/enabled` entry from `project.godot`.
- In-game debug keys: F3 network panel; F4 adds delay and F5 packet loss (clients only,
  panel must be open). Use this to reproduce latency without real networking.
- The server PC must allow inbound UDP 9999; the `netsh` command is in
  `docs/prueba-real.md`.

## References

- `README.md` — run steps, controls, gameplay.
- `docs/red.md` — topology, addressing, routes, per-message reliability table.
- `docs/prueba-real.md`, `docs/simulacion-packet-tracer.md` — physical and Packet Tracer
  test procedures.
- `docs/informe/main.tex` — IEEE report (LaTeX, no committed build script).
