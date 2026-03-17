# FSx Windows volume window updater

`fsx-windows-volume-config.bat` reads current backup and maintenance windows
for FSx for Windows file systems and can update them in place.

## Requirements

- Windows (batch script).
- AWS CLI v2 on `PATH`.
- Credentials configured via `AWS_PROFILE` or `~/.aws/credentials`.

## Usage

```bat
fsx-windows-volume-config.bat -id <fsx-id> [options]
fsx-windows-volume-config.bat -file <path> [options]
```

Exactly one of `-id` or `-file` is required.

## Options

- `-backup <HH:MM>`: daily backup start time (UTC).
- `-backup-plushours <H>`: offset backup by `+H` hours (UTC, 0-12).
- `-backup-minushours <H>`: offset backup by `-H` hours (UTC, 0-12).
- `-maintenance <d:HH:MM>`: weekly maintenance (UTC), `d=1-7` where
  `1=Mon ... 7=Sun`. `HH` must be `00-23` and `MM` must be `00-60`.
- `-maintenance-plushours <H>`: offset maintenance by `+H` hours (UTC, 0-12).
- `-maintenance-minushours <H>`: offset maintenance by `-H` hours (UTC, 0-12).
- `-region <region>`: AWS region (or `AWS_REGION` env var).
- `-profile <profile>`: AWS profile (or `AWS_PROFILE` env var).
- `-help` or `/?`: show help.

If you supply both an explicit time and an offset for the same window, the
offset takes precedence.

## Input file format

When using `-file`, provide one FSx file system ID per line. Blank lines and
lines starting with `#` or `;` are ignored.

Example (`example-myvols.txt`):

```text
fs-04fdc9276c6b9736f
fs-071f4f04a1e98f271
fs-01eb6ca0ba8c54e44
fs-08890d66e7b60e56a
```

## Examples

```bat
fsx-windows-volume-config.bat -id fs-1234567890abcdef0
fsx-windows-volume-config.bat -file example-myvols.txt -backup-plushours 2
fsx-windows-volume-config.bat -id fs-1234567890abcdef0 -maintenance 7:05:00
fsx-windows-volume-config.bat -id fs-1234567890abcdef0 -maintenance-minushours 1
```

## Notes

- Times are in UTC.
- The script prints current windows before applying any update.
