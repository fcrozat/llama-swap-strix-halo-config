# Publishing this repo

The runbook for the branch `AGENTS.md` keeps out of sight: something is already
in the history that must not be public - the local account name, a credential, a
vendored upstream file. It has been done here twice, so the steps below are what
those two passes actually needed, not a theory. The standing rules for commits
that have not happened yet are in `AGENTS.md`, section "Publishable history".

## What counts as clean

No account name, credential, private host or upstream tarball file in **any
commit**. A clean HEAD means nothing: a file deleted last week still ships inside
the packfile, so the audit runs over the object store.

## Audit

Five surfaces. Match over objects rather than the working tree - the gitignored
`llama-swap` pins make a case-insensitive grep report `cooperate` out of the Go
runtime as a false positive.

```bash
N='<needle>'
git rev-list --objects --all | cut -d' ' -f1 | sort -u \
  | git cat-file --batch-check='%(objectname) %(objecttype)' \
  | awk '$2=="blob"{print $1}' | sort -u > /tmp/objs
while read -r b; do git cat-file blob "$b"; done < /tmp/objs | grep -ic "$N"
git log --all --format='%B%GG'           | grep -ic "$N"   # messages + trailers
git log --all --format='%an %ae %cn %ce' | grep -ic "$N"   # identity headers
{ git show-ref; git tag -l
  git log --all --diff-filter=A --name-only --format=''; } | grep -ic "$N"
git fsck --unreachable | wc -l                    # 0, or old objects still live
```

Run it per needle: the account name, `BEGIN PRIVATE`, `api_key`, `token`,
`password`, `://[^/]*:.*@` (a `user:pass@` URL), and any hostname that is not
`localhost`. Both passes here found `0.0.0.0` and `127.0.0.1` as the only
addresses anywhere, and the `ghcr.io/...` images pull anonymously with no
registry credentials on the box, so an image reference is not a credential.

Before trusting a `0`, run the same blob pipeline with a needle you know is
present (`podman`) and watch it go nonzero - a silently empty `/tmp/objs` reads
exactly like a clean repo.

Then pick the needle by shape rather than by substring: `grep -iw` for a bare
name, the full `/home/<name>` for a path. A substring match fires on ordinary
prose - `cooperate` is in the Go binaries, which is why the tree is grepped over
objects at all, and the same word inside this file's own warning above is the
single match a `-i` audit still reports here.

## Rewrite

```bash
# the undo, kept off-repo
git bundle create ~/launchers-pre-<change>.bundle --all
```

`git filter-repo`, not `filter-branch`. Four things its help text leaves unclear,
each one paid for:

- **`--replace-text` covers blob contents only.** Commit and tag messages need
  `--replace-message` (identical file syntax) or `--message-callback`.
- **Literal rules run in file order, each one over the previous rule's output**
  (`blob.data` is rewritten once per rule in a loop). Where needles overlap the
  specific rule must sit on top: `<name>==>x` above `enable-linger <name>==>y`
  removes the longer rule's last chance to match. Non-overlapping rules are
  order-free, so this only bites when a generic rule is listed first.
- **Binary blobs are skipped outright** (a zero byte in the first 8 KiB). A
  secret inside a `llama-swap.v*` pin or a GGUF cannot be substituted - drop the
  path with `--invert-paths`, or the object with `--strip-blobs-with-ids`.
- **`--message-callback` is a function body, not an expression.** It wants
  `return`, so an `A and B or C` one-liner dies with "should have a return
  statement". For multi-line replacement prose, write it to a file and return
  `open(path,"rb").read()`.

Rules files split on `==>`, default to literal (`regex:` and `glob:` opt in), and
a line with no `==>` replaces its match with `***REMOVED***`.

`--force` is needed with a dirty tree, and the run ends by expiring the reflogs
and `gc --prune=now` - that is what actually drops the old objects, so an audit
before it finishes is meaningless.

Quoted hashes die. A hash referenced in a message or in `TODO.md` stops
resolving; `--preserve-commit-hashes` keeps the text accurate while invalidating
the reference anyway. Name a commit by its subject, or point at the bundle.

## Then hand-write the tip

Substitution is mechanical, and mechanical leaves prose lying. Both passes needed
a follow-up commit for exactly this:

- A message that *quoted* the old value now quotes its replacement and reads as
  nonsense (`replaces the literal $HOME`). Rewrite those messages to name the
  thing - "the literal absolute path" - and keep a probe's output as the claim it
  supported rather than the bytes it printed.
- `$HOME` inside a llama-swap config value is wrong on its own merits: the binary
  expands `${env.VAR}` and nothing else, so the value stays literal and podman
  receives a path containing `$HOME`. Use `${env.HOME}`.
- Aligned comment columns shift by the width difference between the name and the
  replacement; realign them with their neighbours.
- Docs describing the pre-rewrite tree go stale mid-flight - `TODO.md` §3 stated
  the name had survived after it had not, and its "16 files and 220 KiB" was a
  measurement of an older tree. Measure again instead of reusing the number.

## Prove it

Rerun the whole audit against the rewritten repo **and a fresh clone of it** -
the clone is what a stranger gets, and it is the only check that the rewrite
reached every ref. Then `./llama-swap -config config.yaml -validate` for
`config is valid: 18 model(s)` and `curl -s localhost:8080/health` for `OK`.

`git fsck --unreachable` counts leftovers rather than leaks: an intermediate from
an amend stays loose until `git gc --prune=now`. Unreachable objects are never
pushed, but they keep the bytes on the disk.

A rewrite changes history and comments only, so no engine should have restarted
and no `ls-*` container should have moved. If restarting the unit to "apply" it
feels necessary, reread *Applying a change* in `AGENTS.md` first.

Then decide. Every hash changed, so the first push is a one-way door: after it
the history is public and force-pushing is off the table.

```bash
gh repo create strix-launchers --public --source=. --remote=origin --push
```

Finally, delete the bundles once the rewrite is confirmed good - each one is a
single file holding exactly what the rewrite removed.
