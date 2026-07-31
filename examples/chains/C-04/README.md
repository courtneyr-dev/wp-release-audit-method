# C-04: plugin activation scope x dependency resolution x UI and REST affordance

Fixtures:

- `codex-dependency/codex-dependency.php`
- `codex-dependent/codex-dependent.php`, with `Requires Plugins:
  codex-dependency`
- network super administrator ID 1
- subsite administrator ID 2 on `codex-active.localhost`

The runner serializes three dependency states. It restores the original network
and site activation options with a trap. Each state probes the network and site
activation screens for both viewers.

Run:

```bash
bash run.sh
```

The known positive control is the network-active dependency cell. The site-active
dependency on the active subsite is the negative control.

