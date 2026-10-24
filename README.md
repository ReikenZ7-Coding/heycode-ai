# HeyCode AI

A personal AI assistant you own. The app (Android and Windows) chats with your
own [Hermes Agent](https://hermes-agent.nousresearch.com) on a free Oracle Cloud
server, which thinks with full GLM-5.3 through OpenRouter.

```
App (Android / Windows)  ──https──▶  Oracle server: Hermes Agent  ──▶  OpenRouter: GLM-5.3
```

## 1. Set up the server

On a fresh Oracle Ubuntu 24.04 server (Always Free, `VM.Standard.A1.Flex`):

1. In the Oracle console, open the server's **subnet → Security list** and add
   two ingress rules: source `0.0.0.0/0`, TCP, destination ports `80` and `443`.
2. Connect with SSH and run:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/ReikenZ7-Coding/heycode-ai/main/server/setup-server.sh -o setup-server.sh
   bash setup-server.sh
   ```

   It asks for your OpenRouter key, then asks you to pick the model
   (OpenRouter → `z-ai/glm-5.3`). At the end it prints the **server address**
   and **private key** for the app.

Useful commands on the server:

| What | Command |
| --- | --- |
| Is the agent running? | `sudo systemctl status hermes` |
| Agent logs | `sudo journalctl -u hermes -n 100` |
| Restart the agent | `sudo systemctl restart hermes` |
| Show the app settings again | `cat ~/heycode-app-settings.txt` |

## 2. Install the app

Every push to `main` builds the apps and publishes them under
**Releases**:

- **Android:** download `HeyCode-AI-android.apk` and open it. Allow
  "install unknown apps" when asked.
- **Windows:** download `HeyCode-AI-windows.zip`, unzip it, and run
  `heycode_ai.exe`.

Open **Settings** in the app, paste the server address and private key, and
tap **Test and save**.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
