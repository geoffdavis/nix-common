# modules/iodd.nix — tooling for driving IODD virtual-drive USB enclosures
# (iodd ST400 et al.) from Linux, shared by birdrock and the NAS fleet.
#
# The IODD firmware mounts VHD/ISO image files that live on its internal disk,
# but it reads each file's extent map through a small fixed-size fragment
# table: a badly fragmented image is rejected ("fragmented") even for ISOs.
# exFAT has no defragmenter on Linux/macOS, so it spirals; NTFS (kernel ntfs3)
# gives full read/write plus sparse files and is the format we standardise on.
#
# This module provides:
#   - the ntfs3 kernel driver (native NTFS read/write, no ntfs-3g FUSE),
#   - mkfs/label tooling for NTFS *and* exFAT (format the stick on Linux),
#   - `progress` (coreutils-viewer) for ^T-style live progress on cp/dd/mv,
#   - `iodd-cp`, which copies existing image files onto the stick as single,
#     contiguous extents so the IODD's fragment table stays happy,
#   - `iodd-mkvhd`, which creates a blank fixed VHD the IODD accepts, fully
#     allocated (contiguous on a clean volume) rather than sparse.
# PROMOTED from nix-personal (#124), where it was imported by four
# configs; fully generic (no host or fleet identifiers). Gained the enable
# gate on promotion — it was import-is-apply before, which this repo's
# contract forbids for feature modules.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.iodd;

  iodd-cp = pkgs.writeShellApplication {
    name = "iodd-cp";
    runtimeInputs = with pkgs; [coreutils util-linux e2fsprogs];
    text = ''
      # iodd-cp SRC [SRC...] DESTDIR
      #
      # Copy each SRC into DESTDIR as one contiguous file: preallocate the
      # destination to the exact source size with fallocate (a single run on a
      # freshly-formatted volume), then stream the bytes in with `dd
      # conv=notrunc`, which overwrites in place and never reallocates. Prints
      # the final extent count so you can confirm the IODD will accept it.
      if [ "$#" -lt 2 ]; then
        echo "usage: iodd-cp SRC [SRC...] DESTDIR" >&2
        exit 2
      fi
      dest="''${!#}" # last positional arg = destination directory
      if [ ! -d "$dest" ]; then
        echo "iodd-cp: destination '$dest' is not a directory" >&2
        exit 2
      fi
      srcs=("''${@:1:$(($# - 1))}") # everything but the last arg
      rc=0
      for src in "''${srcs[@]}"; do
        if [ ! -f "$src" ]; then
          echo "iodd-cp: '$src' is not a regular file, skipping" >&2
          rc=1
          continue
        fi
        size=$(stat -c%s "$src")
        target="$dest/$(basename "$src")"
        if [ "$src" -ef "$target" ]; then
          echo "iodd-cp: '$src' resolves into DESTDIR (source == destination)," \
            "skipping so we don't delete it" >&2
          rc=1
          continue
        fi
        echo "iodd-cp: $src -> $target ($(numfmt --to=iec "$size"))"
        rm -f "$target"
        if fallocate -l "$size" "$target" 2>/dev/null; then
          dd if="$src" of="$target" bs=16M conv=notrunc iflag=fullblock status=progress
        else
          echo "iodd-cp: WARNING fallocate unsupported here; plain copy, file may" \
            "fragment" >&2
          rm -f "$target"
          dd if="$src" of="$target" bs=16M iflag=fullblock status=progress
        fi
        sync "$target"
        # Best-effort contiguity report (some FS drivers lack FIEMAP).
        if frag=$(filefrag "$target" 2>/dev/null); then
          echo "iodd-cp: ''${frag#"$target": }"
        fi
      done
      exit "$rc"
    '';
  };

  iodd-mkvhd = pkgs.writeShellApplication {
    name = "iodd-mkvhd";
    runtimeInputs = with pkgs; [qemu-utils coreutils util-linux e2fsprogs gnugrep];
    text = ''
      # iodd-mkvhd SIZE DEST.vhd   (e.g. iodd-mkvhd 100G /mnt/iodd/_ISO/win.vhd)
      #
      # Create a *fixed* VHD (the only writable geometry the IODD mounts),
      # sized exactly (force_size, no CHS rounding), then fully allocate it in
      # place. qemu-img's fixed VHD is sparse — preallocation= is a no-op for
      # the vpc format — so a plain create fragments on first write. A mode-0
      # fallocate over the whole file fills every hole with real zeroed extents
      # while leaving the trailing 512-byte footer (which the IODD reads for
      # geometry) untouched. On a freshly-formatted volume with contiguous free
      # space that lands as one extent.
      if [ "$#" -ne 2 ]; then
        echo "usage: iodd-mkvhd SIZE DEST.vhd   (e.g. iodd-mkvhd 100G /mnt/iodd/_ISO/win.vhd)" >&2
        exit 2
      fi
      size=$1
      dest=$2
      if [ -e "$dest" ]; then
        echo "iodd-mkvhd: '$dest' already exists, refusing to overwrite" >&2
        exit 1
      fi
      qemu-img create -f vpc -o subformat=fixed,force_size=on "$dest" "$size"
      # File is (virtual size + 512-byte footer); stat gives that exact total.
      # If fallocate can't preallocate (FS without support, or full disk) the
      # VHD would be left sparse and fragment on first write — remove it and
      # fail loudly rather than hand back a deceptively-usable file.
      if ! fallocate -l "$(stat -c%s "$dest")" "$dest"; then
        echo "iodd-mkvhd: fallocate failed on '$dest' — the target filesystem may" \
          "not support preallocation, or the volume is full. Removing the partial" \
          "file; format the volume NTFS (ntfs3) with free space and retry." >&2
        rm -f "$dest"
        exit 1
      fi
      sync "$dest"
      # Confirm contiguity; warn loudly if the volume was too fragmented.
      if frag=$(filefrag "$dest" 2>/dev/null); then
        echo "iodd-mkvhd: ''${frag#"$dest": }"
        extents=$(printf '%s' "$frag" | grep -oE '[0-9]+ extents? found' | grep -oE '^[0-9]+' || true)
        if [ -n "''${extents:-}" ] && [ "$extents" -gt 1 ]; then
          echo "iodd-mkvhd: WARNING $extents extents — the IODD may reject this as" \
            "fragmented; reformat the volume and retry before loading files." >&2
        fi
      fi
    '';
  };
in {
  options.my.iodd.enable =
    lib.mkEnableOption "IODD virtual-drive USB tooling (ntfs3, mkfs/label helpers, iodd-cp/iodd-mkvhd)";

  config = lib.mkIf cfg.enable {
    # Native NTFS read/write via the in-kernel ntfs3 driver (not the ntfs-3g
    # FUSE fallback). Also lets stage-1 mount NTFS, which is harmless here.
    boot.supportedFilesystems.ntfs = true;

    environment.systemPackages = with pkgs; [
      ntfs3g # mkfs.ntfs / ntfslabel / ntfsfix — format + label the stick
      exfatprogs # mkfs.exfat / exfatlabel — keep exFAT tooling too
      progress # coreutils-viewer: live progress for a running cp/dd/mv/ISO
      iodd-cp
      iodd-mkvhd
    ];
  };
}
