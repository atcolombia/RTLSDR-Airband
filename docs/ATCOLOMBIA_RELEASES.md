# ATColombia release binaries

The workflow `.github/workflows/release_binaries.yml` builds portable
Raspberry Pi binaries of `rtl_airband` for the ATColombia receiver fleet and
publishes them as assets of a GitHub Release.

## Cutting a release

1. Merge the changes to `main`.
2. Tag the commit on `main` and push the tag:

   ```sh
   git checkout main && git pull
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. The tag push builds all targets, runs the unit tests and creates (or
   updates) the GitHub Release `vX.Y.Z` with the binaries, `SHA256SUMS` and
   `manifest.json`.

Pull requests that change the workflow (or `.github/release_build.sh`) and
manual `workflow_dispatch` runs are dry runs: they build and assemble the same
files as workflow artifacts (`release-files`) but publish nothing. Their
version is the `git describe --tags` output instead of a tag name.

## Build matrix

| Debian | Docker platform | Asset arch |
| --- | --- | --- |
| bullseye (11) | `linux/arm/v7` (armhf) | `linux-arm` |
| bullseye (11) | `linux/arm64` | `linux-arm64` |
| bookworm (12) | `linux/arm/v7` (armhf) | `linux-arm` |
| bookworm (12) | `linux/arm64` | `linux-arm64` |
| trixie (13) | `linux/arm/v7` (armhf) | `linux-arm` |
| trixie (13) | `linux/arm64` | `linux-arm64` |
| bullseye/bookworm/trixie | `linux/amd64` (x86_64 receivers) | `linux-amd64` |

Each target is built inside the matching `debian:<codename>` container on a
native `ubuntu-24.04-arm` runner, with the same CMake options as production:

```
-DCMAKE_BUILD_TYPE=Release -DPLATFORM=generic -DMIRISDR=OFF -DPULSEAUDIO=OFF
-DNFM=OFF -DSOAPYSDR=ON -DRTLSDR=ON -DBUILD_UNITTESTS=TRUE
```

`PLATFORM=generic` adds no `-march` flags, so the binaries run on Pi 3, 4
and 5. The binaries link dynamically against the Debian packages of the same
release (librtlsdr, libsoapysdr, libshout, libmp3lame, libconfig++, fftw3,
libcurl), so the receiver must run the matching Debian version.

## Artifact contract

The ATColombia receiver server's importer depends on this exactly.

- Binary: `rtl_airband-<tag>-debian<11|12|13>-<linux-arm|linux-arm64|linux-amd64>[-soapy]`.
  The plain build is RTL-SDR only (runs without libSoapySDR, like most
  receivers); `-soapy` also enables SoapySDR for Airspy receivers. Each
  manifest entry has `"flavor": "plain" | "soapy"`, for
  example `rtl_airband-v0.0.3-debian12-linux-arm64`. Stripped, mode 0755.
- `SHA256SUMS`: one `sha256sum` line per binary.
- `manifest.json`:

  ```json
  {
    "version": "<tag>",
    "commit": "<sha>",
    "builds": [
      {
        "file": "rtl_airband-v0.0.3-debian12-linux-arm64",
        "os": "debian-12",
        "arch": "linux-arm64",
        "sha256": "<hex>",
        "size_bytes": 123456,
        "version_output": "RTLSDR-Airband version v0.0.3",
        "ldd": "<ldd output>"
      }
    ]
  }
  ```

The build fails if `rtl_airband -v` does not contain the tag name, if any
unit test fails, or if `ldd` reports a missing library.

## Import into the receiver server

The ATColombia monorepo workflow `receiver-rtl-airband-import.yml` imports
the assets of a release into the receiver server, which relies on the
contract above.
