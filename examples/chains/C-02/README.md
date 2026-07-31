# C-02: upgrade path x file-removal ledger x clean-tree integrity

This batch compares local upgraded Studio trees with the verified beta4 clean
fixture. It also reruns the offline `$_old_files` detector controls.

The prior-beta Core-upgrader fixture must identify as beta4 before that cell can
run. A mismatched identity is a blocker, not a WordPress result.

Run:

```bash
bash run.sh
```

The test is read-only. `cleanup.sh` confirms that no cleanup is required.

