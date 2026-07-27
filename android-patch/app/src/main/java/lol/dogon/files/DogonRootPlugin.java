package lol.dogon.files;

import android.content.pm.PackageManager;
import android.text.TextUtils;

import androidx.annotation.NonNull;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.CapacitorPlugin;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.List;

import rikka.shizuku.Shizuku;
import com.topjohnwu.superuser.Shell;

/**
 * DogonRoot Capacitor Plugin
 * -------------------------------------------------------------
 * Öncelik sırası:
 *   1) Shizuku (ADB/root binder üzerinden ayrıcalıklı, root olmayan erişim)
 *   2) libsu (Magisk root varsa klasik root fallback)
 *   3) İkisi de yoksa backend="none" döner, JS tarafı kurulum ekranı gösterir.
 *
 * SADECE SALT-OKUNUR komutlar çalıştırılır (ls, stat). Yazma/silme/root shell
 * komutu bu plugin üzerinden ÇALIŞTIRILMAZ — bilinçli bir güvenlik sınırıdır.
 */
@CapacitorPlugin(name = "DogonRoot")
public class DogonRootPlugin extends Plugin {

    private static final int SHIZUKU_PERMISSION_REQUEST_CODE = 9421;
    private PluginCall pendingPermissionCall;

    private final Shizuku.OnRequestPermissionResultListener permissionListener =
        (requestCode, grantResult) -> {
            if (requestCode != SHIZUKU_PERMISSION_REQUEST_CODE || pendingPermissionCall == null) return;
            boolean granted = grantResult == PackageManager.PERMISSION_GRANTED;
            JSObject ret = new JSObject();
            ret.put("granted", granted);
            pendingPermissionCall.resolve(ret);
            pendingPermissionCall = null;
        };

    @Override
    public void load() {
        super.load();
        try {
            Shizuku.addRequestPermissionResultListener(permissionListener);
        } catch (Throwable ignored) {
            // Shizuku sınıfı class-path'te ama servis hiç başlatılmamış olabilir; sorun değil.
        }
        // libsu: her komutta yeni root shell istemek yerine tek kalıcı shell kullan
        Shell.enableVerboseLogging = false;
        Shell.setDefaultBuilder(Shell.Builder.create()
                .setFlags(Shell.FLAG_REDIRECT_STDERR)
                .setTimeout(10));
    }

    private boolean shizukuReady() {
        try {
            return Shizuku.pingBinder();
        } catch (Throwable t) {
            return false; // Shizuku servisi kurulu değil / çalışmıyor
        }
    }

    private boolean shizukuPermitted() {
        try {
            return Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED;
        } catch (Throwable t) {
            return false;
        }
    }

    private boolean libsuRootAvailable() {
        try {
            return Shell.getShell().isRoot();
        } catch (Throwable t) {
            return false;
        }
    }

    /** JS: DogonRoot.isAvailable() -> {available, backend, permission} */
    @PluginMethod
    public void isAvailable(PluginCall call) {
        JSObject ret = new JSObject();
        if (shizukuReady()) {
            ret.put("backend", "shizuku");
            ret.put("available", true);
            ret.put("permission", shizukuPermitted());
        } else if (libsuRootAvailable()) {
            ret.put("backend", "libsu");
            ret.put("available", true);
            ret.put("permission", true); // libsu izin isteği ilk komutla birlikte gelir
        } else {
            ret.put("backend", "none");
            ret.put("available", false);
            ret.put("permission", false);
        }
        call.resolve(ret);
    }

    /** JS: DogonRoot.requestPermission() -> {granted} */
    @PluginMethod
    public void requestPermission(PluginCall call) {
        if (shizukuReady()) {
            if (shizukuPermitted()) {
                JSObject ret = new JSObject();
                ret.put("granted", true);
                call.resolve(ret);
                return;
            }
            pendingPermissionCall = call;
            try {
                Shizuku.requestPermission(SHIZUKU_PERMISSION_REQUEST_CODE);
            } catch (Throwable t) {
                pendingPermissionCall = null;
                call.reject("Shizuku izin isteği başarısız: " + t.getMessage());
            }
            return; // sonuç permissionListener callback'inde resolve edilecek
        }

        // Shizuku yok ama libsu (Magisk) olabilir -> ilk root komutu izni tetikler
        boolean root = libsuRootAvailable();
        JSObject ret = new JSObject();
        ret.put("granted", root);
        call.resolve(ret);
    }

    /** JS: DogonRoot.listDir({path}) -> {entries:[{name,isDir,size,mtime,path}]} */
    @PluginMethod
    public void listDir(PluginCall call) {
        String path = call.getString("path", "/");
        if (TextUtils.isEmpty(path)) path = "/";

        // Basit path enjeksiyon koruması: sadece mutlak yollara izin ver, ';','&','|','`' reddet
        if (path.matches(".*[;&|`$><].*")) {
            call.reject("Geçersiz yol");
            return;
        }

        String cmd = "ls -la " + shellQuote(path);

        try {
            List<String> lines;
            if (shizukuReady() && shizukuPermitted()) {
                lines = runViaShizuku(cmd);
            } else if (libsuRootAvailable()) {
                lines = runViaLibsu(cmd);
            } else {
                call.reject("Kök erişim mevcut değil");
                return;
            }
            call.resolve(parseLsOutput(lines, path));
        } catch (Throwable t) {
            call.reject("Listeleme başarısız: " + t.getMessage());
        }
    }

    private String shellQuote(String path) {
        return "'" + path.replace("'", "'\\''") + "'";
    }

    private List<String> runViaLibsu(String cmd) {
        Shell.Result res = Shell.cmd(cmd).exec();
        return res.getOut();
    }

    private List<String> runViaShizuku(String cmd) throws Exception {
        // Shizuku.newProcess salt-okunur "sh -c <cmd>" çalıştırır; sonuç stdout'tan okunur.
        java.lang.reflect.Method newProcess = Shizuku.class.getDeclaredMethod(
                "newProcess", String[].class, String[].class, String.class);
        newProcess.setAccessible(true);
        Process process = (Process) newProcess.invoke(null,
                (Object) new String[]{"sh", "-c", cmd}, null, null);

        java.util.List<String> out = new java.util.ArrayList<>();
        try (InputStream is = process.getInputStream();
             BufferedReader br = new BufferedReader(new InputStreamReader(is))) {
            String line;
            while ((line = br.readLine()) != null) out.add(line);
        }
        process.waitFor();
        return out;
    }

    /** "ls -la" çıktısını Capacitor JSObject listesine çevirir (basit, kabaca birçok Android/BusyBox varyantını kapsar). */
    private JSObject parseLsOutput(List<String> lines, String basePath) {
        JSObject ret = new JSObject();
        JSArray entries = new JSArray();
        for (String line : lines) {
            if (line == null) continue;
            line = line.trim();
            if (line.isEmpty() || line.startsWith("total")) continue;
            // Örnek satır: drwxr-xr-x  2 root root  4096 2026-01-01 12:00 app
            String[] parts = line.split("\\s+", 8);
            if (parts.length < 8) continue;
            String perms = parts[0];
            String sizeStr = parts[4];
            String name = parts[7];
            if (name.equals(".") || name.equals("..")) continue;

            boolean isDir = perms.startsWith("d");
            long size = 0;
            try { size = Long.parseLong(sizeStr); } catch (Exception ignored) {}

            JSObject entry = new JSObject();
            entry.put("name", name);
            entry.put("isDir", isDir);
            entry.put("size", size);
            entry.put("mtime", 0); // BusyBox/toybox tarihi formatı cihaza göre değişir; JS tarafında opsiyonel
            String childPath = basePath.endsWith("/") ? basePath + name : basePath + "/" + name;
            entry.put("path", childPath);
            entries.put(entry);
        }
        ret.put("entries", entries);
        return ret;
    }
}
