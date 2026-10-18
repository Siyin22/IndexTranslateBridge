"""Run the official Bilibili bridge, connecting directly to its Chinese endpoint."""
import importlib.util
from pathlib import Path
import urllib.request

urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))
script = Path(__file__).with_name("call_api.py")
spec = importlib.util.spec_from_file_location("bilibili_official_bridge", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.run_proxy_server(port=8080, host="127.0.0.1")
