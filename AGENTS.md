# AGENTS

When making code changes in this repository:

1. Update documentation when public behavior or public API changes.
2. Run `./run_tests.sh` after changes.
3. Do not consider the task complete if tests fail.
4. If the change affects performance-sensitive paths in `src/wjson.lua`,
   consider running `bench/bench.lua` or the benchmark scripts as a follow-up.
5. Keep diffs small and favor readability unless a benchmark justifies added
   complexity.

## Release administration

When the user asks to release or publish a new version, complete the whole
release rather than stopping after changing the version:

1. Check `jj status` and preserve unrelated work. Choose the next LuaRocks
   version and matching GitHub tag (`v${VERSION}`). Update the rockspec
   filename, its `version`, `source.tag`, and `Makefile`'s `ROCKSPEC`. Update
   release notes or the changelog when one exists. Do not reuse a published
   version or move an existing tag.
2. Run `./run_tests.sh` and `make lint` before committing. Build release assets
   only after the matching tag exists, because the new rockspec's `source.tag`
   must resolve. Confirm `gh auth status` before remote admin.
3. Describe the release with Jujutsu, move `main` to it, and push `main` to
   `origin` with `jj git push --bookmark main`. Wait for the main CI workflow to
   pass before tagging.
4. Create the local tag with `jj tag set "v${VERSION}" -r main`. Create the
   corresponding remote GitHub tag at the exact `main` commit using `gh api`:

   ```sh
   TAG="v${VERSION}"
   COMMIT="$(gh api repos/winterstream/wjson/commits/main --jq .sha)"
   gh api --method POST repos/winterstream/wjson/git/refs \
     -f ref="refs/tags/${TAG}" -f sha="${COMMIT}"
   ```

   Check for an existing tag first and stop unless it already points to the
   exact same commit; never move a published tag.

5. Run `make release-assets`, verify `dist/SHA256SUMS` with
   `(cd dist && sha256sum -c SHA256SUMS)`, and smoke-test the source rock with
   `luarocks install --tree /tmp/wjson-rock-test dist/wjson-${VERSION}.src.rock`.
6. The `v*` tag triggers `.github/workflows/release.yml`, which publishes
   `wjson.lua`, the source rock, and `SHA256SUMS` as a GitHub release. Watch the
   workflow with `gh run watch`, then verify the release and downloaded
   checksums with `gh release view` and `gh release download`.
7. Upload the matching rockspec and source rock to LuaRocks with
   `./luarocks.sh upload`, then verify the exact version appears in
   `./luarocks.sh search wjson --porcelain`. Never use `--force` except to
   correct an explicitly confirmed upload mistake.

Do not commit API keys or other credentials. Report the release URLs, commit,
tag, CI result, and artifact verification result when finished.
