"""Reproducible native GraphML inspect benchmark using only Python's standard library.

Default workloads are exactly 1,000/10,000/100,000 nodes and five edges per
node, with self-loops and parallel edges. Each is run in a fresh process at
least three times. Timing includes process startup, file I/O, decoding,
parse/validation, statistics, and process shutdown; it is not isolated parser
CPU time. Memory is the child process's working set/RSS, not Python's memory.

All generated input, run output, and result files remain in ignored .local/.
No performance comparison with other libraries is implied. --smoke is explicitly
labelled incomplete and does not replace the default full-size workloads.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time
import traceback


ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / ".local" / "benchmark-artifacts"
RESULTS = ROOT / ".local" / "benchmark-results.json"
DEFAULT_SIZES = (1_000, 10_000, 100_000)
DEFAULT_INPUT_LIMIT = 32 * 1024 * 1024
WORKLOAD_VERSION = "flat-directed-five-edges-v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def generate_workload(nodes: int) -> dict:
    """Generate original compact data without changing library resource limits."""
    path = ARTIFACTS / f"nodes-{nodes}-edges-{nodes * 5}.graphml"
    # IDs and values are generated ASCII integers, not interpolated user input.
    with path.open("wb") as stream:
        stream.write(b'<graphml xmlns="http://graphml.graphdrawing.org/xmlns">'
                     b'<graph id="benchmark" edgedefault="directed">')
        for node in range(nodes):
            stream.write(f'<node id="n{node}"/>'.encode("ascii"))
        for node in range(nodes):
            # A self-loop, two identical endpoint pairs, and two distinct spans.
            targets = (node, (node + 1) % nodes, (node + 1) % nodes,
                       (node + 97) % nodes, (node * 17 + 31) % nodes)
            for target in targets:
                stream.write(f'<edge source="n{node}" target="n{target}"/>'.encode("ascii"))
        stream.write(b"</graph></graphml>")
    size = path.stat().st_size
    if size > DEFAULT_INPUT_LIMIT:
        raise RuntimeError(f"generated {size} bytes exceed the unchanged 32 MiB input limit: {path}")
    return {
        "nodes": nodes,
        "edges": nodes * 5,
        "input_path": str(path.relative_to(ROOT)),
        "input_bytes": size,
        "input_sha256": sha256_file(path),
        "runs": [],
    }


class MemoryMonitor:
    """Best-effort child memory sampler; missing measurements are never zero."""

    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.handle = None
        self.peak_bytes = None
        self.samples = 0
        self.errors = []
        self.method = "unavailable"
        self.is_lower_bound = True
        self.psapi = None
        self.kernel32 = None
        if sys.platform == "win32":
            try:
                self.kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
                self.psapi = ctypes.WinDLL("psapi", use_last_error=True)
                self.kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
                self.kernel32.OpenProcess.restype = wintypes.HANDLE
                self.kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
                self.kernel32.CloseHandle.restype = wintypes.BOOL
                self.psapi.GetProcessMemoryInfo.argtypes = (wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD)
                self.psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
                self.handle = self.kernel32.OpenProcess(0x0400 | 0x0010, False, pid)
                if not self.handle:
                    self.handle = self.kernel32.OpenProcess(0x1000 | 0x0010, False, pid)
                if not self.handle:
                    raise ctypes.WinError(ctypes.get_last_error())
                self.method = "Windows GetProcessMemoryInfo PeakWorkingSetSize"
                # The OS counter records peaks between samples; holding a handle
                # allows a final counter query after the child has exited.
                self.is_lower_bound = False
            except (OSError, AttributeError) as error:
                self.errors.append(str(error))
        elif sys.platform.startswith("linux"):
            self.method = "Linux /proc/<pid>/status VmHWM sampled while alive"
            # The process might reach a final peak just before /proc disappears.
            self.is_lower_bound = True
        else:
            self.errors.append(f"no standard-library RSS sampler for {sys.platform}")

    def sample(self) -> None:
        value = None
        if self.handle and self.psapi:
            class Counters(ctypes.Structure):
                _fields_ = [
                    ("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                ]
            counters = Counters()
            counters.cb = ctypes.sizeof(counters)
            if self.psapi.GetProcessMemoryInfo(self.handle, ctypes.byref(counters), counters.cb):
                value = int(counters.PeakWorkingSetSize)
            else:
                message = str(ctypes.WinError(ctypes.get_last_error()))
                if message not in self.errors:
                    self.errors.append(message)
                # If the final query fails, an observed running counter remains
                # useful but cannot establish the exact lifetime high-water mark.
                self.is_lower_bound = True
        elif sys.platform.startswith("linux"):
            try:
                status = Path(f"/proc/{self.pid}/status").read_text(encoding="ascii")
                match = re.search(r"^VmHWM:\s*(\d+)\s+kB\s*$", status, re.MULTILINE)
                if match:
                    value = int(match.group(1)) * 1024
            except FileNotFoundError:
                pass  # Normal process-exit race, explicitly covered by lower-bound semantics.
            except OSError as error:
                message = str(error)
                if message not in self.errors:
                    self.errors.append(message)
        if value is not None:
            self.peak_bytes = max(self.peak_bytes or 0, value)
            self.samples += 1

    def close(self) -> None:
        if self.handle and self.kernel32:
            self.kernel32.CloseHandle(self.handle)
            self.handle = None

    def result(self) -> dict:
        return {
            "peak_resident_bytes": self.peak_bytes,
            "method": self.method,
            "sample_count": self.samples,
            "is_lower_bound": self.is_lower_bound,
            "errors": self.errors,
        }


def physical_memory_bytes() -> tuple[int | None, str]:
    if sys.platform == "win32":
        class Status(ctypes.Structure):
            _fields_ = [
                ("dwLength", wintypes.DWORD), ("dwMemoryLoad", wintypes.DWORD),
                ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]
        try:
            kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel.GlobalMemoryStatusEx.argtypes = (ctypes.c_void_p,)
            kernel.GlobalMemoryStatusEx.restype = wintypes.BOOL
            status = Status()
            status.dwLength = ctypes.sizeof(status)
            if not kernel.GlobalMemoryStatusEx(ctypes.byref(status)):
                raise ctypes.WinError(ctypes.get_last_error())
            return int(status.ullTotalPhys), "Windows GlobalMemoryStatusEx"
        except (OSError, AttributeError) as error:
            return None, str(error)
    try:
        pages = os.sysconf("SC_PHYS_PAGES")
        page_size = os.sysconf("SC_PAGE_SIZE")
        return pages * page_size, "os.sysconf physical pages"
    except (ValueError, OSError, AttributeError) as error:
        return None, str(error)


def cpu_description() -> str:
    if sys.platform == "win32":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
                return str(winreg.QueryValueEx(key, "ProcessorNameString")[0]).strip()
        except OSError:
            return os.environ.get("PROCESSOR_IDENTIFIER", platform.processor()) or "unavailable"
    if sys.platform.startswith("linux"):
        try:
            cpuinfo = Path("/proc/cpuinfo").read_text(encoding="utf-8")
            match = re.search(r"^model name\s*:\s*(.+)$", cpuinfo, re.MULTILINE)
            if match:
                return match.group(1).strip()
        except OSError:
            pass
    return platform.processor() or "unavailable"


def command_details(command: list[str]) -> dict:
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=30)
        return {"command": command, "returncode": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr}
    except (OSError, subprocess.SubprocessError) as error:
        return {"command": command, "error": str(error)}


def drain_pipe(pipe, chunks: list[bytes], errors: list[str]) -> None:
    try:
        while True:
            chunk = pipe.read(64 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
    except OSError as error:
        errors.append(str(error))
    finally:
        pipe.close()


def run_inspect(executable: Path, workload: dict, repeat: int, timeout: float,
                poll_interval: float) -> dict:
    path = ROOT / workload["input_path"]
    command = [str(executable), "inspect", str(path)]
    stdout_chunks: list[bytes] = []
    stderr_chunks: list[bytes] = []
    pipe_errors: list[str] = []
    started = time.perf_counter()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    monitor = MemoryMonitor(process.pid)
    readers = [
        threading.Thread(target=drain_pipe, args=(process.stdout, stdout_chunks, pipe_errors), daemon=True),
        threading.Thread(target=drain_pipe, args=(process.stderr, stderr_chunks, pipe_errors), daemon=True),
    ]
    for reader in readers:
        reader.start()
    timed_out = False
    try:
        while process.poll() is None:
            monitor.sample()
            elapsed = time.perf_counter() - started
            if elapsed >= timeout:
                timed_out = True
                process.kill()
                break
            time.sleep(min(poll_interval, max(0.0, timeout - elapsed)))
        process.wait()
        elapsed = time.perf_counter() - started
        monitor.sample()
    finally:
        # Exception paths must not leave a benchmark child alive or a full pipe
        # blocking process completion. All captured failure output is retained.
        if process.poll() is None:
            process.kill()
            process.wait()
        monitor.close()
        for reader in readers:
            reader.join(timeout=5)
        if any(reader.is_alive() for reader in readers):
            raise RuntimeError(f"pipe reader did not finish for {command}")
    stdout = b"".join(stdout_chunks).decode("utf-8", errors="replace")
    stderr = b"".join(stderr_chunks).decode("utf-8", errors="replace")
    output_path = ARTIFACTS / f"nodes-{workload['nodes']}-run-{repeat}.json"
    output = {"command": command, "returncode": process.returncode,
              "timed_out": timed_out, "stdout": stdout, "stderr": stderr,
              "pipe_errors": pipe_errors}
    output_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    if timed_out or process.returncode != 0 or pipe_errors:
        raise RuntimeError(f"benchmark child failed: {json.dumps(output, ensure_ascii=False)}")
    match = re.search(r"^graphs=(\d+) nodes=(\d+) edges=(\d+) hyperedges=(\d+) ports=(\d+) endpoints=(\d+)\s*$",
                      stdout, re.MULTILINE)
    expected = (1, workload["nodes"], workload["edges"], 0, 0, 0)
    actual = tuple(map(int, match.groups())) if match else None
    if actual != expected:
        raise AssertionError(f"wrong stored counts: expected {expected}, got {actual}; output={output}")
    if not re.search(r"^mixed=false parallel=true loops=true locators=false xml_payloads=false\s*$",
                     stdout, re.MULTILINE):
        raise AssertionError(f"workload structural flags missing or wrong; output={output}")
    return {
        "repeat": repeat,
        "elapsed_seconds": elapsed,
        "throughput_megabytes_per_second": workload["input_bytes"] / 1_000_000 / elapsed,
        "stored_counts": {"graphs": actual[0], "nodes": actual[1], "edges": actual[2]},
        "child_output_path": str(output_path.relative_to(ROOT)),
        "memory": monitor.result(),
    }


def main() -> int:
    default_binary = ROOT / "_build/native/release/build/cmd/graphml" / (
        "graphml.exe" if sys.platform == "win32" else "graphml")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=default_binary)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("--poll-ms", type=float, default=5.0)
    parser.add_argument("--smoke", action="store_true", help="only 1,000 nodes; explicitly incomplete smoke results")
    options = parser.parse_args()
    if options.repeats < 3:
        parser.error("at least three fresh-process repeats are required")
    if options.timeout <= 0 or options.poll_ms <= 0:
        parser.error("timeout and poll interval must be positive")
    executable = options.exe.resolve()
    if not executable.is_file():
        parser.error(f"native executable does not exist: {executable}; build release first")
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    ram, ram_method = physical_memory_bytes()
    moon = shutil.which("moon")
    report = {
        "status": "running",
        "recorded_utc": datetime.now(timezone.utc).isoformat(),
        "workload_version": WORKLOAD_VERSION,
        "requested_sizes": list(DEFAULT_SIZES[:1] if options.smoke else DEFAULT_SIZES),
        "full_target_workload": not options.smoke,
        "repeats": options.repeats,
        "timeout_seconds": options.timeout,
        "memory_poll_interval_ms": options.poll_ms,
        "measurement_scope": "native inspect process wall time: startup, file read/decode, parse/validate, statistics, shutdown",
        "throughput_unit": "decimal megabytes (1,000,000 input bytes) per second",
        "timing_note": "includes sampler/poll scheduling overhead; fresh processes, OS file cache not flushed",
        "memory_note": "child working set/RSS, not total allocated heap; Linux sampled VmHWM is a lower bound",
        "hardware": {
            "os": platform.platform(), "system": platform.system(), "release": platform.release(),
            "architecture": platform.machine(), "cpu": cpu_description(), "logical_cpu_count": os.cpu_count(),
            "physical_memory_bytes": ram, "physical_memory_source": ram_method,
            "python": sys.version, "python_executable": sys.executable,
        },
        "executable": {"path": str(executable), "bytes": executable.stat().st_size,
                       "sha256": sha256_file(executable)},
        "toolchain": command_details([moon, "version", "--all"]) if moon else {"error": "moon not found on PATH"},
        "workloads": [],
        "comparison": "no performance claim against reference libraries",
    }

    def save_report() -> None:
        RESULTS.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    save_report()
    try:
        for nodes in report["requested_sizes"]:
            workload = generate_workload(nodes)
            report["workloads"].append(workload)
            print(f"input nodes={nodes} edges={nodes * 5} bytes={workload['input_bytes']} sha256={workload['input_sha256']}", flush=True)
            for repeat in range(1, options.repeats + 1):
                run = run_inspect(executable, workload, repeat, options.timeout, options.poll_ms / 1000.0)
                workload["runs"].append(run)
                save_report()
                memory = run["memory"]["peak_resident_bytes"]
                print(f"nodes={nodes} run={repeat}/{options.repeats} seconds={run['elapsed_seconds']:.6f} "
                      f"MB/s={run['throughput_megabytes_per_second']:.3f} peak_bytes={memory}", flush=True)
            times = [run["elapsed_seconds"] for run in workload["runs"]]
            throughputs = [run["throughput_megabytes_per_second"] for run in workload["runs"]]
            peaks = [run["memory"]["peak_resident_bytes"] for run in workload["runs"]
                     if run["memory"]["peak_resident_bytes"] is not None]
            workload["summary"] = {
                "seconds_min": min(times), "seconds_median": statistics.median(times), "seconds_max": max(times),
                "megabytes_per_second_median": statistics.median(throughputs),
                "peak_resident_bytes_max": max(peaks) if peaks else None,
                "memory_runs_measured": len(peaks),
                "all_counts_asserted": True,
            }
            save_report()
        report["status"] = "passed_smoke_only" if options.smoke else "passed"
        report["completed_utc"] = datetime.now(timezone.utc).isoformat()
        save_report()
        print(f"{report['status']}: {RESULTS}", flush=True)
        return 0
    except Exception as error:
        report["status"] = "failed"
        report["failure"] = {"type": type(error).__name__, "message": str(error), "traceback": traceback.format_exc()}
        report["completed_utc"] = datetime.now(timezone.utc).isoformat()
        save_report()
        traceback.print_exc()
        print(f"failed: complete diagnostics are in {RESULTS}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
