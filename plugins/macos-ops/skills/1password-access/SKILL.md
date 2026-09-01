---
name: 1password-access
description: Read a secret from 1Password via the op CLI without leaking it into the transcript. Use when a task needs a credential stored in 1Password, or when op reports "account is not signed in" or rejects a secret reference.
---

# 1Password access (op CLI)

Four things that cost trial and error on macOS with `op` 2.39 + desktop-app
integration. Everything else about `op` behaves as documented.

## 1. `op whoami` is not a liveness check

With desktop-app integration on, `op whoami` fails with `account is not signed
in` while `op` is fully working (biometric unlock happens per read). `op account
list` likewise lists accounts while signed out. Test with a real read:

```bash
op vault list   # succeeds => op works, whatever whoami says
```

Don't ask the user to `op signin` on the strength of a `whoami` error.

## 2. Use the ID form of `op://`, not the name form

Two independent reasons, both observed:

**Punctuation is unquotable.** A vault named `For Chang's Claude` breaks every
name-form reference — there is no escaping that satisfies it:

```
invalid secret reference 'op://For Chang's Claude/item/credential':
invalid character in secret reference: '''
```

**Names change; IDs don't.** That vault was later renamed to `For Claude`. Every
name-form reference to it broke a second time; the ID-form references kept
resolving untouched.

Resolve IDs once — they are stable and hazard-free:

```bash
op vault list                    # -> vault ID (26-char ULID)
op item list --vault "<name>"    # -> item ID
op read "op://<vaultID>/<itemID>/<field>"
```

## 3. Two commands leak the secret to stdout

- `op item get <id> --fields <f> --reveal` — obviously prints it.
- `op item get <id> --format json` — **also prints it.** It reads like metadata
  but the `fields[].value` entries carry live secret values.

Anything printed is in the transcript permanently. Always capture into a
variable in the *same* command that uses it:

```bash
TOK="$(op read "op://<vaultID>/<itemID>/credential")"
curl -sS -H "Authorization: Bearer $TOK" https://api.example.com/whoami
```

And when suppressing output, mind the order: `2>&1 >/dev/null` sends stderr to
the *old* stdout and leaves the value on screen. The suppress-both form is
`>/dev/null 2>&1`.

## 4. Inspect an item's shape without revealing it

To learn which fields exist (and read the non-secret ones like URLs or
usernames) before deciding what to fetch:

```bash
op item get <itemID> --format json | python3 -c "
import json,sys
SAFE={'url','website','domain','issuer','hostname','host','username','email','type'}
d=json.load(sys.stdin)
cat=d.get('category')
print(d.get('title'), '|', cat)
for f in d.get('fields',[]):
    label=(f.get('label') or f.get('id') or '').strip(); v=f.get('value')
    if v is None: continue
    safe = label.lower() in SAFE and cat != 'SECURE_NOTE'
    print(f'  {label}: {v if safe else f\"<redacted len={len(v)} prefix={v[:4]}>\"}')
"
```

The prefix and length are usually enough to identify a credential's type (an
Okta SSWS token starts `00`, a Google API key `AIzaSy`, a Notion integration
token `ntn_`) without exposing it.

**Two rules in that snippet are load-bearing — do not loosen either.**

**Match labels EXACTLY, never by substring.** An earlier version tested
`any(t in label.lower() for t in (...,'notes',...))`. 1Password names a secure
note's body `notesPlain`, which contains `notes`, so the snippet classified the
secret as safe metadata and printed it in full. Substring matching over a
safe-list fails open: every new field name is assumed harmless if it happens to
contain a safe word. Exact membership fails closed, which is the direction this
snippet needs — its whole promise is in the heading.

**Exclude `SECURE_NOTE` outright.** For that category the note *is* the
credential, so no field of it is metadata. Secure notes are exactly where loose
API keys get parked, which makes this the worst category to get wrong.

Both together, not either alone: the exact-match rule fixes the `notesPlain`
collision, and the category rule covers the next field name nobody predicted.
