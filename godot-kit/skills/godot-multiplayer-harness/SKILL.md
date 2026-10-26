---
name: godot-multiplayer-harness
description: Prove that Godot 4 multiplayer code works - a REAL headless server and REAL client(s) as separate engine processes, every process's log judged, plus a static check that every RPC sent has an @rpc function to land on. Use when you add or change networking, RPCs, ENet/MultiplayerPeer code, lobby/host/join logic or server-authoritative rules, when asked to test multiplayer, or before reporting that a networking fix works. Runs through the godot-run skill's runner.
---

# godot-multiplayer-harness

Networking bugs hide from every single-process check. All of these were measured on Godot 4.7.2 (Windows and
Linux) with the kit's `tests/measure_traps.sh`, and every process involved **exits 0**:

| What happened | Where the evidence is |
|---|---|
| `.rpc()` on a function without `@rpc`, or `rpc_id(1, "no_such_method")` | an `ERROR: Unable to get the RPC configuration...` in the **sender's** log only. The receiver never hears of it. |
| server and client have the RPC node at different paths | `ERROR: ... Requested node was not found` in the **receiver's** log only. The sender's script runs to the end as if all was fine. |
| the port is taken | `create_server` returns 20 and logs `ERROR: Couldn't create an ENet host.` |
| a client connects while nobody listens | `connection_failed` arrives after **~31 s** |
| the server dies mid-session | the client hears `server_disconnected` after **~10 s** |
| a script calls `.rpc()` on a non-`@rpc` function | it compiles: the parse gate PASSES it |

So a multiplayer check needs three things:

- **Every process's log judged.** Judging only one log misses the first two rows.
- **Positive assertions on what each side received.** Without them, the second row reads as success.
- **Its own short timeouts.** Without them, the last two rows hold a run for 10-30 s, and then it just says "timeout".

## 1. Run a harness

```bash
bash "${CLAUDE_SKILL_DIR}/net_run.sh" --path . res://tools/netdiag_hits.tscn
bash "${CLAUDE_SKILL_DIR}/net_run.sh" --path . --clients 3 res://tools/netdiag_lobby.tscn
```

`net_run.sh` does the following:

1. It imports once, then starts the server and N clients, each with `--no-import`. Parallel imports would write the
   same `.godot/` at the same time.
2. Each process runs through the `godot-run` runner, so it is isolated and has a `--quit-after` and wall-clock
   backstop.
3. Each process gets `-- --role=server|client --port=P --clients=N`.
4. It waits for all of them and judges **each log**.

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-NET: PASS (server + N client(s))` | 0 | every process passed (banner, no error token, exit 0) |
| `GODOT-NET: FAIL (<roles>)` | 1 | names each role that did not pass; its runner lines are printed above |
| `GODOT-NET: NO-ENGINE` | 3 | no binary: see the `godot-run` skill |

More options:

- `--port P` sets the port. By default it is random in 20000-49999.
- `--no-import`: only for runs after the first in a session, while no file was added or moved.
- `--timeout S`, default 120 per process.
- `--out <dir>` keeps the logs.

The `godot-ci` skill runs every `netdiag_*.tscn` this way, together with the static RPC check below.

## 2. Write one

```bash
bash "${CLAUDE_SKILL_DIR}/scaffold.sh" --path . lobby     # res://tools/netdiag_lobby.gd + .tscn
```

It fails on purpose, on **both** sides, until you replace the two placeholders with real checks. The
template already contains the parts that are easy to get wrong:

- role and port parsing,
- `_wait_until` (a short timeout that also ends on `connection_failed` / `server_disconnected`),
- the "client done" handshake,
- a server that binds **127.0.0.1 only**,
- closing the peer before quitting.

Binding every interface would ask the Windows firewall for an exception on the first run. If the game has its own
`host()` / `join()`, call those from `_host()` / `_join()` so that they are under test too.

The demo's `res://tools/netdiag_hits.gd` is a filled-in example. A client asks the server for hits. The server
validates each one against the real `Health` and syncs the hp back. The checks:

- the **client** asserts the synced values (`[70, 69]`),
- the **server** asserts the hp it applied, the hits it refused and the hits it accepted.

## 3. The harness contract

Each rule exists because breaking it gave a green run that was wrong:

1. **One scene, both roles.** The same scene gives the same node paths on both sides. Two scenes whose RPC node
   sits at different paths drop every RPC, and the error appears only on the receiving side.
2. **Instantiate the real game scene in both roles,** as a child of the harness, and drive it. Never a copy of its
   logic.
3. **Assert what came back, not what was sent.**
   - The client checks the value the server synced.
   - The server checks the state it applied and how many requests it accepted and refused.
   - The sender's script ends normally whether or not anything arrived.
4. **Every network wait has a timeout,** and also ends on the failure signals. Use `_wait_until`, never a bare
   `await multiplayer.connected_to_server`: ENet's own limits are ~31 s and ~10 s.
5. **A refused request produces no message.** To prove a refusal, follow it with a valid request and assert the
   next sync. The demo sends 9999, then 1, and expects `[70, 69]`.
6. **The server prints its banner only after every client reported done** (or the wait timed out). Otherwise the
   server can say PASS while a client is still failing.
7. **`EXPECTED` per role** is asserted, as in single-process harnesses. A check that silently did not run is a FAIL.
8. **Close the peer before `quit()`.** The other side then hears it at once, instead of after ENet's ~10 s.

## 4. Static RPC check

```bash
bash "${CLAUDE_SKILL_DIR}/rpc_check.sh" --path .
```

It reports every sent RPC that has no `@rpc` function to land on, with `file:line`. That covers
`foo.rpc()` / `foo.rpc_id()` where `foo` is a function of the project, and the string forms
`x.rpc("foo")` / `rpc_id(id, "foo")`.

- It ignores comments and text inside strings.
- `@rpc` counts both on the line above `func` (other annotations may come between) and on the same line. So does
  `rpc_config("foo", {...})`.
- Declarations in `addons/` count, because game code may call an addon's RPCs. Calls *inside* `addons/` are not
  checked: third-party code is not yours to fail.
- `ci.sh --no-rpc-check` turns it off for a project it misreads.
- **It works by name.** If any class declares `@rpc func foo`, every `foo.rpc()` passes.
- A method name held in a variable is skipped and counted in the summary, never guessed.

The check is a pre-filter; the harness run is the proof.

## 5. Prove the harness bites

As with single-process harnesses, a check is not done until you have seen it fail for the right reason. Break one
thing at a time and restore it byte for byte (`cmp`). Measured on the demo:

| Sabotage | Result |
|---|---|
| a FAIL on one side only | that role FAILs, the other PASSes, the verdict is FAIL |
| the client's game node at another path | both FAIL; the server log has `Requested node was not found` |
| `@rpc` removed from `sync_hp` in the game code | the server log has `Unable to get the RPC configuration`; the client FAILs its sync checks; `rpc_check.sh` names the line |
| the port taken by another socket | `listening on port` FAILs, the client FAILs `connected` after the harness's 10 s, not ENet's 31 s |

## 6. Reporting

Report:

- the `GODOT-NET:` line,
- each role's runner verdict,
- the `ok` / `FAIL` lines of every role,
- the log directory.

For a new check, include the sabotage run that made it FAIL and the restored run that made it PASS. "Server
passes" alone says nothing about the clients.
