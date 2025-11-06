# raspi-dhcpcd-reconnect

A simple Bash script that automatically checks and restores network connectivity on Raspberry Pi systems that use **dhcpcd** as their network manager.

If your Raspberry Pi loses Internet access (for example, after a router reboot), this script will detect the issue, attempt to reconnect, and notify you via Telegram once connectivity is restored.

> **Disclaimer:**  
> This tool is intended for **personal use only** and **not recommended for production environments**.  
> Use it at your own risk and review the code before deployment.

---

## Features

- Checks both router and Internet connectivity.
- Automatically restarts the `dhcpcd` service if the connection is lost.
- Optional Telegram notification when the Internet connection is restored.
- Logs only when something goes wrong or recovers — no unnecessary noise.
- Allows custom IP addresses for router and Internet targets.
- Lightweight and cron-friendly.

---

## Installation

### 1. Clone the repository
```bash
git clone https://github.com/c24o/raspi-dhcpcd-reconnect.git
cd raspi-dhcpcd-reconnect
```

### 2. (Optional) Create an environment file
If you want to receive Telegram notifications, then create `/usr/local/etc/raspi-dhcpcd-reconnect/reconnect-dhcpcd-network.env` and add your Telegram credentials:

```bash
TELEGRAM_BOT_TOKEN="1234567890:ABCDEF1234567890abcdef1234567890ab"
TELEGRAM_CHAT_ID="123456789"
```

Keep this file private — it contains your bot's secret token.

Set secure permissions:
```bash
sudo chown root:root /usr/local/etc/raspi-dhcpcd-reconnect/reconnect-dhcpcd-network.env
sudo chmod 600 /usr/local/etc/raspi-dhcpcd-reconnect/reconnect-dhcpcd-network.env
```

If you don't create this file or don't set both variables, then the script will skip Telegram notifications.

Check the instructions below to generate a Telegram Bot.

### 3. Make the script executable
```bash
chmod +x reconnect-dhcpcd-network.sh
```

### 4. Add to crontab
Run `sudo crontab -e` and add this line to check every 10 minutes:

```bash
*/10 * * * * /path/to/reconnect-dhcpcd-network.sh
```

---

## Default and Custom Values

The script supports both default and custom IP addresses for testing connectivity.

### Default behavior
If you run the script without parameters, it will use:
- **Router IP:** `192.168.1.1`
- **Internet IP:** `8.8.8.8`

Example:
```bash
./reconnect-dhcpcd-network.sh
```

### Custom IPs
You can override the defaults by passing arguments when running the script:

```bash
./reconnect-dhcpcd-network.sh <router_ip> <internet_ip>
```

Examples:
```bash
./reconnect-dhcpcd-network.sh 192.168.0.1 1.1.1.1
./reconnect-dhcpcd-network.sh 10.0.0.1 9.9.9.9
```

If only one argument is provided, the router IP is updated, and the Internet IP keeps its default value.

Example:
```bash
./reconnect-dhcpcd-network.sh 192.168.0.1
```

In this case, it will use the default internet IP of 8.8.8.8.

---

## Telegram Setup Guide (Optional)

### Step 1: Create a Telegram Bot

1. Open **Telegram** and search for **@BotFather**.  
2. Start a chat and send the command:
   ```
   /newbot
   ```
3. Follow the prompts to choose a name and username (the username must end with "bot", e.g., `RaspiReconnectBot`).  
4. Once finished, BotFather will reply with a message like:
   ```
   Done! Congratulations on your new bot.
   Use this token to access the HTTP API:
   1234567890:ABCDEF1234567890abcdef1234567890ab
   ```
   That is your **BOT_TOKEN**.

### Step 2: Get Your Chat ID

1. Open a chat with your new bot (click the link provided by BotFather, e.g. `t.me/RaspiReconnectBot`) and send any message (like `hi`).
2. Then, in your Raspberry Pi terminal, run:
   ```bash
   curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
   ```
3. You’ll see a JSON response like:
   ```json
   {
     "ok": true,
     "result": [
       {
         "update_id": 123456789,
         "message": {
           "chat": {
             "id": 987654321,
             "first_name": "Carlos",
             "type": "private"
           },
           "text": "hi"
         }
       }
     ]
   }
   ```
4. The `"id"` inside `"chat"` (e.g. `987654321`) is your **CHAT_ID**.

You can now test the setup:

```bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
     -d chat_id="${TELEGRAM_CHAT_ID}"
     -d text="✅ Telegram notifications are working!"
```

If the message appears in Telegram, you’re all set.

---

## How It Works

1. The script pings both your router (e.g. `192.168.1.1`) and Google’s DNS (`8.8.8.8`).  
2. If both fail, it assumes the connection is lost and restarts the `dhcpcd` service.  
3. Once connectivity returns, it logs the event and sends a Telegram notification.  
4. If everything is working, it stays silent (no logs, no messages).

---

## Log File

By default, logs are saved at:
```
/var/log/raspi-dhcpcd-reconnect.log
```

Only connection failures and recoveries are recorded.

Example entries:
```
[2025-11-06 06:40:12] Router unreachable, attempting reconnect...
[2025-11-06 06:41:23] Internet connection restored, notification sent.
```
