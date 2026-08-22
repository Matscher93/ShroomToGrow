#!/usr/bin/env python3
"""Local editor for the balance resources. Stdlib only, binds to localhost.

    python3 tools/balance_editor/server.py        # then open http://127.0.0.1:8765

Reads and writes res://data/**.tres directly: Godot is invoked headlessly to
dump every resource as a tabular snapshot, and again to write edits back. All
serialisation stays on the Godot side, so uids, [ext_resource] links and typed
array/dictionary element types survive a save untouched.

Set GODOT_BIN if `godot` is not on PATH.
"""

import errno
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parent.parent
CLI_SCRIPT = "tools/gd_balance_cli.gd"
SIM_SCENE = "tools/sc_balance_sim.tscn"

# A simulated run takes far longer than any read-only command, which is seconds.
#
# The ceiling is high because the simulator strides over idle stretches rather
# than playing them out, so a run's cost tracks how often it buys something
# rather than how many ticks it was given: ten million ticks is months of game
# time and still finishes in about the time a fifth of that used to take.
SIM_TIMEOUT = 900
SIM_MAX_TICKS = 10_000_000

# When the simulator measures what each upgrade is contributing. Validated here
# rather than passed through, so nothing a page sends can reach the command line.
SIM_BREAKDOWNS = ("milestones", "end", "off")

# How often an /api/events connection looks for a new version, and how long it
# stays silent before sending a keep-alive comment.
EVENT_POLL_SECONDS = 0.5
EVENT_HEARTBEAT_SECONDS = 15.0
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")
HOST = "127.0.0.1"
PORT = int(os.environ.get("PORT", "8765"))
OPEN_BROWSER = "--no-browser" not in sys.argv and os.environ.get("NO_BROWSER", "") == ""

# One Godot process at a time: two concurrent saves would race on the same files.
_godot_lock = threading.Lock()
_snapshot: dict = {}
# Bumped every time the .tres files are written through here. Pages watch it over
# /api/events, so a second window showing a different view redraws when the first
# one saves. Only writes made through this server count - a change made in the
# Godot editor is invisible until someone presses "Reload from .tres".
_version = 0
_derived: dict = {}      # command name -> its last report, dropped whenever data changes
# Where the running simulation is writing its progress, and when it started.
# Empty whenever nothing is running, which is what /api/sim/progress reports as
# "not running". Only ever written under _godot_lock, so there is only ever one.
_progress: dict = {}
_servers: list[ThreadingHTTPServer] = []

# Everything the page may load next to index.html. An allowlist rather than a
# path join, so no request can reach out of this directory.
STATIC_SUFFIXES = (".js", ".css")
CONTENT_TYPES = {".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8"}


class GodotError(Exception):
    pass


def run_godot(args: list[str], entry: list[str] | None = None, timeout: int = 300,
              progress: bool = False) -> dict:
    """Runs a headless Godot tool and returns the JSON report it wrote to --out.

    `entry` says what to run: the balance CLI by default, or the simulator scene,
    which cannot use --script because the ViewModels App builds address the App
    autoload by name.

    `progress` asks the tool to keep a file saying how far it has got, and
    publishes where that file is while the run lasts, for /api/sim/progress to
    read. Only the simulator writes one - it is the only command that takes long
    enough for anyone to want it.
    """
    with _godot_lock, tempfile.TemporaryDirectory() as tmp:
        out_path = Path(tmp) / "report.json"
        command = [GODOT_BIN, "--headless", *(entry or ["--script", CLI_SCRIPT]), "--",
                   *args, f"--out={out_path}"]
        if progress:
            progress_path = Path(tmp) / "progress.json"
            command.append(f"--progress={progress_path}")
            _progress["path"] = progress_path
            _progress["started"] = time.time()
        try:
            done = subprocess.run(command, cwd=PROJECT_ROOT, capture_output=True,
                                  text=True, timeout=timeout)
        except FileNotFoundError:
            raise GodotError(f"{GODOT_BIN} not found - set GODOT_BIN")
        except subprocess.TimeoutExpired:
            raise GodotError(f"godot timed out after {timeout}s")
        finally:
            # The temporary directory goes with this block, so the path has to
            # stop being published before it does.
            _progress.clear()
        if not out_path.exists():
            detail = (done.stderr or done.stdout or "").strip().splitlines()
            raise GodotError("godot wrote no report: " + " / ".join(detail[-3:]))
        return json.loads(out_path.read_text())


def sim_progress() -> dict:
    """How far the running simulation has got, for a page that is waiting.

    Read on demand rather than pushed: this is polled while a run lasts and
    forgotten the rest of the time. A run that has not written its first update
    yet, or one caught mid-write, reports as running with nothing to show rather
    than as an error - the next poll is 300ms away.
    """
    path = _progress.get("path")
    if path is None:
        return {"running": False}
    state = {"running": True, "elapsed": round(time.time() - _progress.get("started", 0.0), 1)}
    try:
        state.update(json.loads(Path(path).read_text()))
    except (OSError, ValueError):
        pass
    return state


def load_snapshot() -> dict:
    """Re-reads every .tres into the in-memory snapshot."""
    global _snapshot, _version
    report = run_godot(["dump"])
    if report.get("errors"):
        raise GodotError("; ".join(report["errors"]))
    _snapshot = report["data"]
    _derived.clear()     # curves and perks are derived from what just changed
    _version += 1
    return _snapshot


def simulate(request: dict) -> dict:
    """One simulated run. Not cached: the whole point is to re-run it.

    A `save` in the request starts the run from that state instead of from a
    fresh one - an uploaded save file, or one savepoint out of an earlier run.
    `from_tick` and `from_seconds` say where that state already stood, so a
    continued run's chart carries on from the run it came out of instead of
    restarting at zero.

    `breakdowns` says how often the run measures what each upgrade contributes.
    Every milestone by default; it is the expensive part of a run, so a long one
    can ask for "end" or "off" instead.
    """
    breakdowns = str(request.get("breakdowns", "milestones"))
    if breakdowns not in SIM_BREAKDOWNS:
        raise ValueError(f"breakdowns must be one of {', '.join(SIM_BREAKDOWNS)}")
    args = [
        f"--ticks={min(int(request.get('ticks', 20000)), SIM_MAX_TICKS)}",
        f"--prestiges={int(request.get('prestiges', 3))}",
        f"--samples={int(request.get('samples', 200))}",
        f"--policy={str(request.get('policy', 'roi'))}",
        f"--breakdowns={breakdowns}",
    ]
    with tempfile.TemporaryDirectory() as tmp:
        start = request.get("save")
        if isinstance(start, dict):
            # Handed over as a file rather than on the command line: a save is
            # kilobytes of JSON, well past what an argument list wants to carry.
            start_path = Path(tmp) / "start.json"
            start_path.write_text(json.dumps(start))
            args += [
                f"--load={start_path}",
                f"--from-tick={max(0, int(request.get('from_tick', 0)))}",
                f"--from-seconds={max(0.0, float(request.get('from_seconds', 0.0)))}",
            ]
        report = run_godot(args, entry=[SIM_SCENE], timeout=SIM_TIMEOUT, progress=True)
    if report.get("errors"):
        raise GodotError("; ".join(report["errors"]))
    return report


def derived(command: str, fresh: bool = False) -> dict:
    """One of the read-only report commands, cached until the data changes.

    Each is a fresh Godot process, so they are computed on demand rather than
    alongside the dump every save does.

    `fresh` forces the Godot run. Callers use it when what changed is upstream of
    the data - the report is derived by GDScript, and nothing here notices that.
    """
    if fresh:
        _derived.pop(command, None)
    if command not in _derived:
        report = run_godot([command])
        if report.get("errors"):
            raise GodotError("; ".join(report["errors"]))
        _derived[command] = report
    return _derived[command]


def table(name: str) -> dict:
    if name not in _snapshot:
        raise ValueError(f"no such table: {name}")
    return _snapshot[name]


def build_patch(name: str, header: list[str], rows: list[list[str]]) -> dict:
    """Diffs submitted rows against the snapshot, keyed by res_path."""
    current = table(name)
    if header != current["header"]:
        raise ValueError(f"{name}: columns do not match the snapshot - reload first")
    by_path = {row[0]: row for row in current["rows"]}
    patch: dict[str, dict[str, str]] = {}
    for row in rows:
        if len(row) != len(header):
            raise ValueError(f"{name}: row '{row[0]}' has {len(row)} of {len(header)} fields")
        was = by_path.get(row[0])
        if was is None:
            raise ValueError(f"{name}: unknown row {row[0]} - reload first")
        changed = {header[i]: row[i] for i in range(1, len(header)) if row[i] != was[i]}
        if changed:
            patch[row[0]] = changed
    return patch


def run_with_payload(command: str, flag: str, payload: dict, dry_run: bool) -> dict:
    """Hands a JSON payload to the CLI through a temp file."""
    with tempfile.TemporaryDirectory() as tmp:
        payload_path = Path(tmp) / "payload.json"
        payload_path.write_text(json.dumps(payload))
        args = [command, f"{flag}={payload_path}"]
        if dry_run:
            args.append("--dry-run")
        return run_godot(args)


def apply_patch(patch: dict, dry_run: bool) -> dict:
    if not patch:
        return {"changes": [], "saved": 0, "errors": []}
    return run_with_payload("apply", "--patch", patch, dry_run)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, payload: dict, status: int = 200) -> None:
        self._send(status, json.dumps(payload).encode("utf-8"), "application/json")

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    def _events(self) -> None:
        """Server-sent events: one message per version, forever.

        Every open page listens, so a save made in one window reaches the others
        without either of them knowing the other exists. Polling a counter beats
        waking threads through a condition: the loop is one integer comparison
        twice a second, and a dropped connection is noticed on the next write.
        """
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        seen = -1
        idle = 0.0
        try:
            while True:
                if _version != seen:
                    seen = _version
                    self.wfile.write(f"data: {seen}\n\n".encode())
                    self.wfile.flush()
                    idle = 0.0
                time.sleep(EVENT_POLL_SECONDS)
                idle += EVENT_POLL_SECONDS
                if idle >= EVENT_HEARTBEAT_SECONDS:
                    # A comment line, ignored by EventSource, but it is what
                    # notices a browser that closed the tab without saying so.
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    idle = 0.0
        except (BrokenPipeError, ConnectionResetError):
            return          # the page went away, which is not an error

    def _static_file(self) -> Path | None:
        """The view module this request asks for, or None. Only plain file names
        directly beside index.html resolve, so `..` cannot walk anywhere."""
        name = self.path.lstrip("/")
        if "/" in name or not name.endswith(STATIC_SUFFIXES):
            return None
        path = HERE / name
        return path if path.is_file() else None

    def do_GET(self) -> None:
        try:
            if self.path in ("/", "/index.html"):
                self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
            elif self.path == "/api/files":
                if not _snapshot:
                    load_snapshot()
                self._send_json({"files": sorted(_snapshot), "project": str(PROJECT_ROOT)})
            elif self.path.startswith("/api/file/"):
                self._send_json(table(self.path[len("/api/file/"):]))
            elif self.path == "/api/events":
                self._events()
            elif self.path == "/api/sim/progress":
                self._send_json(sim_progress())
            elif self.path.split("?")[0] in ("/api/curves", "/api/perks", "/api/unused"):
                # ?fresh=1 drops the cache first. The cache is keyed off data
                # writes, so a change to the .gd that *derives* the report - a
                # layout constant in PerkTree, a new column in gd_balance_data -
                # leaves a stale report served until the server restarts.
                path, _, query = self.path.partition("?")
                self._send_json(derived(path[len("/api/"):], "fresh=1" in query))
            elif self._static_file():
                path = self._static_file()
                self._send(200, path.read_bytes(), CONTENT_TYPES[path.suffix])
            else:
                self._send_json({"error": "not found"}, 404)
        except Exception as error:  # surfaced in the page, not just the terminal
            self._send_json({"error": str(error)}, 400)

    def do_PUT(self) -> None:
        try:
            if not self.path.startswith("/api/file/"):
                self._send_json({"error": "not found"}, 404)
                return
            name = self.path[len("/api/file/"):]
            payload = self._body()
            patch = build_patch(name, payload["header"], payload["rows"])
            report = apply_patch(patch, payload.get("dry_run", False))
            if report["errors"]:
                self._send_json({"error": "; ".join(report["errors"])}, 400)
                return
            if patch and not payload.get("dry_run"):
                load_snapshot()          # pick up whatever Godot actually wrote
            self._send_json({"ok": True, "version": _version, "changes": report["changes"],
                             "saved": report["saved"], "table": _snapshot.get(name)})
        except Exception as error:
            self._send_json({"error": str(error)}, 400)

    def do_POST(self) -> None:
        try:
            if self.path == "/api/create":
                payload = self._body()
                dry_run = bool(payload.pop("dry_run", False))
                report = run_with_payload("create", "--request", payload, dry_run)
                if report["errors"]:
                    self._send_json({"error": "; ".join(report["errors"])}, 400)
                    return
                if not dry_run:
                    load_snapshot()      # the new row has to appear everywhere
                self._send_json({"ok": True, "version": _version, "path": report["path"],
                                 "changes": report["changes"], "files": sorted(_snapshot)})
            elif self.path == "/api/delete":
                payload = self._body()
                dry_run = bool(payload.pop("dry_run", False))
                report = run_with_payload("delete", "--request", payload, dry_run)
                if report["errors"]:
                    self._send_json({"error": "; ".join(report["errors"]),
                                     "collateral": report.get("collateral", [])}, 400)
                    return
                if not dry_run:
                    load_snapshot()
                self._send_json({"ok": True, "version": _version, "path": report["path"],
                                 "changes": report["changes"],
                                 "collateral": report.get("collateral", []),
                                 "needs_force": report.get("needs_force", False),
                                 "files": sorted(_snapshot)})
            elif self.path == "/api/shutdown":
                self._send_json({"ok": True})
                print("shutdown requested from the page", flush=True)
                stop_servers()
                return
            elif self.path == "/api/sim":
                self._send_json(simulate(self._body()))
            elif self.path == "/api/reload":
                load_snapshot()
                self._send_json({"ok": True, "version": _version, "files": sorted(_snapshot)})
            else:
                self._send_json({"error": "not found"}, 404)
        except Exception as error:
            self._send_json({"error": str(error)}, 400)


class ServerV6(ThreadingHTTPServer):
    """`localhost` resolves to ::1 first on plenty of systems, and a v4-only
    bind makes the browser fail the fetch with a bare NetworkError."""

    address_family = socket.AF_INET6


def bind(server_class: type[ThreadingHTTPServer], host: str) -> ThreadingHTTPServer | None:
    try:
        return server_class((host, PORT), Handler)
    except OSError as error:
        if error.errno == errno.EADDRINUSE:
            raise
        return None  # no IPv6 on this box, or the loopback alias is missing


def open_now(url: str) -> None:
    try:
        webbrowser.open(url)
    except Exception as error:                # a headless box has no browser
        print(f"could not open a browser ({error}) - go to {url}", file=sys.stderr)


def running_editor(url: str) -> dict | None:
    """Whatever is already on the port: this editor's identity, or None."""
    try:
        with urllib.request.urlopen(f"{url}/api/files", timeout=3) as response:
            payload = json.load(response)
        return payload if "files" in payload and "project" in payload else None
    except Exception:
        return None


def stop_servers() -> None:
    """shutdown() must not run on the thread serving requests, so it is deferred
    a moment - which also lets the response reach the browser first."""
    def go() -> None:
        time.sleep(0.2)
        for server in _servers:
            server.shutdown()
    threading.Thread(target=go, daemon=True).start()


def open_browser(url: str) -> None:
    """Opens the page once the socket is accepting. The listening socket exists
    from bind(), so the request queues until serve_forever() picks it up - but
    the call is threaded anyway, since a browser launch can block for seconds."""
    def go() -> None:
        time.sleep(0.3)
        open_now(url)
    threading.Thread(target=go, daemon=True).start()


def main() -> None:
    url = f"http://{HOST}:{PORT}"
    try:
        server = bind(ThreadingHTTPServer, HOST)
        server_v6 = bind(ServerV6, "::1")
    except OSError:
        # Re-running the script is the obvious way to ask for the page, so treat
        # it as that rather than as an error - but only if the editor already
        # there is serving this same project.
        running = running_editor(url)
        if running is None:
            print(f"port {PORT} is already in use, and it is not this editor.", file=sys.stderr)
            print(f"stop it, or use another port: PORT={PORT + 1} python3 {__file__}",
                  file=sys.stderr)
            raise SystemExit(1)
        if running.get("project") != str(PROJECT_ROOT):
            print(f"an editor is already running on {url}, but for a different project:",
                  file=sys.stderr)
            print(f"  {running.get('project')}", file=sys.stderr)
            print(f"use another port: PORT={PORT + 1} python3 {__file__}", file=sys.stderr)
            raise SystemExit(1)
        print(f"already running on {url} - opening that one", flush=True)
        if OPEN_BROWSER:
            open_now(url)
        return
    _servers.extend(s for s in (server, server_v6) if s is not None)

    print(f"reading {PROJECT_ROOT / 'data'} through {GODOT_BIN}…", flush=True)
    try:
        load_snapshot()
        print(f"{sum(len(t['rows']) for t in _snapshot.values())} rows "
              f"across {len(_snapshot)} resource types", flush=True)
    except Exception as error:
        print(f"could not read the resources: {error}", file=sys.stderr, flush=True)

    if server_v6 is not None:
        threading.Thread(target=server_v6.serve_forever, daemon=True).start()

    print(f"balance editor on {url}", flush=True)
    if OPEN_BROWSER:
        open_browser(url)
    else:
        print("opening index.html as a file:// page cannot reach the API - use that URL",
              flush=True)
    try:
        server.serve_forever()
        print("stopped", flush=True)
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
