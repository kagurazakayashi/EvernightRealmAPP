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

## Server address

The server entry page lets you type the address of the server you want to use and keep it on this device, so switching between test servers no longer needs a rebuild. Only a complete `http://` or `https://` address that carries no user name or password is accepted, and an address is saved only after it answers. A wrong format is reported with the specific reason — for example "The address must start with http:// or https://" — and no request is sent at all; an address with a valid format that does not respond is not saved, and the page says why instead of pretending otherwise. The address in use and the address saved on this device are listed separately, together with where the current one came from; a debug build keeps the build parameter `--dart-define=ER_SERVER_BASE_URL` in priority and states on screen that a locally saved address is not yet in effect. Your entry is stored on your own device only.

## When something goes wrong

If part of the app cannot be displayed, the interface switches to a safe notice page: it says where the problem happened (drawing the interface, a background task, or talking to the server), gives a diagnostic code you can match against this device's log, and includes the server request ID when the failure involves a request. A single action, "Return to a working page", takes you back to an usable interface. The notice page never shows the raw error text, a stack trace, or the server address, and nothing is sent anywhere — problems are recorded on your own device only.

One honest caveat: the section that just failed may stay blank for a while after you return, until the interface rebuilds. If the same problem keeps coming back, the notice page will tell you to reload the app.

## License

Mulan Permissive Software License, Version 2 (MulanPSL-2.0). Third-party original licenses are not overridden.

Bundled fonts: Noto Sans SC / Noto Sans TC / Noto Sans JP, SIL Open Font License 1.1 (texts under `licenses/`).
