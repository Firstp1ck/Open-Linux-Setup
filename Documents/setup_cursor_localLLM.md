# LM Studio Integration with Cursor IDE Setup Guide

## Overview
This guide covers how to use local LLM models from LM Studio within Cursor IDE using ngrok to bypass Cursor's private IP restrictions.

## Prerequisites
- LM Studio installed (version 0.3.35.1 or later)
- Cursor IDE installed
- ngrok account (free tier works)
- Arch Linux/EndeavourOS (or similar Linux distribution)

---

## Part 1: LM Studio Configuration

### 1.1 Load Your Model
1. Open LM Studio
2. Click the search/magnifying glass icon in the left sidebar to browse models
3. Download and load your desired model (e.g., `mistralai/ministral-3-14b-reasoning`)

### 1.2 Configure Server Settings
1. Navigate to the **Developer** tab (server icon in sidebar)
2. Click **"Server Settings"** button
3. Enable the following:
   - **Enable CORS** ✓
   - **Serve on Local Network** ✓
   - Set **Server Port** to `1234` (default)

### 1.3 Enable Reasoning Content Separation
For reasoning models only:
1. Go to **Settings** (gear icon) → **App Settings** → **Developer** tab
2. Enable: **"When applicable, separate reasoning_content and content in API responses"** ✓
3. This separates thinking process from actual answers in API responses

### 1.4 Start the Server
1. In the **Developer** tab, click **"Start Server"**
2. Verify status shows "Running" on port 1234

---

## Part 2: ngrok Setup

### 2.1 Install ngrok
```
# Arch Linux/EndeavourOS
yay -S ngrok
```

### 2.2 Create Static Domain (Free)
1. Go to [ngrok dashboard](https://dashboard.ngrok.com/cloud-edge/domains)
2. Navigate to **Cloud Edge** → **Domains**
3. Click **"Create Domain"**
4. You'll get a free static domain like `your-name.ngrok-free.app`
5. Save this domain name

### 2.3 Configure ngrok
Create the config file:

```
mkdir -p ~/.config/ngrok
nano ~/.config/ngrok/ngrok.yml
```

Add this content (use **spaces, not tabs**):

```
version: "2"
authtoken: YOUR_NGROK_AUTHTOKEN_HERE
tunnels:
  lmstudio:
    proto: http
    domain: your-static-domain.ngrok-free.app
    addr: 1234
```

Get your authtoken from [ngrok dashboard](https://dashboard.ngrok.com/get-started/your-authtoken)

### 2.4 Test ngrok
```
ngrok start lmstudio
```

You should see:
```
Forwarding  https://your-static-domain.ngrok-free.app -> http://localhost:1234
```

Keep this terminal open.

---

## Part 3: Cursor IDE Configuration

### 3.1 Add Custom Model
1. Open Cursor → **Settings** → **Models**
2. Click **"Add Model"**
3. Enter these details:
   - **Model Name**: `mistralai/ministral-3-14b-reasoning` (exact name from LM Studio)
   - **OpenAI Base URL**: `https://your-static-domain.ngrok-free.app/v1` ⚠️ **Must include `/v1`**
   - **API Key**: Any dummy value like `lm-studio` or `sk-local-1234`

### 3.2 Network Settings
1. In Cursor Settings, search for **"HTTP/2"**
2. Enable **"Disable HTTP/2"** (use HTTP/1.1)

### 3.3 Test Connection
1. Click **"Verify"** button in model settings
2. Open a new Chat in Cursor (Ctrl/Cmd + L)
3. Select your custom model from the dropdown
4. Send a test message

---

## Part 4: Autostart ngrok on Boot

### 4.1 Install ngrok as a System Service
ngrok includes built-in service management that automatically creates a systemd service:

```
# Install ngrok as a system service
sudo ngrok service install --config ~/.config/ngrok/ngrok.yml

# Start the service
sudo ngrok service start

# Enable to start on boot
sudo systemctl enable ngrok.service
```

This automatically configures ngrok to start at boot with your tunnels from the config file.

### 4.2 Verify Service Status
```
# Check if service is running
systemctl status ngrok.service

# View service logs
journalctl -u ngrok.service -f
```

The service will automatically start all tunnels defined in your `ngrok.yml` file on boot.

---

## Troubleshooting

### Issue 1: "Connection to private IP is blocked" (SSRF_BLOCKED)
**Error**: `{"error":{"type":"client","reason":"ssrf_blocked"}}`

**Cause**: Cursor blocks localhost and private IPs (192.168.x.x) for security

**Solution**: Must use ngrok or another public tunneling service

---

### Issue 2: "Empty provider response"
**Error**: Provider did not send back a response

**Possible Causes & Solutions**:

1. **Missing `/v1` in URL**
   - ✓ Correct: `https://domain.ngrok-free.app/v1`
   - ✗ Wrong: `https://domain.ngrok-free.app`

2. **Reasoning content not separated** (for reasoning models)
   - Enable "separate reasoning_content and content" in LM Studio Developer settings
   - Restart LM Studio server after enabling

3. **Model not loaded in LM Studio**
   - Verify model shows "Model Loaded: [name]" at top of LM Studio

4. **CORS not enabled**
   - Enable CORS in LM Studio Server Settings

5. **Timeout with reasoning models**
   - Reasoning models take 40+ seconds to respond
   - Test with faster models first (llama-3.1-8b-instruct)

---

### Issue 3: ngrok URL Changed
**Error**: `The endpoint xxx.ngrok-free.app is offline`

**Cause**: Free ngrok URLs change on every restart (without static domain)

**Solution**: 
- Use static domain (one free per account)
- Update Cursor settings if URL changes

---

### Issue 4: "Authentication failed: Your account is limited to 1 simultaneous ngrok agent"
**Error**: `ERR_NGROK_108`

**Cause**: Another ngrok instance is already running

**Solution**:
```
# Kill existing ngrok
pkill ngrok

# Or check dashboard
# https://dashboard.ngrok.com/agents

# Then start again
ngrok start lmstudio
```

---

### Issue 5: "EOS token found" - Model Stops Prematurely
**Symptom**: Model stops generating after "Thought for X seconds"

**Solutions**:
1. Update LM Studio to 0.3.14+ (bug was fixed)
2. Increase **Max Tokens** in model settings (try 2048-4096)
3. Lower **Temperature** (0.7-0.8)
4. Check/clear custom **Stop Sequences**
5. Try reloading the model

---

### Issue 6: YAML Parsing Error in ngrok.yml
**Error**: `yaml: line X: mapping values are not allowed in this context`

**Common Causes**:
1. **Missing newline after authtoken** - ensure authtoken is on its own line
2. **Tabs instead of spaces** - YAML requires spaces for indentation
3. **No space after colon** - must be `key: value` not `key:value`
4. **Wrong version** - use `version: "2"` not "3"

**Validation**:
```
# Check file contents
cat ~/.config/ngrok/ngrok.yml

# Test syntax
ngrok start lmstudio
```

---

### Issue 7: nginx Warning (Optional)
**Warning**: `could not build optimal types_hash`

**Solution** (if you set up nginx):
Edit `/etc/nginx/nginx.conf` in the `http` block:
```
http {
    types_hash_max_size 4096;
    # ... rest of config
}
```

Then reload: `sudo systemctl reload nginx`

**Note**: We ended up not using nginx due to Cursor's private IP restrictions, but kept it for potential future local network use.

---

## Testing Your Setup

### Test 1: Verify LM Studio API
```
curl https://your-domain.ngrok-free.app/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistralai/ministral-3-14b-reasoning",
    "messages": [{"role": "user", "content": "Hi"}],
    "stream": false
  }'
```

Should return JSON with `content` and `reasoning_content` fields.

### Test 2: Check ngrok Inspector
Open `http://127.0.0.1:4040` in your browser to see real-time requests/responses.

### Test 3: Cursor Connection
Send a test message in Cursor Chat - should receive a response without errors.

---

## Maintenance

### Restart Services
```
# Restart LM Studio server (in Developer tab)

# Restart ngrok service
sudo ngrok service restart

# Check ngrok status
systemctl status ngrok.service

# View ngrok logs
journalctl -u ngrok.service -f
```

### Update Static Domain
If you change your ngrok static domain:
1. Update `~/.config/ngrok/ngrok.yml`
2. Restart ngrok service: `sudo ngrok service restart`
3. Update Cursor's OpenAI Base URL

---

## Summary

With this setup:
- ✓ LM Studio models run locally on your machine
- ✓ ngrok provides public URL to bypass Cursor's SSRF protection
- ✓ Static domain means no URL changes on restart
- ✓ Automatic startup with ngrok's built-in service management
- ✓ Works with Cursor's Composer and Chat features

**Key Points to Remember**:
- Always include `/v1` in the Cursor Base URL
- Free ngrok tier allows one simultaneous session
- Reasoning models take 40+ seconds per response
- Enable reasoning content separation for reasoning models
- ngrok service runs automatically on boot

