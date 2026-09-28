"""Yönetim panelinin ortak detay sayfası: BAĞLANTI ve ERİŞİM bekçileri.

Neden bu dosya var: sahibin ölçülen şikâyeti "ortaklık linki nerede
görünmüyor, ortak hesabına nereden girecek belli değil" idi. Onarım tamamen
`web/rytho-admin/gorunumler/ortaklar.js` içinde ve onarımı geri alan bir
düzenleme (sütunu daraltmak, modülü kaldırmak, bağlantıyı
`location.origin`den kurmak) hiçbir testi kırmıyordu — yani aynı boşluk
sessizce geri gelebilirdi. Bu dosya o sessizliği kırıyor.

⚠️ Eşleşmeden ÖNCE yorumlar atılıyor: dosyanın kendi başlık yorumu
`rytho.app/r/` dizesini ANLATIYOR, yani yorumlu kaynakta arama yapan bekçi
kod bağlantıyı üretmeyi bıraksa bile YEŞİL kalırdı (bu depoda iki kez
patladı: build kapısı kendi manifest yorumuna, davet sayfası testi kendi
HTML yorumuna takıldı).

⚠️ Satır yorumu ayıklaması YALNIZ satır başındaki `//` için: aranan dizenin
kendisi `https://…` olduğu için ham bir `//` süzgeci tam da kanıtı silerdi.
Bu yüzden iddialar TIRNAKLI dize literaline bağlı — bir yorum tırnak
taşımaz.
"""

import pathlib
import re

KOK = pathlib.Path(__file__).resolve().parents[2]
PANEL = KOK / "web" / "rytho-admin" / "gorunumler" / "ortaklar.js"
MANIFEST = (KOK / "apps" / "mobile" / "android" / "app" / "src" / "main"
            / "AndroidManifest.xml")
UC = KOK / "backend" / "api" / "admin.py"


def _js_yorumsuz(metin: str) -> str:
    """Blok yorumları + SATIR BAŞINDAKİ satır yorumlarını atar."""
    metin = re.sub(r"/\*.*?\*/", "", metin, flags=re.S)
    return re.sub(r"(?m)^[ \t]*//.*$", "", metin)


def _xml_yorumsuz(metin: str) -> str:
    return re.sub(r"<!--.*?-->", "", metin, flags=re.S)


def _panel() -> str:
    return _js_yorumsuz(PANEL.read_text(encoding="utf-8"))


def _manifest_r_hostlari() -> list[str]:
    """`/r/` yol öneki için intent-filter'daki ana makineler."""
    kaynak = _xml_yorumsuz(MANIFEST.read_text(encoding="utf-8"))
    hostlar: list[str] = []
    for blok in re.findall(r"<intent-filter.*?</intent-filter>", kaynak, re.S):
        if not re.search(r'android:pathPrefix="/r/"', blok):
            continue
        hostlar += re.findall(r'android:host="([^"]+)"', blok)
    return hostlar


def test_panel_paylasilacak_tam_baglantiyi_gosteriyor():
    """Ürünün sattığı şey KOD değil BAĞLANTI: panel kodu gösterip bağlantıyı
    yöneticinin kafasında kurmasını bekleyemez (ölçülen şikâyet tam buydu).
    """
    panel = _panel()
    assert "'https://rytho.app/r/'" in panel, (
        "ortaklar.js artık tam ortak bağlantısının kökünü taşımıyor — panel "
        "yalnız kodu gösteriyorsa yönetici paylaşacağı adresi hiçbir yerde "
        "görmez")


def test_baglanti_kokunun_ana_makinesi_app_links_ile_ayni():
    """Farklı bir ana makineyle üretilen bağlantı KURULU uygulamada
    doğrudan açılmaz; tarayıcıda kalır ve iki ana makine aynı sayfayı
    sunduğu için hata SESSİZ olur. Bu yüzden iddia ölçülür.
    """
    eslesme = re.search(r"var BAGLANTI_KOKU = '([^']+)';", _panel())
    assert eslesme, "BAGLANTI_KOKU tek yerde duran bir sabit olmalı"
    kok = eslesme.group(1)
    parca = re.match(r"^https://([^/]+)(/[^?#]*)$", kok)
    assert parca, f"bağlantı kökü mutlak https adresi değil: {kok}"
    host, yol = parca.group(1), parca.group(2)
    assert yol == "/r/", f"bağlantı yolu /r/ değil: {yol}"
    assert _manifest_r_hostlari() == [host], (
        "panelin ürettiği ortak bağlantısının ana makinesi ile "
        "AndroidManifest'teki /r/ intent-filter ana makineleri ayrıştı: "
        f"panel={host} manifest={_manifest_r_hostlari()}")


def test_baglanti_sayfanin_kendi_adresinden_kurulmuyor():
    """Panel `rhytoai.web.app` üstünden de açılabiliyor. Bağlantı
    `location.origin`den kurulsa o oturumda üretilen her ortak bağlantısı
    kurulu uygulamada açılmayan bir bağlantı olurdu.
    """
    assert "location.origin" not in _panel(), (
        "ortak bağlantısı sayfanın kendi ana makinesinden kuruluyor olabilir")


def test_ortagin_giris_adresi_panelde_yaziyor_ve_gercekten_var():
    """Ortak panosu üründe hiçbir yerden linklenmiyor (bilinçli), yani adres
    ELDEN veriliyor. Panel onu yazmazsa ortağın girebileceği bir kapı yok.
    """
    eslesme = re.search(r"var ORTAK_PANO_ADRESI = '([^']+)';", _panel())
    assert eslesme, "ortağın giriş adresi panelde tek bir sabitte durmalı"
    adres = eslesme.group(1)
    parca = re.match(r"^https://[^/]+(/.*)$", adres)
    assert parca, f"giriş adresi mutlak https adresi değil: {adres}"
    yol = parca.group(1).strip("/")
    # Adresin karşılığı gerçekten yayınlanan bir sayfa olmalı: klasör
    # taşınırsa panel var olmayan bir adres dağıtmaya devam ederdi.
    assert (KOK / "web" / yol / "index.html").is_file(), (
        f"panel {adres} adresini veriyor ama web/{yol}/index.html yok")


def test_erisim_ucu_owner_kapisinin_arkasinda():
    """Panelde düğmeyi gizlemek YETMEZ: claim basmak bir yetki değişikliği
    ve tek gerçek kapı sunucudadır. Panel bu uca POST ediyorsa uç
    `require_owner` taşımak zorunda.
    """
    assert "'/access'" in _panel(), (
        "panel ortak erişim ucuna artık POST etmiyor — erişim yalnız komut "
        "satırından basılabilir hâle dönmüş olabilir")
    kaynak = UC.read_text(encoding="utf-8")
    yer = kaynak.find('@router.post("/partners/{partner_id}/access")')
    assert yer >= 0, "erişim ucu admin.py'de bulunamadı"
    imza = kaynak[yer:yer + 400]
    assert "require_owner" in imza, (
        "ortak erişimi ucu owner kapısını kaybetmiş: support rolü başka bir "
        "hesaba ortaklık claim'i basabilir")
