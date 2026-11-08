# Contributing to Auto Backup

Thanks for helping make backups easier to understand and verify. Contributions of all sizes and experience levels are welcome, including documentation, bug reports, UI feedback, tests, and code.

## Ways to help

- Report a bug with steps we can reproduce using sample files.
- Suggest a feature and explain the backup problem it solves.
- Improve documentation, labels, keyboard navigation, or VoiceOver behavior.
- Test on Apple silicon or Intel Macs, different macOS versions, and APFS, exFAT, or other destination filesystems.
- Improve performance, cancellation, recovery, and verification without weakening file safety.

Browse [open issues](https://github.com/Krissams/auto-backup/issues), or open one to discuss your idea. For your first contribution, a small documentation fix or a focused regression test is a useful starting point. Ask in an issue if you would like help choosing a task.

## Local setup

Use macOS 13 or later with Xcode or Command Line Tools and Swift 5.7 or later. No third-party dependencies are required.

1. Fork the repository on GitHub.
2. Clone your fork and create a branch:

   ```sh
   git clone https://github.com/YOUR-USERNAME/auto-backup.git
   cd auto-backup
   git switch -c describe-your-change
   ```

3. Build and run:

   ```sh
   zsh scripts/build.sh
   open "build/Auto Backup.app"
   ```

The build creates a locally signed app for your Mac's architecture. The source deployment target is macOS 13. Build output stays under `build/` and is not committed.

## Making a change

- Keep a pull request focused on one problem and describe the resulting behavior.
- Follow nearby Swift conventions: four-space indentation, descriptive names, and small types and functions.
- Keep filesystem work off the main thread; publish UI state on the main actor.
- Use native Mac controls, accessible labels, keyboard support, and theme-aware colors. Review UI changes in light and dark appearances and at the minimum window size.
- Keep filename/extension/size matches distinct from content verification. A metadata match must never silently authorize skipping a copy as content-identical.
- Preserve the user's checked file selection when filtering or navigating. Never let automatic runs include files the user has not approved.
- Preserve staged writes, verification, conflict handling, and cancellation cleanup. Add meaningful regression coverage when changing these behaviors.
- Keep credentials, personal paths, real backup files, build artifacts, and local preferences out of commits. Use synthetic files and screenshots for examples.

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for the main components.

## Validate

Run these before opening a pull request:

```sh
zsh scripts/test.sh
zsh scripts/build.sh
codesign --verify --deep --strict "build/Auto Backup.app"
```

The test scripts create and remove their own temporary fixtures. Use a separate disposable source and destination for any manual file-operation testing.

For UI or documentation changes, optionally render the example screens:

```sh
zsh scripts/preview.sh
```

Include relevant screenshots or an explanation of the changed interaction. Explain what you tested and any checks you could not run. CI performs the automated tests, build, and bundle verification on macOS.

## Open a pull request

Push your branch to your fork and open a pull request against `main`. Use the template to describe the problem, your change, and validation. Link an issue when relevant; large changes benefit from an issue discussion first. Maintainers may suggest changes before merging.

By submitting a contribution, you agree to make it available under the project's [MIT license](LICENSE). No separate contributor agreement is required. Please follow the [community guidelines](CODE_OF_CONDUCT.md).
