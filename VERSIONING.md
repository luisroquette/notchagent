# Versioning policy

NotchAgent is the **desktop software product**. It follows
[Semantic Versioning 2.0.0](https://semver.org/) using `MAJOR.MINOR.PATCH`.

- **MAJOR:** incompatible public model, persisted-data, provider contract, or
  supported-platform change requiring migration.
- **MINOR:** backward-compatible provider, screen, integration, or capability.
- **PATCH:** backward-compatible correctness, reliability, security, copy, or
  packaging fix.
- Prereleases use `-alpha.N`, `-beta.N`, or `-rc.N` and are never presented as stable.

Commits follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
`feat` implies MINOR, `fix` implies PATCH, and `BREAKING CHANGE:` implies MAJOR.
`CHANGELOG.md` remains human-curated using Added, Changed, Deprecated, Removed,
Fixed, and Security sections.

## Product boundary

- App tags: `vX.Y.Z` in this repository.
- Desk firmware/product tags: independent `vX.Y.Z` in
  [`notchagent-desk`](https://github.com/luisroquette/notchagent-desk).
- Desk wire compatibility is governed by that repository's protocol version and
  compatibility matrix, not by matching app and firmware numbers.
- Published tags and release artifacts are immutable.

## Release gates

1. `VERSION`, bundle metadata, changelog and tag agree.
2. Swift and affected integration tests pass with paid probes disabled.
3. Public-release audit reports no credentials or personal identifiers.
4. macOS artifacts are signed, notarized and stapled before stable distribution.
5. Platform support matches physical evidence; Windows remains Preview until
   its installer and hardware matrix are validated.
