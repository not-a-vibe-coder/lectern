# Lectern

**Lecture notes and past questions for a class, on one shelf.**

A course rep signs in with a Sui wallet, creates a shelf such as "Computer Science · 300 Level · 2026/2027", uploads the class materials and shares one link or a printed QR code. Classmates open it on any phone with no wallet and no account, find files by course code and download them.

Files are stored on [Walrus](https://walrus.xyz) through [Dartus](https://pub.dev/packages/dartus),
the Dart SDK for Walrus. Each course rep's own Sui wallet (for example [Slush](https://slush.app))
pays for what they store and owns the Blob object on Sui. The server holds no keys and pays for
nothing.

## Features

- **Shelves for course reps.** Sign in with a Sui wallet (a signed message, no gas), create a shelf from school, department, level and session, and manage it from any device.
- **Batch uploads.** PDF, PNG, JPEG, WebP, GIF, DOCX and PPTX, up to 25 MB each. Files added together are stored as one Walrus quilt: two wallet approvals and one storage fee for the whole batch. Course codes and titles are suggested from file names.
- **Share anywhere.** Copy the class link, share it to WhatsApp, or print an A4 QR poster for the lecture hall.
- **For students.** No wallet, no sign-in. Files are grouped by course code, with type filters, search ("csc301" matches "CSC 301"), "new since your last visit" marks, inline image previews and downloads under the original file name.
- **Honest storage.** Every item shows its blob ID and when its storage period ends. Hiding a file removes it from the shelf; the rep's wallet owns the Blob object on Sui.

## How it works

- **`app/`**: Flutter web app. Uploads go through Dartus `WalrusWriter`: the blob ID is computed
  in a Web Worker, the wallet approves the storage payment, the bytes go to the Walrus upload
  relay, and the wallet approves once more to certify. Reads use Dartus `WalrusClient`.
- **`server/`**: Dart ([shelf](https://pub.dev/packages/shelf)) server. Serves the landing page
  and the web app, handles Sign in with Sui, keeps metadata in SQLite, and checks every upload
  on Sui (a certified Walrus Blob owned by the signed-in address) before listing it.
- **`packages/`**: shared packages for wallet connection, sign-in, blob checks and upload
  recovery.

```
app/        Flutter web app, served at /app
server/     Dart server and API
packages/   shared Dart packages
Dockerfile  one image with the app and the server
```

## Running locally

With Docker:

```sh
docker build -t lectern .
docker run -p 8091:8091 -v lectern-data:/data -e PUBLIC_BASE_URL=http://localhost:8091 lectern
```

Or with Flutter 3.44.2:

```sh
cd app && flutter pub get
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
cd ../server && dart pub get
WEB_DIR=../app/build/web PORT=8091 PUBLIC_BASE_URL=http://localhost:8091 dart run bin/server.dart
```

Open http://localhost:8091 for the landing page and http://localhost:8091/app for the app.
Sign-in is bound to `PUBLIC_BASE_URL`, so open exactly that address (`127.0.0.1` is a different
origin). By default everything runs on Sui testnet.

## Configuration

Environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8091` | HTTP port |
| `PUBLIC_BASE_URL` | `http://localhost:<PORT>` | The exact URL people open. Sign-in messages are bound to it, and share links and link previews are built from it. Set it in production. |
| `SUI_CHAIN` | `testnet` | `testnet` or `mainnet` |
| `AGGREGATOR_URL` | Mysten's aggregator for `SUI_CHAIN` | Walrus aggregator for reads |
| `EPOCHS` | `26` | Storage period the app suggests (a mainnet epoch is two weeks). Users pay for what they choose. |
| `MAX_UPLOAD_MB` | `25` | Largest file accepted |
| `DATA_DIR` | `data` | Folder for the SQLite database |
| `TRUST_PROXY` | `false` | Set to `true` behind a reverse proxy that sets `X-Forwarded-*` headers |
| `CLAIM_LIMIT` | `120` | Blob claims per account per hour |
| `SESSION_DAYS` | `30` | How long a sign-in lasts |
| `SIGN_IN_LIMIT` | `30` | Sign-in requests per client address per 10 minutes |

## Deploying

The `Dockerfile` builds the web app and the server into one small image. Run it on any host that
supports Docker and give it a persistent volume at `/data`. For mainnet:

```sh
PUBLIC_BASE_URL=https://lectern.example.com
SUI_CHAIN=mainnet
AGGREGATOR_URL=https://aggregator.walrus-mainnet.walrus.space
TRUST_PROXY=true   # when behind the host's proxy
```

There is no publisher to run and no wallet to fund: every upload is paid for by the user's
wallet.

## Licence

MIT. See [LICENSE](LICENSE).
