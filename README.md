# Droidspaces RootFS Builder (x86_64 + aarch64 / Linux desktop)

Builds x86_64 and aarch64 (ARM64) rootfs tarballs for [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)
on a Linux desktop or server, from Dockerfiles. Every build is published as a GitHub release,
and `rootfs.json` is regenerated on every release.

This is a port of [Droidspaces/Droidspaces-rootfs-builder](https://github.com/Droidspaces/Droidspaces-rootfs-builder),
which targets Android phones (mostly aarch64). The build engine, CI and label scheme are the same.
The templates are not.

## What changed from the Android templates

Removed, because a desktop does not need them:

- Android network groups (`aid_inet`, `aid_net_raw`, `aid_net_admin`). They only matter on Android
  kernels with paranoid networking.
- The forced `iptables-legacy` switch. Desktop images keep each distro's default backend.
- QEMU binfmt (`qemu-user-static`). It exists to run x86 programs on an ARM phone.
- `download-firmware` and `install-mesa`. The first decompresses firmware for Android kernels, the
  second installs a Mesa build for Adreno GPUs.
- The XFCE autostart unit and the `xfwm4` Turnip workaround. Both are wired to Termux:X11.

Kept, because they are about running in a container and not about Android:

- The systemd/udev/journald overrides, and the unit overrides that keep network daemons out of
  `host` and `none` network modes (they read `/run/droidspaces/container.config`).
- The OpenRC and `dhcpcd` setup on Alpine.
- The `/etc/droidspaces` marker file.

Changed:

- The XFCE images install Mesa from the distro (`libgl1-mesa-dri`, `mesa-vulkan-drivers` and
  friends), so the host GPU works through `--gpu` or `--hw-access`.
- New users get the `input`, `video` and `tty` groups.

## Templates

| Distro | Templates |
| --- | --- |
| Alpine 3.23 | Minimal, base |
| Arch Linux | Minimal, base |
| Azure Linux 3.0 | Minimal |
| Debian 13 | Minimal, base, XFCE |
| Kali Linux | Minimal, XFCE |
| Ubuntu 22.04 | Minimal, base |
| Ubuntu 24.04 | Minimal, base, XFCE |

Not ported yet: Artix (the Android build bootstraps from an ARM-only tarball), OpenWrt (it is
built around Android's lack of nftables and needs a different firewall setup on a desktop), and the
bspwm images (they depend on Termux:X11).

## Using a rootfs

Download an archive from the releases page (`.tar.xz` by default, or `.tar.gz` / `.tar.zst` if
the release was built with another format), then extract it as root. Without `sudo` the files are
not owned by root and setuid bits are lost. Pick the file that matches your CPU: `x86_64` for
Intel/AMD, `aarch64` for ARM64 (Raspberry Pi, ARM servers, Apple Silicon VMs).

```
mkdir ubuntu
sudo tar -xf Ubuntu-24.04-Minimal-Droidspaces-rootfs-x86_64-*.tar.* -C ubuntu
sudo droidspaces --name=ubuntu --rootfs=$PWD/ubuntu start
sudo droidspaces --name=ubuntu enter
```

`tar` detects `.xz` and `.gz` by itself. `.zst` needs the `zstd` package installed.

See the [Linux installation guide](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Installation-Linux.md)
for ext4 images and the daemon.

### Graphical programs

On Linux the container uses the host GPU through Mesa, with no bridge. Start it with `--gpu` (render
nodes only) or `--hw-access`, run `xhost +local:` on the host, add `--x11`, and set `DISPLAY` to the
host's display. The details are in the Linux section of
[Display, audio and desktop](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Graphics-and-Audio.md).

The XFCE images ship the desktop packages but do not start a session on their own.

## About `rootfs.json`

Only the Droidspaces Android app reads it (Manage Repositories can subscribe to any feed that
publishes one). The desktop CLI takes a rootfs directory or image directly, so the release
tarballs are what you use there.

## Adding a distro

Create `templates/<arch>/<Name>.Dockerfile` for every architecture you want (`x86_64`, `aarch64`).
That is the whole change. It must end with an `export` stage that carries the metadata labels:

```
FROM scratch AS export
LABEL droidspaces.name="Ubuntu 24.04 LTS - Minimal" \
      droidspaces.distro="Ubuntu" \
      droidspaces.description="Minimal Ubuntu 24.04 rootfs with basic packages." \
      droidspaces.author="Your name"
COPY --from=customizer / /
```

`name`, `distro` and `description` are required. Check them with:

```
python3 scripts/generate_rootfs_json.py --lint
```

## Architectures

`archs.json` maps each architecture to a Docker platform and a GitHub runner:

| Architecture | Platform      | Runner             |
|--------------|---------------|--------------------|
| x86_64       | `linux/amd64` | `ubuntu-latest`    |
| aarch64      | `linux/arm64` | `ubuntu-24.04-arm` |

aarch64 is built natively on GitHub's arm64 runner, not under QEMU emulation, which is faster and
avoids emulation bugs in `systemd` and `apt` postinst scripts. Those runners are free for public
repositories only.

`templates/aarch64/` is a copy of `templates/x86_64/`. Almost every base image is multi-arch and every
package exists on arm64, so the files are identical except for three Ubuntu templates
(`Ubuntu-22.04-base`, `Ubuntu-24.04-base`, `Ubuntu-24.04-XFCE`). There `fastfetch` and `firefox-esr`
come from PPAs that may not publish arm64 builds, so they are installed in their own layer and
skipped with a `WARNING:` line in the build log if missing, instead of failing the whole build.
After changing an x86_64 template, apply the same change to the aarch64 copy. This shows what differs:

```
diff -ru templates/x86_64 templates/aarch64
```

## Building locally

```
./build.sh -i Ubuntu-24.04-Minimal
./build.sh -a aarch64 -i Debian-13-Minimal -f zst
```

`-a` picks the architecture (default `x86_64`) and `-f` the archive format: `xz` (default), `gz` or
`zst`. Needs docker with buildx and `jq`, plus `xz`, `gzip` or `zstd` for the chosen format. On a host
of the other architecture the script installs QEMU for you, but that build is slow. The output is
`<Name>-Droidspaces-rootfs-<arch>-<date>-<version>.<format>`.

## CI

`.github/workflows/build-rootfs-releases.yml` runs by hand only (Actions tab, Run workflow). The
form asks for:

- **architectures**: `all` (default), `x86_64` or `aarch64`.
- **rootfs_format**: `tar.xz` (default), `tar.gz` or `tar.zst`.
- **update_json_only**: only regenerate `rootfs.json` from the latest release.

It lints the labels, builds every selected template in parallel, creates one release with all
tarballs in the chosen format, then regenerates and commits `rootfs.json`.

A single failed build blocks the whole release. A release made for one architecture replaces the
latest release, so `rootfs.json` then lists only that architecture until the next `all` build.
Use that to test a new architecture, and finish with an `all` build.

`cleanup-old-assets.yml` runs weekly and deletes releases, tags and workflow runs older than seven
days. The latest release is kept. Both scripts that talk to GitHub read `GITHUB_REPOSITORY` and
refuse to run without it, so they can never act on a repository you did not mean.

After pushing the repo to GitHub, enable Actions and start the first build from the Actions tab
(Run workflow).
