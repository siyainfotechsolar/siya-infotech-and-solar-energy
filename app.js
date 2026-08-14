// Dynamic Release Metadata Loader
document.addEventListener('DOMContentLoaded', async () => {
  try {
    const response = await fetch('release.json?v=' + Date.now(), { cache: 'no-store' });
    if (!response.ok) return;

    const data = await response.json();

    // Update app title & subtitle
    if (data.appName) {
      document.title = `${data.appName} - Download Android App`;
      const appNameEl = document.getElementById('appName');
      if (appNameEl) appNameEl.textContent = data.appName;
    }

    if (data.subtitle) {
      const subtitleEl = document.getElementById('appSubtitle');
      if (subtitleEl) subtitleEl.textContent = data.subtitle;
    }

    // Update Version & Badges
    if (data.version) {
      const versionBadgeEl = document.getElementById('versionBadge');
      if (versionBadgeEl) versionBadgeEl.textContent = `Version ${data.version}`;

      const versionValEl = document.getElementById('versionVal');
      if (versionValEl) versionValEl.textContent = `${data.version} (Build ${data.versionCode || 1})`;
    }

    if (data.releaseDate) {
      const dateValEl = document.getElementById('dateVal');
      if (dateValEl) dateValEl.textContent = data.releaseDate;
    }

    if (data.apkSize) {
      const sizeValEl = document.getElementById('sizeVal');
      if (sizeValEl) sizeValEl.textContent = data.apkSize;
    }

    if (data.minAndroidVersion) {
      const minAndroidValEl = document.getElementById('minAndroidVal');
      if (minAndroidValEl) minAndroidValEl.textContent = data.minAndroidVersion;
    }

    // Update Download Links
    if (data.apkFile) {
      const primaryBtn = document.getElementById('primaryDownloadBtn');
      if (primaryBtn) primaryBtn.setAttribute('href', data.apkFile);
    }

    if (data.latestApk) {
      const latestBtn = document.getElementById('latestDownloadBtn');
      if (latestBtn) latestBtn.setAttribute('href', data.latestApk);
    }

    // Update Changelog List
    if (Array.isArray(data.changelog) && data.changelog.length > 0) {
      const changelogListEl = document.getElementById('changelogList');
      if (changelogListEl) {
        changelogListEl.innerHTML = '';
        data.changelog.forEach(item => {
          const li = document.createElement('li');
          li.textContent = item;
          changelogListEl.appendChild(li);
        });
      }
    }
  } catch (err) {
    console.log('[ReleasePage] Using static fallback metadata:', err);
  }
});
