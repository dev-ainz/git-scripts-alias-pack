# Contributing

## Development Rules

- Keep scripts POSIX-compatible (`sh`).
- Keep logic simple and predictable.
- Use clear error messages.
- Keep comments short and objective.

## Local Validation

Run syntax checks before opening a PR:

```bash
bash -n aliases/pn.sh
bash -n aliases/rb.sh
bash -n aliases/bpd.sh
bash -n scripts/install.sh
bash -n scripts/uninstall.sh
```

## Documentation

When changing behavior:

- update `README.md`
- update examples/flags if needed
- include migration notes for alias changes
