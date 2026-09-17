# Recipes

The scripts that actually produced the current models and scenes, kept because
they are the most honest documentation there is: every real run, in order, with
the flags that were used and a comment saying why.

They were written as one-offs in `pipeline/runs/` (which is gitignored), so
these are copies. Read them before copying; they hard-code `/home/marc` paths
and the us-east-2 bucket.

| Script | What it did |
|---|---|
| `sky3.sh` | A complete fresh data run for one segment: 144 briefs, teacher, verify, revise, combine with earlier runs on the same held-out briefs, retrain at 14336. **The best template for a new data run.** |
| `retrain_len14k.sh` | Retrain any segment on an existing dataset at `--max-len 14336` with Liger, then evaluate on the same held-out briefs as the old model and print the per-world split. Waits for a free training slot. |
| `dir1.sh` | Director training data: 400 scene briefs → Opus plans → the GPU-free director verifier → SFT rows. Runs without a GPU. |
| `scene_demos_v4.sh` | The eight published scenes, end to end, with the local 8B director and four local specialists. |
| `ground5_local.sh` | The same data run with a **local** teacher instead of Claude, using `--backend local:` and `--notes`. |

Long runs should be launched as user systemd units, not `nohup` — background
children die when the terminal session ends:

```bash
systemd-run --user --unit=scene-<name> --collect \
  --setenv=XAUTHORITY=/run/user/1000/gdm/Xauthority --setenv=HOME=$HOME --setenv=PATH=$PATH \
  -p StandardOutput=append:/absolute/path.log -p StandardError=append:/absolute/path.log \
  /absolute/path/to/script.sh
systemctl --user is-active scene-<name>
```

`StandardOutput=append:` needs an absolute path or the unit silently fails to
start, and never put a `pkill` pattern and the launch of the same script name
in one shell command — it matches its own command line and kills the session.
