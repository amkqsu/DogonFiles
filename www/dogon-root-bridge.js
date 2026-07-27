/* ============================================================
   DogonFiles — ROOT BRIDGE
   Bu dosya, HTML/JS tarafındaki ROOT_MODE simülasyonunu gerçek
   Shizuku / libsu native plugin'ine bağlar.

   Native taraf (android-patch/.../DogonRootPlugin.java) şu metodları
   Capacitor plugin köprüsü üzerinden JS'e açar:
     - DogonRoot.isAvailable()   -> {available: bool, backend: 'shizuku'|'libsu'|'none', permission: bool}
     - DogonRoot.requestPermission() -> {granted: bool}
     - DogonRoot.listDir({path}) -> {entries: [{name,isDir,size,mtime}]}
     - DogonRoot.openShizukuGuide() -> Shizuku kurulum sayfasını (Play Store/GitHub) açar

   Bu dosya www/index.html'in orijinal davranışını BOZMAZ:
   Plugin yoksa (ör. tarayıcıda test ederken) otomatik olarak
   eski ROOT_FS simülasyonuna düşer.
============================================================ */
(function () {
  const hasCapacitor = !!(window.Capacitor && window.Capacitor.Plugins);
  const NativeRoot = hasCapacitor ? window.Capacitor.Plugins.DogonRoot : null;

  function nodeFromNative(entry) {
    if (entry.isDir) {
      return { type: 'folder', name: entry.name, mtime: fmtMtime(entry.mtime), children: [], __realPath: entry.path };
    }
    const ext = (entry.name.split('.').pop() || '').toLowerCase();
    return { type: 'file', name: entry.name, size: entry.size || 0, mtime: fmtMtime(entry.mtime), ext, __realPath: entry.path };
  }

  function fmtMtime(ts) {
    if (!ts) return '—';
    try {
      const d = new Date(ts);
      return d.toLocaleDateString('tr-TR', { day: '2-digit', month: 'short' });
    } catch (e) { return '—'; }
  }

  // Bir dizini gerçek cihazdan asenkron listeleyip FS-node biçimine çevirir.
  async function listRealDir(path) {
    const res = await NativeRoot.listDir({ path });
    const children = (res.entries || []).map(nodeFromNative);
    return { type: 'folder', name: path.split('/').filter(Boolean).pop() || 'root', mtime: '—', children, __realPath: path };
  }

  // Orijinal kodda klasöre girme işlemi handleRowClick içinde state.path.push(node)
  // ile yapılıyor. Gerçek kök modundayken, bir klasöre ilk kez girildiğinde
  // içeriğini native tarafından lazy (istendiğinde) çekmek için bu fonksiyonu sarmalıyoruz.
  const originalHandleRowClick = window.handleRowClick;
  if (typeof originalHandleRowClick === 'function') {
    window.handleRowClick = async function (ref) {
      const node = nodeFromRef(ref);
      if (!state.selectMode && node && node.type === 'folder' &&
          window.DogonRootController && window.DogonRootController.isRealMode() &&
          node.__realPath && (!node.children || node.children.length === 0) && !node.__loaded) {
        try {
          const res = await NativeRoot.listDir({ path: node.__realPath });
          node.children = (res.entries || []).map(nodeFromNative);
          node.__loaded = true;
        } catch (e) {
          showToast('Klasör okunamadı: ' + (e.message || 'izin hatası'), 'warn');
          return;
        }
      }
      return originalHandleRowClick(ref);
    };
  }

  const DogonRootController = {
    _realMode: false,
    isRealMode() { return this._realMode; },

    async toggle() {
      // Kapatma: her zaman anında çalışır
      if (window.ROOT_MODE) {
        window.ROOT_MODE = false;
        this._realMode = false;
        document.getElementById('rootMenuLabel').textContent = 'Kök Erişimini Etkinleştir';
        showToast('Kök erişimi kapatıldı', 'ok');
        state.path = [FS];
        render();
        return;
      }

      if (!NativeRoot) {
        // Plugin yok (tarayıcı önizlemesi) -> eski simülasyona düş
        window.ROOT_MODE = true;
        this._realMode = false;
        document.getElementById('rootMenuLabel').textContent = 'Kök Erişimini Kapat';
        showToast('Kök erişimi etkinleştirildi (simülasyon — native plugin bulunamadı)', 'warn');
        state.path = [ROOT_FS];
        state.tab = 'files';
        goTab('files');
        return;
      }

      showToast('Kök erişimi kontrol ediliyor…', 'ok');
      let status;
      try {
        status = await NativeRoot.isAvailable();
      } catch (e) {
        status = { available: false, backend: 'none', permission: false };
      }

      if (status.backend === 'none') {
        // Ne Shizuku ne libsu var -> kurulum yönlendirme ekranını göster
        openShizukuGuideSheet();
        return;
      }

      if (!status.permission) {
        let granted = false;
        try {
          const permRes = await NativeRoot.requestPermission();
          granted = !!permRes.granted;
        } catch (e) { granted = false; }
        if (!granted) {
          showToast('Kök erişim izni verilmedi', 'warn');
          return;
        }
      }

      // Gerçek kök dizini listele
      try {
        const rootNode = await listRealDir('/');
        window.ROOT_MODE = true;
        this._realMode = true;
        document.getElementById('rootMenuLabel').textContent = 'Kök Erişimini Kapat';
        showToast(`Kök erişimi etkinleştirildi (${status.backend === 'shizuku' ? 'Shizuku' : 'libsu/Magisk'})`, 'ok');
        state.path = [rootNode];
        state.tab = 'files';
        goTab('files');
      } catch (e) {
        showToast('Kök dizin okunamadı: ' + (e.message || 'bilinmeyen hata'), 'warn');
      }
    }
  };
  window.DogonRootController = DogonRootController;

  // ---------- Shizuku kurulum yönlendirme sheet'i ----------
  function openShizukuGuideSheet() {
    let sheet = document.getElementById('sheetShizukuGuide');
    if (!sheet) {
      sheet = document.createElement('div');
      sheet.id = 'sheetShizukuGuide';
      sheet.className = 'sheet-overlay';
      sheet.innerHTML = `
        <div class="sheet" style="max-height:80vh;overflow-y:auto;">
          <div class="sheet-handle"></div>
          <h3 style="margin:4px 2px 14px;">Kök Erişimi İçin Shizuku Gerekli</h3>
          <div class="sub" style="line-height:1.5;margin-bottom:14px;">
            Cihazınızda Shizuku servisi çalışmıyor ve Magisk/libsu root da bulunamadı.
            Sistem klasörlerini (örn. /system, /data) görüntülemek için aşağıdaki
            yöntemlerden biriyle Shizuku'yu etkinleştirin:
          </div>
          <div class="menu-row" onclick="window.open('https://play.google.com/store/apps/details?id=moe.shizuku.privileged.api','_blank')">1) Play Store'dan Shizuku'yu kurun</div>
          <div class="menu-row" onclick="window.open('https://github.com/RikkaApps/Shizuku/releases','_blank')">2) veya GitHub'dan APK indirin</div>
          <div class="sub" style="margin-top:10px;">3) Bilgisayardan ADB ile başlatma:</div>
          <div style="background:var(--bg-elev2);border-radius:10px;padding:10px;font-family:monospace;font-size:12px;margin:6px 0;">adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh</div>
          <div class="sub">4) veya Android 11+ cihazlarda: Shizuku uygulaması içinden "Kablosuz hata ayıklama" (Wireless debugging) yöntemiyle bilgisayarsız başlatın.</div>
          <div class="sub" style="margin-top:10px;">Magisk ile root'luysanız ekstra kuruluma gerek yok — uygulama otomatik olarak libsu üzerinden root isteği gönderecektir.</div>
          <button class="btn-primary" style="margin-top:16px;width:100%;" onclick="closeSheet('sheetShizukuGuide')">Anladım</button>
        </div>`;
      document.body.appendChild(sheet);
    }
    openSheet('sheetShizukuGuide');
  }

  // Uygulama açılışında sessizce Shizuku/libsu durumunu kontrol et (sadece log/UI etiketi için)
  window.addEventListener('DOMContentLoaded', async () => {
    if (!NativeRoot) return;
    try {
      const status = await NativeRoot.isAvailable();
      console.log('[DogonRoot] backend:', status.backend, 'available:', status.available);
    } catch (e) { /* sessiz geç */ }
  });
})();
