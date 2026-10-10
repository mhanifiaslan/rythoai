# -*- coding: utf-8 -*-
r"""Backend (pytest) bekçilerinin mutasyon sınaması — bir workflow çıktısındaki
her ajanın `yeni_bekciler` listesini BEN de koşturuyorum (mutasyon_d0.py'nin
genelleştirilmiş hâli: çıktı dosyası ve ajan adları argümandan).

Kullanım: python mutasyon_backend.py <workflow_output.json> [ajan,ajan,...]

Her mutasyon: dosyayı BAYT oku, tek değişim uygula, ilgili pytest düğümünü
koştur, KIRMIZI bekle, bayt birebir geri yaz, SHA-256 doğrula.

Ajan kayıtlarındaki iki serbestlik tolere edilir: test kimliğine eklenen
"(… parametreli)" notu kesilir; `mutasyon_yeni` "(boş" ile başlıyorsa parça
silinir. Çapa bulunamayan mutasyon KOŞMAZ ve raporda "ÇAPA YOK" olarak
görünür — elle bakılır, sessizce geçilmez.
"""
import hashlib, io, json, re, subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')

# Depo köküne göre: betik tools/ altında yaşar, makineye bağlı yol yok.
# Yorumlayıcı: betiği koşturan python (backend/.venv ile çağrılır).
import pathlib
KOK = str(pathlib.Path(__file__).resolve().parents[1]).replace(chr(92), '/')
PY = sys.executable

cikti = sys.argv[1]
ajanlar = sys.argv[2].split(',') if len(sys.argv) > 2 else None
d = json.load(io.open(cikti, encoding='utf-8', errors='replace'))['result']


def mutlak(yol):
    yol = yol.replace(chr(92), '/')
    return yol if yol[1:3] == ':/' else f'{KOK}/{yol}'


def test_dugumu(test):
    # "backend/tests/x.py::ad[param] (15 sayfaya parametreli)" → "tests/x.py::ad[param]"
    # pytest backend/ icinden kosuyor; ajanlar yolu depo kokunden yaziyor.
    t = re.split(r'\s+\(', test.strip(), maxsplit=1)[0].strip()
    return t[len('backend/'):] if t.startswith('backend/') else t


def kos(test):
    p = subprocess.run([PY, '-m', 'pytest', '-q', '-p', 'no:cacheprovider',
                        '--runxfail', test],
                       cwd=KOK + '/backend', capture_output=True, text=True,
                       encoding='utf-8', errors='replace')
    return p.returncode, (p.stdout or '')[-400:]


sorun, toplam = [], 0
for ajan, r in d.items():
    if ajanlar and ajan not in ajanlar:
        continue
    if not isinstance(r, dict) or 'yeni_bekciler' not in r:
        continue
    for b in r['yeni_bekciler']:
        toplam += 1
        ad = f"{ajan}:{b['test'].split('::')[-1][:50]}"
        if b['mutasyon_dosya'].startswith('(bellek'):
            # Ajan "diske mutasyon yok" diyor: bu bir olcum DEGIL, beyan —
            # raporda ayri gorunsun, sorun sayilmasin ama sayiya da girmesin.
            toplam -= 1
            print(f'{ad:58s} AJAN BEYANI (diske mutasyon yok) — olcum degil'); continue
        yol = mutlak(b['mutasyon_dosya'])
        try:
            ham = open(yol, 'rb').read()
        except OSError:
            print(f'{ad:58s} DOSYA YOK ({b["mutasyon_dosya"]})'); sorun.append(ad); continue
        once_sha = hashlib.sha256(ham).hexdigest()
        metin = ham.decode('utf-8')
        eski = b['mutasyon_eski']
        yeni = b['mutasyon_yeni']
        if yeni.startswith(('(boş', '(bos', '(satır silindi', '(satir silindi')):
            yeni = ''
        # Ajan kayitlarindaki serbestlikler: literal "\n" (ters bolu + n),
        # capanin sonuna eklenmis "(aciklama)" notu.
        if eski not in metin:
            aday = eski.replace(chr(92) + 'n', chr(10))
            aday = re.sub(r'\s+\([^()]*\)\s*$', '', aday)
            if aday in metin:
                eski = aday
                yeni = re.sub(r'\s+\([^()]*\)\s*$', '', yeni.replace(chr(92) + 'n', chr(10)))
        if eski not in metin:
            print(f'{ad:58s} ÇAPA YOK ({b["mutasyon_dosya"]})'); sorun.append(ad); continue
        io.open(yol, 'w', encoding='utf-8', newline='').write(
            metin.replace(eski, yeni, 1))
        try:
            kod, kuyruk = kos(test_dugumu(b['test']))
        finally:
            open(yol, 'wb').write(ham)
        sonra_sha = hashlib.sha256(open(yol, 'rb').read()).hexdigest()
        geri = 'BAYT BIREBIR' if sonra_sha == once_sha else 'GERI YAZIM BOZUK!'
        if kod == 0:
            print(f'{ad:58s} YESIL KALDI — bekci kor!  {geri}'); sorun.append(ad)
        elif kod in (1,):
            print(f'{ad:58s} KIRMIZI (bekci tuttu)  {geri}')
        else:
            print(f'{ad:58s} pytest kod {kod} (toplama hatasi?)  {geri}')
            print('   ', kuyruk.replace(chr(10), ' | ')[-300:])
            sorun.append(ad)
        if geri != 'BAYT BIREBIR':
            sorun.append(ad + ' GERI')

print()
if sorun:
    print(f'{len(sorun)}/{toplam} SORUNLU:', sorun)
    sys.exit(1)
print(f'{toplam} MUTASYONUN HEPSI KIRMIZI DONDU, hepsi bayt birebir geri yazildi.')
