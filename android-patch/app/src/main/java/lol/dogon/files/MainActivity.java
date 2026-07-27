package lol.dogon.files;

import android.os.Build;
import android.os.Bundle;
import android.view.WindowManager;
import android.webkit.WebSettings;
import android.webkit.WebView;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Özel plugin'i Capacitor köprüsüne kaydet
        registerPlugin(DogonRootPlugin.class);
        super.onCreate(savedInstanceState);

        // ---- 120Hz / akıcılık ayarları ----
        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);

        WebView webView = this.bridge.getWebView();
        WebSettings settings = webView.getSettings();
        // Kaydırma sırasında ekran dışı içeriği önceden çiz (jank azaltır)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            webView.setLayerType(WebView.LAYER_TYPE_HARDWARE, null);
        }
        settings.setOffscreenPreRaster(true);
        webView.setScrollBarStyle(WebView.SCROLLBARS_INSIDE_OVERLAY);
        webView.setOverScrollMode(WebView.OVER_SCROLL_NEVER);

        // Edge-to-edge (safe-area ile birlikte www/index.html zaten CSS env() kullanıyor olmalı)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            getWindow().setDecorFitsSystemWindows(false);
        }
    }
}
