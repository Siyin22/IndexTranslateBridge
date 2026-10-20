"""Start the local bridge in the background, with no changes to Windows startup."""
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.request

folder = Path(__file__).resolve().parent
runtime = folder.parent / "runtime"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def ready():
    try:
        with opener.open("http://127.0.0.1:8080/", timeout=1) as response:
            return response.read(100).strip() == b"Index-Translate Proxy Ready"
    except Exception:
        return False

if ready():
    print("Bridge already running: http://127.0.0.1:8080/v1")
    sys.exit(0)

with socket.socket() as probe:
    if probe.connect_ex(("127.0.0.1", 8080)) == 0:
        print("Port 8080 is used by another program. No changes made.")
        sys.exit(1)

runtime.mkdir(exist_ok=True)
with (runtime / "bridge.log").open("ab", buffering=0) as log:
    child = subprocess.Popen(
        [sys.executable, "-I", "-B", "-u", str(folder / "run_bridge.py")],
        cwd=folder, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    (runtime / "bridge.pid").write_text(str(child.pid), encoding="ascii")

for _ in range(30):
    if ready():
        print("Bridge started. You may close this window.")
        print("Base URL: http://127.0.0.1:8080/v1")
        print("API Key: index")
        print("Model: Index-Translate-35B-A3B")
        sys.exit(0)
    if child.poll() is not None:
        break
    time.sleep(0.2)
print("Could not start. See runtime/bridge.log in the project folder.")
sys.exit(1)
