# C-03: multisite status flags x network upgrade x first load

This batch first runs the five-site denominator control. It then temporarily
restores the archived site, performs one local front-end request, reads its
`db_version`, and restores the archived flag. A trap restores the flag if the
test exits early.

The result can establish first-load behavior. It cannot establish functional
impact until a source-backed feature that requires the newer schema is named.

Run:

```bash
bash run.sh
```

