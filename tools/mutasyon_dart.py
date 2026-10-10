# -*- coding: utf-8 -*-
r"""Flutter bekçilerinin mutasyon sınaması — bir workflow çıktısındaki
(mutasyon_dosya, eski, yeni, test) listesini BEN de koşturuyorum.

Kullanım: python mutasyon_dart.py <workflow_output.json> [ajan,ajan,...]

Her mutasyon: dosyayı BAYT oku, tek değişim uygula, ilgili test DOSYASINI
koştur (`flutter test test/x.dart`), KIRMIZI bekle, bayt birebir geri yaz,
SHA-256 doğrula. Dart tarafında test adı seçimi (--plain-name) Türkçe
karakterlerde güvenilir değil; dosya düzeyi yeter — bir mutasyon aynı
dosyadaki başka bir testi düşürürse o da "bekçi tuttu" sayılır ve
raporda görünür.
"""
import hashlib, io, json, re, subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')

# Depo köküne göre: betik tools/ altında yaşar, makineye bağlı yol yok.
import pathlib, shutil
KOK = str(pathlib.Path(__file__).resolve().parents[1] / 'apps' / 'mobile').replace(chr(92), '/')
# flutter PATH'te olmayabilir (Windows'ta C:/flutter/bin); önce PATH, sonra bilinen yer.
FLUTTER = shutil.which('flutter') or shutil.which('flutter.bat') or 'C:/flutter/bin/flutter.bat'

cikti = sys.argv[1]
ajanlar = sys.argv[2].split(',') if len(sys.argv) > 2 else None
d = json.load(io.open(cikti, encoding='utf-8', errors='replace'))['result']


def mutlak(yol):
    yol = yol.replace('\\', '/')
    if yol[1:3] == ':/':
        return yol
    if yol.startswith('apps/mobile/'):
        yol = yol[len('apps/mobile/'):]
    return f'{KOK}/{yol}'


def test_dosyasi(test):
    # "test/x.dart :: ad" | "test/x.dart::ad" | "x_test.dart" → test/x.dart
    m = re.search(r'(test/[\w/]+\.dart)', test.replace('\\', '/'))
    if m:
        return m.group(1)
    m = re.search(r'([\w]+_test\.dart)', test)
    return f'test/{m.group(1)}' if m else None


def kos(dosya):
    p = subprocess.run([FLUTTER, 'test', '--no-pub', dosya], cwd=KOK,
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return p.returncode


sorun, toplam = [], 0
for ajan, r in d.items():
    if ajanlar and ajan not in ajanlar:
        continue
    if not r:
        print(f'{ajan}: sonuc YOK'); continue
    for b in r['yeni_bekciler']:
        toplam += 1
        ad = f"{ajan}:{b['test'].split('::')[-1].strip()[:46]}"
        yol = mutlak(b['mutasyon_dosya'])
        dosya = test_dosyasi(b['test'])
        if not dosya:
            print(f'{ad:54s} TEST DOSYASI COZULEMEDI ({b["test"]})'); sorun.append(ad); continue
        try:
            ham = open(yol, 'rb').read()
        except FileNotFoundError:
            print(f'{ad:54s} DOSYA YOK ({yol})'); sorun.append(ad); continue
        once_sha = hashlib.sha256(ham).hexdigest()
        metin = ham.decode('utf-8')
        eski, yeni = b['mutasyon_eski'], b['mutasyon_yeni']
        if yeni.startswith(('(boş', '(bos', '(satır silindi', '(satir silindi')):
            yeni = ''
        # Ajan kayitlarindaki serbestlikler (backend harness'iyla ayni):
        # literal "\n" (ters bolu + n) gercek satir sonu demek; capanin
        # sonuna eklenmis "(aciklama)" notu capanin parcasi degil.
        if eski not in metin:
            # Dosya CRLF ise literal "\n" gercekte "\r\n"dir (dogum_formu.dart'ta
            # olculdu: 47/48 sonra tek "ÇAPA YOK" bu yuzdendi).
            satir_sonu = chr(13) + chr(10) if chr(13) in metin else chr(10)
            aday = re.sub(r'\s+\([^()]*\)\s*$', '', eski.replace(chr(92) + 'n', satir_sonu))
            if aday in metin:
                eski = aday
                yeni = re.sub(r'\s+\([^()]*\)\s*$', '', yeni.replace(chr(92) + 'n', satir_sonu))
        if eski not in metin:
            print(f'{ad:54s} ÇAPA YOK ({b["mutasyon_dosya"]})'); sorun.append(ad); continue
        io.open(yol, 'w', encoding='utf-8', newline='').write(
            metin.replace(eski, yeni, 1))
        kod = kos(dosya)
        open(yol, 'wb').write(ham)
        geri = hashlib.sha256(open(yol, 'rb').read()).hexdigest() == once_sha
        hukum = 'KIRMIZI (bekci tuttu)' if kod != 0 else 'YESIL -> KOR BEKCI'
        if kod == 0: sorun.append(ad)
        if not geri: sorun.append(ad + ' [geri yazim]')
        print(f'{ad:54s} {hukum:22s} {"BAYT BIREBIR" if geri else "GERI YAZIM BOZUK"}')
        sys.stdout.flush()

print()
if sorun:
    print(f'SORUNLU ({len(sorun)}/{toplam}):', ', '.join(sorun)); sys.exit(1)
print(f'{toplam} MUTASYONUN HEPSI KIRMIZI DONDU, hepsi bayt birebir geri yazildi.')
