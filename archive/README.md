# Archived configuration

Files in this directory are retained for reference. They are not installed by the
current catalogue, and the archived scripts are not supported setup procedures.
Archiving does not remove software or personal configuration already installed.

To inspect a moved file's history after the move is committed:

```sh
git log --follow -- archive/os/install_r.sh
git blame -M -C -- archive/os/install_r.sh
```

Replace the example path with the archived file you want to inspect. References
inside archived files may point to the old directory layout.
