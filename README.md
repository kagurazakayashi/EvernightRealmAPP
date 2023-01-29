![EvernightRealm Web](assets/icons/EvernightRealmFrontendRounded.ico)
<!-- 圖示：來源檔在 assets/icons/，各平台尺寸由 tools/icons/generate_icons.py 推導 -->

# EvernightRealm Web

> The client interface of EvernightRealm — step into your group's private world from a browser or desktop app.

[English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文（台灣）](./README.zh-TW.md) · [日本語](./README.ja-JP.md)

## What is this?

This is the client of EvernightRealm, a self-hosted, offline-first platform for a small group of players. Activities, characters, assets and chat all come to life here, on a local network — no internet, cloud accounts or telemetry.

## Features (under development)

- **Activity view** — follow scenes, phases and events as they unfold
- **Character panel** — play player, NPC and admin identities in one private world
- **Asset management** — see and trade virtual items with auditable ownership
- **Private chat** — messages stay on your own server
- **Offline-first** — the client works fully against your local server; no cloud required

## Current status

Under active development. No stable release is available yet.

## How it will work (once released)

- Open the host's address in a browser on the same local network — no install needed
- A desktop app will also be available for Windows, macOS and Linux
- No third-party registration; data stays on the host's machine

## Languages

Simplified Chinese, Traditional Chinese (Taiwan), English and Japanese. The interface language follows your system language by default and can be switched on the server entry page; the choice is remembered locally. System languages outside this list fall back to English.

## Server connectivity check

The server entry page offers a server connectivity check: it reads the health and time endpoints from your server and shows the service name and version, the server's UTC time, that time converted to the server's own display timezone, and the request ID for the call. When a check fails, the interface states only why it failed (unreachable, no response, service not ready, and so on) together with the error code and request ID — nothing that looks like a successful result is left on screen. Every value comes from the server; the app never falls back to the device clock or sample data.

## Root initialization guide

A brand-new server has no Root yet, so the entry page carries a read-only "Root initialization" card. It asks the server for its initialization state and shows exactly one of five honest results: not initialized, already initialized, server unreachable, server refuses to report, or this check produced no reliable answer. (With no saved address it says that first and sends no request at all.) The steps to run on the server's own machine — stop the service, create the schema first if the data directory is brand new, run `evernight-server init-root --password-stdin`, start the service again, then check again here — appear only when the server actually answered "no Root yet". A failed check is never phrased as a state, and "Check initialization" only asks again: every call is read-only and cannot create, change or overwrite a credential.

The card collects no password. It has no password field and sends no credential anywhere, because initializing Root remains reachable only through a command run on the server host. Once a credential exists the card stops listing steps and simply reports initialization is complete; signing in is now available through the "Login and session" card below, while this card itself stays read-only and collects no credentials.

## Sign-in and identity restoration

Once the server has a Root, the entry page's "Login and session" card is the way in:

- The sign-in page first shows which server you are about to sign in to (the effective address, plus service name and version when a probe succeeded), then asks for credentials. Two paths exist: Root sign-in (password only) and account sign-in (login name plus password). The account path reuses the existing server endpoint; this app offers no self-registration, and the only account-creation entry is the one Root uses in the Root console.
- Every failure says its own honest piece: refused credentials map to one uniform sentence (the server does not distinguish "no such account" from "wrong password", and neither does the interface), throttling says to try again later, unreachable and local-storage failures each say their own. No message ever echoes your password, the server's own text is never displayed verbatim, and nothing is saved or auto-filled on this device.
- After signing in, the identity shown is the one the server confirmed — never whatever the form guessed. Protected pages sit behind a session gate that shows nothing protected before the server answers, and the "return to" target kept when you are bounced to the sign-in page can only be a route registered in this app; anything else (including external URLs) lands you back on the entry page.
- Reopening the app restores and verifies the previous session first: while checking, only a neutral hint appears; if the session is still valid the card lists the real subject, device and server-side expiry (UTC); if the server deems it invalid you are returned to sign-in and the stored credential is cleared.
- The signed-in card carries a Sign-out button that makes the server revoke exactly this session: on web the response delivers a delete instruction with the same cookie name and attributes, on native the stored credential for this server is removed from system-level secure storage. Signing out again is idempotent—the server does not open a new session or tell you to sign in again just because the credential was already dead. When the server cannot be reached, this device still clears its own state, and the notice separates "local cleanup done" from "server revocation unconfirmed"; it never claims the server signed you out, and it never implies every device has gone offline.
- The signed-in card also carries a My-devices entry: it lists your own sessions exactly as the server reports them, marks the device you are using right now, and lets you revoke another one. The scope is enforced by the server — the panel cannot name another account's device — and revoking the current device is the same as signing out on it. A stale list, an already-invalid session and an unreachable server are each stated as they are; a revocation that did not happen is never reported as success.
- The signed-in card also carries a Change-password entry: rotating your credential requires handing over the current password in the request itself—“still signed in” is never authorization for a password change. A successful change revokes every session of yours, this device included (the approved policy), and the app enters the signed-out state asking you to sign in again with the new password. No password is cached anywhere: the three fields live only inside the dialog, are cleared when used, and every field is obscured. For accounts flagged “must change password at first sign-in” the server itself only serves the change-password flow, sign-out and the current-session read; every other protected feature answers machine code 2010. The card then shows only those entries instead of pretending buttons that are certain to be refused would work.
- The Root console wires seven capabilities today: creating a server administrator, browsing the administrator directory, viewing or editing one record, disabling or restoring an administrator's sign-in, resetting an administrator's sign-in credential, soft-deleting an administrator, and the server's account-creation policy. The creation form hands over three values - login name, display name and a one-time initial password - and there is no field for a role or a subject kind, because the endpoint is what makes the account an administrator. The initial password is never shown again, never cached locally and never appears anywhere in the interface; the new account has to change it at first sign-in, and until it does the server itself refuses every other protected entry with code 2010. A credential reset is handled the same way: Root types the replacement into one obscured field, the field is cleared as soon as it is submitted, nothing is ever read back, and a confirmation dialog states what the reset does before the request goes out. The directory is a real page view, not a fixed short list: paging with a server-echoed total, one status filter (deleted accounts are listed too), newest grant first, and - plainly stated by design - the configured Root is never one of its editable rows. Opening a row re-reads that single record from the server before the edit form appears; the form edits only the display name and submits it with the stored value it saw, so a save based on a stale screen is refused (2013) and overwrites nothing. Disabling asks for an explicit confirmation that names the target, says what it does (new sign-ins rejected, all their live sessions revoked) and what it does not do - it is not deletion. Restoring only brings back the ability to sign in again: sessions revoked when the account was disabled stay dead, and a pending first password change stays required. Deletion is its own terminal action behind its own confirmation, which names the account and states the effects before anything is sent: sign-in stops, live sessions are revoked, and there is no restore - disabled and deleted are two different states, so the restore entry can never revive a deleted account and the interface offers no such button. A deleted record goes read-only: it shows the placeholder display name the server wrote and the deletion time, and it explains that the identity behind past operations is still resolvable, because grants, sessions and audit rows keep pointing at the same account. Root's own configured credential is not a directory row, so it is never a target here. Neither Root nor one administrator disabling a peer can be submitted from this interface at all, and a stale or repeated status change is refused with 2014, which the screen turns into "reload and look again", never a second click; editing, resetting the credential or deleting an already-deleted account is refused with 2015, and nothing that deletes is ever re-sent on an unclear outcome. Every number and label shown comes from server responses; nothing is filled in optimistically. The seventh is the policy card: it reads the three values from the server (whether administrators may create ordinary accounts, the self-registration mode, whether guest accounts may be created) and requires a confirmation dialog before saving. The screen keeps two facts apart - what is saved is this deployment's intention, while none of the three creation paths exists yet, so the line saying what an unsigned-in browser can see stays closed. Mode offers only closed and open; sending a recognised name such as approval or invite is refused by the server with 2016, which the screen words separately from 1004's malformed-value sentence. When the card cannot read the policy it shows no guessed values, a failed write returns all three values to the last server truth, and an unclear outcome is never re-sent automatically.
- The rest of the Root management modules are still under development: the signed-in home shows only the true identity and entries that actually work today, and nothing is padded with sample data. Identity lines follow the `roles` the server returns, so an administrator sees "server administrator" and an account without grants does not; a signed-in administrator who opens the same creation form is told plainly that they lack permission (code 2011), and signing in again does not change that. Session credentials are kept by the browser's HttpOnly cookie on web, and by system-level secure storage on native clients — never in plain local files. On web that cookie is marked Secure only when the page is actually served over HTTPS; on a plain-HTTP LAN deployment the browser's protection comes from SameSite plus the server's origin check, so using HTTPS means putting your own TLS-terminating reverse proxy in front of the server.

## Server address

The server entry page lets you type the address of the server you want to use and keep it on this device, so switching between test servers no longer needs a rebuild. Only a complete `http://` or `https://` address that carries no user name or password is accepted, and an address is saved only after it answers. A wrong format is reported with the specific reason — for example "The address must start with http:// or https://" — and no request is sent at all; an address with a valid format that does not respond is not saved, and the page says why instead of pretending otherwise. The address in use and the address saved on this device are listed separately, together with where the current one came from; a debug build keeps the build parameter `--dart-define=ER_SERVER_BASE_URL` in priority and states on screen that a locally saved address is not yet in effect. Your entry is stored on your own device only.

## When something goes wrong

If part of the app cannot be displayed, the interface switches to a safe notice page: it says where the problem happened (drawing the interface, a background task, or talking to the server), gives a diagnostic code you can match against this device's log, and includes the server request ID when the failure involves a request. A single action, "Return to a working page", takes you back to an usable interface. The notice page never shows the raw error text, a stack trace, or the server address, and nothing is sent anywhere — problems are recorded on your own device only.

One honest caveat: the section that just failed may stay blank for a while after you return, until the interface rebuilds. If the same problem keeps coming back, the notice page will tell you to reload the app.

## Building from source

The per-platform icons and launch screens are generated, not committed: they are derived from the four source images in `assets/icons/`. On a fresh clone, run

    python tools/icons/generate_icons.py

before building — Android, iOS, macOS and Windows builds fail while their icon resources are missing, and a web build would ship without icons. `python tools/icons/generate_icons.py --check` reports the current state without writing anything; see `tools/icons/README.md`.

## License

Mulan Permissive Software License, Version 2 (MulanPSL-2.0). Third-party original licenses are not overridden.

Bundled fonts: Noto Sans SC / Noto Sans TC / Noto Sans JP, SIL Open Font License 1.1 (texts under `licenses/`).
