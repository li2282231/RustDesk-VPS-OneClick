# Installer regression tests

Run from the repository root:

```bash
python3 -m unittest discover -s tests -v
```

Tests use temporary directories and require no root access. The real APT/POSIX lock tests run on Linux and are skipped on other systems. No host packages are installed or removed.
