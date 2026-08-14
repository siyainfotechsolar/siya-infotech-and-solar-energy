# 🚀 Free Direct APK Download Page (GitHub Pages Setup)

This static web directory allows staff and users to directly download the **Siya Infotech & Solar Energy** Android APK for free without requiring a paid server, database, or Google Play Console account.

---

## 📂 Directory Structure

```text
release-page/
├── index.html        # Main HTML download page
├── style.css         # Branding stylesheet (Deep Blue, Gold, Green)
├── app.js            # Dynamic metadata loader
├── release.json      # Release info (version, size, links, changelog)
├── README.md         # Hosting instructions
└── releases/
    ├── Siya-Infotech-Solar-v1.0.0.apk
    └── latest/
        └── Siya-Infotech-Solar-latest.apk
```

---

## 🛠️ Step-by-Step: Host for Free on GitHub Pages

### Step 1 — Create a GitHub Repository
1. Go to [github.com/new](https://github.com/new).
2. Name the repository: `solar-crm-downloads` (or `solar-crm-release`).
3. Set visibility to **Public**.
4. Click **Create repository**.

---

### Step 2 — Upload `release-page` Files
Run the following commands from your project root:

```bash
cd release-page
git init
git add .
git commit -m "Initial APK release v1.0.0"
git branch -M main
git remote add origin https://github.com/siyainfotechsolar/siya-infotech-and-solar-energy.git
git push -u origin main
```

---

### Step 3 — Enable GitHub Pages
1. On GitHub, open your repository ⚙️ **Settings**.
2. Scroll down to **Pages** in the left sidebar.
3. Under **Build and deployment** → **Source**, select **Deploy from a branch**.
4. Under **Branch**, select `main` and `/ (root)`.
5. Click **Save**.

---

### Step 4 — Get your Free Live Download Link!
After 1-2 minutes, GitHub will give you a live URL:

```text
https://siyainfotechsolar.github.io/siya-infotech-and-solar-energy/
```

Share this URL with staff members! They can open it on their mobile phone browser and tap **DOWNLOAD APK** to directly install the app.

---

## 🔄 How to Publish Future Releases (e.g. v1.0.1)

1. Increase the version in `pubspec.yaml` (`version: 1.0.1+2`).
2. Run `scripts/release_android.bat` (Windows) or `scripts/release_android.sh` (macOS/Linux).
3. Update `release-page/release.json` with the new version and changelog.
4. Commit and push:
   ```bash
   git add .
   git commit -m "Release v1.0.1"
   git push origin main
   ```
5. The download page will update automatically!
