Screenshot harness: serve `docs/` on a local port, then

    python3 cdp_gpu.py http://127.0.0.1:8765/index.html 5,13,20 out

writes `out_<n>_<t>s.png` at the given seconds after page load and echoes the
browser console. `cdp_shots.py` is the same thing using SwiftShader software GL.
