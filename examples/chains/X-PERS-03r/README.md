# X-PERS-03r: KSES URL-value reparse

This runs the direct-parser gate and a lower-privilege full-content re-save. It
compares a pinned CSS corpus on the local WordPress 7.0.2 and 7.1-beta4
runtimes. The save probe creates a temporary author and draft, reparses the
admin-seeded content as that author, then deletes both records.

If the safe legacy corpus changes unexpectedly or either control fails, stop.
Only a calibrated direct-parser result can advance to the lower-privilege
post-save and REST-save matrix.

Run:

```bash
bash run.sh
```

The parser gate is read-only. The save-path leg verifies its own cleanup.
