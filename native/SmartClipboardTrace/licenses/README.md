Dependency distributions normally provide the license text used by `verify-notices.py`.

Three locked packages omit it:

- `flo_curves` 0.3.1 declares Apache-2.0 in its published manifest. Its recorded source commit `fccd933942532562557be2a61a706ebc0a1f1888` also contains no LICENSE or NOTICE file. `Apache-2.0.txt` is the unmodified standard text downloaded from https://www.apache.org/licenses/LICENSE-2.0.txt.
- The two Windows GNU support packages at 0.4.0 declare MIT/Apache-2.0 and point to the winapi repository. Their license texts are copied unchanged from the locked parent `winapi` 0.3.9 package. These target-specific packages are included in the complete lockfile notices even though they are not part of the macOS helper.

The generated notices retain all supplied copyright and license text; they do not assign new copyright claims to dependencies.

`rust-1.94.0-library.html` is copied unchanged from the official Rust 1.94.0 macOS toolchain's `share/doc/rust/COPYRIGHT-library.html`. Its full text, including standard-library dependency licenses, is included in the generated app notice file.
