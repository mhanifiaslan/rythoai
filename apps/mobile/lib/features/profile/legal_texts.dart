/// Hukuki metinler (gizlilik politikası ve kullanım şartları), dile göre.
///
/// Bu metinler ÜRÜNÜN BUGÜNKÜ HÂLİNE göre yazılmıştır; eski sürümden birebir
/// çevrilmemiştir. Eski metin artık var olmayan özellikleri (yüz fotoğrafı
/// analizi, gönderi akışı, takip ilişkileri, birebir mesajlaşma) anlatıyordu
/// ve buna karşılık yeni veri kategorilerini (sohbetten damıtılan kullanıcı
/// hafızası, abonelik durumu, arkadaş katmanı) hiç kapsamıyordu. Yanlış
/// beyan, eksik beyandan daha büyük bir uyum riski.
///
/// UYARI: Bunlar mühendislik tarafından hazırlanmış taslaklardır. Yayın
/// öncesi KVKK/GDPR açısından bir hukukçu tarafından gözden geçirilmelidir.
library;

/// (başlık | null, gövde) çiftleri — başlıksız girdiler düz paragraftır.
typedef LegalSections = List<(String?, String)>;

/// Gizlilik politikasının tarihi. İki kopya (uygulama içi + `web/legal/`)
/// aynı günü göstermek ZORUNDA: 2026-10-02'ye kadar uygulama "2 Ağustos",
/// web "5 Ağustos" diyordu ve metinleri de ayrışmıştı — webde "Abonelik ve
/// tek cihaz" ile "Bildirimler" bölümleri hiç yoktu. Kullanıcı hangi kopyayı
/// okuduğuna göre farklı bir beyan görüyordu; iki tarih bunu görünür kılmak
/// yerine gizliyordu. Metin bu turda değiştiği için tarih de ileri alındı:
/// değişmiş bir politikayı eski tarihle sunmak yanlış beyandır. (22 Ekim:
/// Mac'in yapay zeka onayı metniyle Windows'un bildirim metni birleşti —
/// iki yayımlanmış sürümden de farklı bir politika.)
const String kLegalLastUpdatedTr = '22 Ekim 2026';
const String kLegalLastUpdatedEn = '22 October 2026';

/// Kullanım şartlarının tarihi gizlilik politikasından AYRI tutulur: ortaklık
/// programı maddesi yalnız şartlara eklendi, politika metni değişmedi. Tek
/// ortak sabit kullanılsaydı bu ekleme, değişmemiş bir politikayı da
/// "güncellenmiş" diye gösterirdi — ölçülmeyen bir beyan.
const String kTermsLastUpdatedTr = '27 Eylül 2026';
const String kTermsLastUpdatedEn = '27 September 2026';
const String kLegalContact = 'aslan.mh@gmail.com';

// ---------------------------------------------------------------------------
// Gizlilik Politikası — Türkçe
// ---------------------------------------------------------------------------

const LegalSections kPrivacyPolicyTr = [
  (
    null,
    'Son güncelleme: $kLegalLastUpdatedTr. Bu politika, Rytho\'yu kullanırken '
        'hangi verileri neden işlediğimizi, kimlerle paylaştığımızı ve '
        'haklarını açıklar.'
  ),
  (
    'Hesap bilgileri',
    'Google ile veya e-posta ile giriş yaptığında adın, e-posta adresin ve '
        'varsa profil fotoğrafın işlenir. Amaç: hesabını oluşturmak ve '
        'oturumunu doğrulamak. Hukuki dayanak: sözleşmenin ifası.\n\n'
        'Profil fotoğrafını DEĞİŞTİRİRSEN: seçtiğin fotoğraf galerinden '
        'alınır, kırpılır ve bulut depolamamıza (Google Cloud Storage) '
        'YÜKLENİR. Yani bu fotoğraf telefonunda kalmaz — sunucuda saklanır '
        've arkadaşlarının gördüğü kartta görünür. Yüz okumadaki görüntüden '
        'farkı budur: orada görüntü hiç yüklenmez, burada yüklenir. '
        'Fotoğrafı istediğin an değiştirebilir, hesabını silerek '
        'kaldırabilirsin.'
  ),
  (
    'Telefon numarası (isteğe bağlı)',
    'Telefonunu doğrularsan numaran SMS ile doğrulanır ve kimlik '
        'sağlayıcımızda (Firebase Authentication) hesabına bağlanır. '
        'Sunucularımızda numaranın kendisi DEĞİL, geri döndürülemez bir '
        'özeti (SHA-256) tutulur; bu özet yalnızca bir numaranın tek hesaba '
        'bağlı kalmasını sağlamak ve — açarsan — rehber eşleşmesinde '
        'kullanılır. Numaranı doğrulamak zorunlu değildir; doğrulamazsan '
        'uygulamanın geri kalanı aynen çalışır.'
  ),
  (
    'Abonelik ve tek cihaz',
    'Rytho+ aboneliği aynı anda tek cihazda kullanılır. Bunu sağlamak için '
        'cihazında rastgele üretilmiş bir tanımlayıcı saklanır ve '
        'isteklerinle birlikte gönderilir. Bu tanımlayıcı donanım kimliği '
        'değildir, reklam veya takip amacıyla kullanılmaz; uygulamayı silip '
        'yeniden kurduğunda değişir.'
  ),
  (
    'Doğum verisi',
    'Doğum tarihin, saatin ve şehrin; natal harita, BaZi ve günlük okuma '
        'hesaplamaları için işlenir ve hesabında saklanır. Bu üçlü hassas bir '
        'kombinasyondur: hiçbir başka kullanıcı bu verilere erişemez. '
        'Arkadaşların yalnızca senin görünür kıldığın türetilmiş bilgileri '
        '(adın, kullanıcı adın, güneş burcun, açtıysan serin) görebilir. '
        'Doğum verisi reklam veya profilleme amacıyla üçüncü taraflarla '
        'paylaşılmaz ve satılmaz.'
  ),
  (
    'Eklediğin kişiler',
    'Eşinin, çocuğunun ya da bir yakınının doğum bilgilerini eklersen bu '
        'kayıt yalnızca senin hesabının altında tutulur: başka hiçbir '
        'kullanıcı erişemez, arkadaş listelerinde görünmez, rehber '
        'eşleşmesine girmez ve hiçbir dizinde aranamaz.\n\n'
        'Kişi kaydında ad TUTULMAZ — verdiğin etiket yalnızca bu telefonda '
        'saklanır; sunucudaki kayıtta duran tek kimlik işareti seçtiğin '
        'yakınlık türüdür (eş, çocuk, ebeveyn...) ve Rytho o kişiden adıyla '
        'değil "eşin", "çocuğun" diye söz eder.\n\n'
        'Tek istisna sohbettir: bir mesajda adı SEN yazarsan (ya da "@" ile '
        'seçersen) o ad mesajın parçası olur; mesaj, diğer mesajlar gibi konu '
        'arşivine girer ve yanıt üretimi için işlenir.\n\n'
        'Bu kişiler uygulamayı kullanmadığı için rızaları alınamıyor. Bu '
        'yüzden veriyi yalnızca sen görürsün, dilediğin an silebilirsin ve '
        'hesabını sildiğinde bu kayıtlar da birlikte silinir. Bilgileri '
        'girerken o kişinin bilgisi ve isteği dahilinde hareket etmek '
        'senin sorumluluğundadır.'
  ),
  (
    'Sohbet ve kullanıcı hafızası',
    'Sohbet mesajların yanıt üretmek üzere yapay zeka sağlayıcımıza '
        'iletilir.\n\n'
        'Konuşmaların kaldığın yerden sürebilmesi için mesajların konu konu '
        'hesabına bağlı olarak SAKLANIR. Bu arşiv yalnızca sana görünür; '
        'başka kullanıcılara gösterilmez, reklam veya profilleme için '
        'kullanılmaz. Bir konuyu istediğin an silebilirsin; 30 gün boyunca '
        'hiç açılmayan konular mesajlarıyla birlikte otomatik silinir. '
        'Hesabını sildiğinde tüm konuşmaların da silinir.\n\n'
        'Ayrıca seni sonraki konuşmalarda daha iyi anlayabilmek için '
        'konuşmadan kısa ve yapılandırılmış olgular damıtılır (örneğin '
        'tekrar eden bir tema, dile getirdiğin bir hedef, tercih ettiğin '
        'anlatım tonu). Bu olgular yalnızca kapalı bir kategori kümesine '
        'oturur, hesabına bağlı olarak saklanır ve başka kullanıcılara '
        'gösterilmez. Sağlık durumu, tanı veya ilaç bilgisi bu kapsamda '
        'TUTULMAZ.'
  ),
  (
    'Günlüğün',
    'Uygulama içinde tuttuğun günlük notları serbest metindir ve ne '
        'yazacağına yalnız sen karar verirsin. Notlar hesabına bağlı olarak '
        'sunucuda saklanır ve iki işe yarar: sana geçmişini göstermek, ve '
        'sorduğunda yorumunu bugünkü hâline göre kurmak. Bunun için notun '
        'yapay zeka sağlayıcımıza (Google Gemini) iletilebilir. Notları tek '
        'tek silebilirsin; hesabını silersen hepsi gider. Sağlık durumu, '
        'tanı ya da ilaç bilgisi yazmamanı öneririz — bunlar bizim '
        'işleyebileceğimiz veri türleri değildir.'
  ),
  (
    'Geri bildirim',
    'Profil → Geri bildirim ile bize yazdığın metin, hesabınla birlikte '
        'saklanır. Metnin yanında sorunun tekrar üretilebilmesi için '
        'uygulama sürümü, platform, dil ve o sırada bulunduğun ekranın adı '
        'da kaydedilir. Bu kayıtları yalnız uygulama yöneticisi okur; '
        'yanıtlarsak yanıt sana bildirim olarak gelir. Hesabını sildiğinde '
        'gönderdiğin geri bildirimler de silinir.'
  ),
  (
    'Ölçüm ve çökme kayıtları',
    'Uygulama çökerse Firebase Crashlytics\'e teknik bir kayıt gider: hata '
        'izi, cihaz modeli, işletim sistemi ve uygulama sürümü. Bu kayıtta '
        'adın, e-postan, doğum verin ya da yazdığın hiçbir metin bulunmaz.'
        '\n\n'
        'Uygulamanın hangi ekranlarının kullanıldığını görmek için Firebase '
        'Analytics kullanılır. Olaylar dar kategorilerdir (hangi rapor '
        'üretildi, satın alma akışı nerede kaldı, bildirim izni verildi mi); '
        'kişisel veri taşımazlar. Uygulama reklam göstermez ve Android\'in '
        'reklam kimliğini (Advertising ID) KULLANMAZ: bu izin uygulama '
        'paketinden çıkarıldı, olaylar yalnızca uygulama kurulumuna özel '
        'bir kimlikle eşlenir.\n\n'
        'Ayrıca yapay zeka çağrılarının maliyetini takip edebilmek için '
        'sunucuda teknik bir kullanım kaydı tutulur: hangi özellik, hangi '
        'model, kaç kelime birimi, ne kadar sürdü. Bu kayıtta sorunun ya da '
        'cevabın METNİ yoktur. Hesabını sildiğinde bu kayıtlar da silinir.'
  ),
  (
    'Ortak bağlantısı tıklamaları',
    'Rytho\'ya bir ortaklık bağlantısıyla geldiysen, o bağlantının '
        'açılması ortağın kodu için GÜN BAŞINA bir sayacı bir artırdı. '
        'Sayılan şey TIKLAMADIR, kişi değildir: bu ölçümün KALICI kaydına '
        'IP adresi, tarayıcı bilgisi, çerez ve kimlik yazılmaz — orada sana '
        'ait tek bir bayt yoktur. Geçici tek istisna bu uca özel değil: '
        'kötüye kullanımı sınırlayan kota katmanı, kimliksiz her istekte '
        'olduğu gibi IP adresini yalnız sunucu belleğinde ve birkaç '
        'dakikalık bir pencerede sayaç anahtarı olarak tutar; hiçbir kalıcı '
        'yere gitmez. Bunun sonucu olarak tekil ziyaretçi sayısı ÖLÇÜLEMEZ ve '
        'ölçülmüyor; tekillik ancak bir işaretle sayılabilirdi ve o işaret '
        'kişisel veri olurdu. Ortağın panosunda bu sayı "tıklama" diye '
        'görünür.'
  ),
  (
    'Yüz okuma',
    'Yüz okuma iki yolla çalışır: canlı kamera ya da galerinden seçtiğin '
        'bir fotoğraf. İki yolda da GÖRÜNTÜ TELEFONUNDAN ÇIKMAZ: yüz '
        'hatlarının tespiti de, saç çizgisinin bulunması da tamamen '
        'cihazında, çevrimdışı çalışan modellerle yapılır. Görüntü '
        'sunucularımıza gönderilmez ve buluta yüklenmez. Kamera yolunda '
        'fotoğraf hiç çekilmez, kare bellekte işlenir ve işlem bittiği anda '
        'silinir; galeri yolunda fotoğrafın uygulamaya verilen kopyası '
        'bellekte işlenir ve işlem bitince silinir — asıl fotoğrafına '
        'dokunulmaz.\n\n'
        'Sunucuya yalnızca yüz hatlarından TÜRETİLMİŞ ORANLAR gider (örneğin '
        'alın yüksekliğinin yüz yüksekliğine oranı). Bu sayılar iki ondalığa '
        'yuvarlanır ve kişiyi tanımaya yaramaz: "0,34" değeri milyonlarca '
        'insanda aynıdır. Yüz tanıma, kimlik doğrulama veya kişi eşleştirme '
        'YAPILMAZ; bu sayılardan yüzün geri üretilmesi mümkün değildir.\n\n'
        'Oranlar ve üretilen okuma hesabına bağlı olarak saklanır, başka '
        'kullanıcılara gösterilmez. Bu özellik ayrı ve açık rızanla '
        'çalışır; rızanı Profil > Gizlilik bölümünden istediğin an geri '
        'alabilirsin. Geri aldığında oranların ve o oranlardan üretilmiş '
        'okumalar silinir.\n\n'
        'Yüz okuma bir eğlence ve kendini tanıma aracıdır. Sağlık, işe alım, '
        'kredi, sigorta ya da benzeri hiçbir kararda kullanılmaz ve '
        'kullanılmamalıdır.'
  ),
  (
    'Arkadaş katmanı',
    'Kullanıcı adın, karşılıklı onaylı arkadaşlıkların ve gönderdiğin hazır '
        'tepkiler saklanır. Uygulamada kullanıcılar birbirine serbest metin '
        'gönderemez; yalnızca önceden tanımlı bir tepki kümesinden seçim '
        'yapılabilir.\n\n'
        'Rehberine varsayılan olarak ERİŞİLMEZ. "Rehberimden arkadaş öner" '
        'ayarını açarsan rehberindeki telefon numaraları CİHAZINDA geri '
        'döndürülemez özetlere (SHA-256) çevrilir ve yalnızca bu özetler '
        'eşleştirme için sunucuya gönderilir. Kişilerin adları CİHAZINDA '
        'okunur — listede kimin Rytho\'da olduğunu gösterebilmek için — ama '
        'ad, soyad ve başka hiçbir rehber alanı sunucuya GÖNDERİLMEZ. '
        'Özet listesi eşleştirme '
        'yapıldıktan sonra atılır, sunucuda saklanmaz. Eşleşme '
        'KARŞILIKLIDIR: yalnızca ikiniz de bu ayarı açtıysanız birbirinizi '
        'görürsünüz. Ayarı kapattığın an görünmez olursun.'
  ),
  (
    'Bildirimler',
    'Saat dilimin ve seçtiğin arayüz dili, bildirimi hiç açmasan da her '
        'oturum açılışında hesabına yazılır; cihazının bildirim kimliği '
        '(FCM token) ise yalnız bildirim iznini verdiysen alınabilir ve '
        'saklanır. Saat dilimi, bildirimin senin yerel sabahına denk gelmesi '
        'için gerekir; konum bilgin alınmaz, yalnızca cihazının bildirdiği '
        'saat dilimi adı (örneğin "Europe/Istanbul") kaydedilir. Bildirim '
        'metinleri sunucumuzda üretilir ve KİŞİYE ÖZELDİR: sabah okuması, '
        'öğle bildirimi ve akşam check-in sorusunun gövdesi senin doğum '
        'haritandan çıkan o güne özgü sinyalden üretilir. Sabah ve öğle '
        'bildirimindeki kişisel cümleyi ve akşam sorusunu yapay zeka yazar; '
        'bu yalnız yapay zeka iznin varsa olur (bkz. "Yapay zeka ile '
        'işleme"). İznin yoksa sabah ve öğle bildiriminde aynı sinyalin '
        'teknik satırı gider, akşam sorusu hiç gönderilmez. O gün haritandan '
        'gönderilecek bir sinyal çıkmazsa yerine burcuna göre hazırlanan '
        'ortak metin gider; seri hatırlatıcısı ve arkadaş tepkisi bildirimi '
        'ise sabit şablondur (serinin kaç gün olduğu, tepkiyi gönderenin '
        'adı). Akşamki Çevrem notu, Çevrem\'e eklediğin bir kişiyle ya da '
        'bir arkadaşınla aranızda o gün ölçülen bir geçişi anlatır; '
        'başlığında o kişinin görünen adı ya da ilişki etiketi yer alır. '
        'Uygulamayı 3, 10 ve 30 gün açmadığında birer kez hatırlatma gider '
        've sonra susar; 10. gün hatırlatması Çevrem\'indeki bir kişiye '
        'değinebilir. Sohbet geçmişin bildirim üretiminde kullanılmaz. '
        'Bildirim türlerini ve sessiz saatleri Profil > Bildirimler '
        'bölümünden kapatabilir, cihaz ayarlarından tümüyle kaldırabilirsin. '
        'Uygulamayı sildiğinde bildirim kimliği geçersizleşir ve ilk '
        'başarısız gönderimde kaydımızdan silinir.'
  ),
  (
    'Abonelik',
    'Satın alma işlemi cihazının uygulama mağazası üzerinden yürütülür; '
        'ödeme bilgilerini biz görmeyiz ve saklamayız. Abonelik durumunu '
        '(aktif/pasif, dönem sonu) RevenueCat aracılığıyla alır ve hesabına '
        'bağlı olarak saklarız.'
  ),
  (
    'Yapay zeka ile işleme',
    'Kişisel okumalar (günlük okuma, natal rapor, BaZi, Yıl Haritası, İç '
        'Takvim, Doğum Heksagramı, I Ching, ilişki okumaları), sohbet '
        'yanıtları, yüz okuması yorumu, sinyal kartlarındaki ve takvim '
        'olaylarındaki yorum satırları, sabah ve öğle bildirimindeki kişisel '
        'cümleler ve akşam check-in sorusu üçüncü taraf bir yapay zeka '
        'hizmetiyle — Google LLC\'nin Gemini API\'siyle — üretilir. Bu '
        'özellikler için uygulama içinde AYRI ve açık iznini isteriz. İzin '
        'vermezsen bu özellikler kapalı kalır ve aşağıdaki veriler '
        'Gemini\'ye gönderilmez; doğum haritan, gökyüzü, takvim ve arkadaş '
        'özellikleri çalışmaya devam eder.\n\n'
        'İzin verdiğinde, kullandığın özelliğe göre şunlar Google\'a '
        'gönderilir: doğum haritandan hesaplanan bilgiler (gezegen '
        'konumları, evler, açılar, transitler, BaZi sütunları; Yıl Haritası '
        'okumasında güneş dönüşü tarihi ve şehir adları); sohbet mesajların '
        've konuşmanın son kısmı; I Ching\'e sorduğun soru; sohbetlerden '
        'çıkarılan kısa notlar, ruh hâli seyrin ve son günlük notların; '
        'adın (ilişki okumalarında); arkadaşlarının görünen adı ve burcu '
        '(ilişki okumalarında ve sohbette); eklediğin kişilerin yakınlık türü ve haritası (onlara '
        'verdiğin isim telefonunda kalır); yüz okumasında yüz hatlarından '
        'türetilen oranlar (fotoğraf gönderilmez). Sohbette bir mesaja '
        'yazdığın her şey — bir ad dahil — mesajın parçası olarak gider.'
        '\n\n'
        'Bu veriler yalnız istediğin yorumu ya da cevabı üretmek için '
        'gönderilir. Genel burç yorumları ve burca göre hazırlanan bildirim '
        'satırları da yapay zekayla yazılır ama bunlara kişisel verin '
        'katılmaz.\n\n'
        'İznini istediğin an Profil > Gizlilik bölümünden geri alabilir, '
        'yeniden verebilirsin. Geri aldığın andan itibaren gönderim durur; '
        'daha önce üretilmiş okumalar ve sohbet geçmişin bu işlemle '
        'silinmez. Yorumlar içgörü amaçlıdır; tıbbi, hukuki veya finansal '
        'tavsiye değildir.'
  ),
  (
    'Alt işleyiciler',
    'Google LLC (Firebase Authentication, Cloud Firestore, Cloud Run, '
        'Gemini API) ve RevenueCat, Inc. (abonelik yönetimi). Veriler '
        'ağırlıklı olarak Google Cloud us-central1 bölgesinde işlenir; bu, '
        'verilerin Türkiye ve AB dışına aktarılması anlamına gelir.'
  ),
  (
    'Saklama süresi',
    'Hesap ve doğum verilerin hesabın var olduğu sürece saklanır. Yapay '
        'zeka yanıt önbelleği en fazla 30 gün tutulur. Hesabını sildiğinde '
        'verilerin kalıcı olarak silinir: doğum kaydın, sohbetlerin ve '
        'onlardan çıkarılan notlar, günlük girişlerin, eklediğin kişiler, '
        'arkadaşlıkların, kullanıcı adın, sana özel üretilmiş okumalar, '
        'yapay zeka kullanım kaydın, telefon doğrulama denemelerin ve bize '
        'gönderdiğin geri bildirimler.\n\n'
        'İki kayıt bilerek kalır. Satın alma ve iade kayıtların mali '
        'belgedir; vergi mevzuatı bunları beş yıl saklamamızı zorunlu '
        'kılar ve bu kayıtlar ürün, tutar ve tarihten ibarettir. '
        'Yöneticinin hesabın üzerinde yaptığı işlemlerin denetim izi de '
        'kalır; silinebilir olsaydı denetim izi olmazdı. Gönderdiğin '
        'şikayet kayıtları da başkalarının güvenliği için saklanır.'
  ),
  (
    'Haklarının kullanımı',
    'Verilerine erişme, düzeltme, silme, işlemeyi kısıtlama ve taşınabilirlik '
        'haklarına sahipsin. Hesabını uygulama içinden silebilirsin; '
        'dilersen $kLegalContact adresine de yazabilirsin. Talepler en geç '
        '30 gün içinde sonuçlandırılır.'
  ),
  (
    'Yaş sınırı',
    'Rytho 13 yaşın altındakilere yönelik değildir ve bilerek bu yaş grubundan '
        'veri toplamayız.'
  ),
  (
    'İletişim',
    'Gizlilikle ilgili sorular için: $kLegalContact'
  ),
];

// ---------------------------------------------------------------------------
// Kullanım Şartları — Türkçe
// ---------------------------------------------------------------------------

const LegalSections kTermsOfUseTr = [
  (
    null,
    'Son güncelleme: $kTermsLastUpdatedTr. Rytho\'yu kullanarak bu şartları '
        'kabul etmiş olursun.'
  ),
  (
    'İçgörü amaçlıdır',
    'Tüm okumalar, raporlar ve sohbet yanıtları kişisel içgörü amaçlıdır. '
        'Hiçbir içerik tıbbi, hukuki, finansal veya psikolojik tavsiye '
        'değildir. Uygulama sağlık, hastalık, hamilelik, ölüm ve yatırım '
        'konularında öngörüde bulunmayı bilinçli olarak REDDEDER; bu tür '
        'kararlar için ilgili alanın uzmanına danış.'
  ),
  (
    'Astroloji hakkında dürüst not',
    'Gökyüzü hesaplamaları gerçek astronomik veriye dayanır (Swiss '
        'Ephemeris). Ancak bu konumlardan kişilik veya olay çıkarımı '
        'geleneksel bir yorum pratiğidir; bilimsel olarak doğrulanmış bir '
        'öngörü yöntemi değildir.'
  ),
  (
    'Hesap ve yaş sınırı',
    'Kullanım için hesap oluşturman gerekir ve en az 13 yaşında olmalısın. '
        'Hesap bilgilerinin güvenliğinden sen sorumlusun.'
  ),
  (
    'Abonelik',
    'Rytho+ aboneliği, dönem bitiminden en az 24 saat önce iptal edilmezse '
        'otomatik yenilenir. Ücretlendirme ve iptal cihazının uygulama '
        'mağazası hesabı üzerinden yürür. Deneme süresi sunulduysa, süre '
        'dolmadan iptal edersen ücret alınmaz.'
  ),
  (
    'Davranış kuralları',
    'Uygulamada kullanıcılar birbirine serbest metin gönderemez; etkileşim '
        'önceden tanımlı tepkilerle sınırlıdır. Buna rağmen rahatsız edici '
        'davranışla karşılaşırsan kullanıcıyı engelleyebilir ve şikayet '
        'edebilirsin. Hizmeti kötüye kullanan hesaplar kapatılabilir.'
  ),
  (
    'Fikri mülkiyet',
    'Uygulamanın tasarımı, yazılımı ve bilgi tabanı Rytho\'ya aittir. '
        'Efemeris hesaplarında Swiss Ephemeris (© Astrodienst AG) kullanılır. '
        'Şehir ve ülke verileri GeoNames\'ten (geonames.org) alınmıştır ve '
        'CC-BY 4.0 lisansıyla kullanılmaktadır.'
  ),
  (
    'Sorumluluk sınırı',
    'Hizmet "olduğu gibi" sunulur; kesintisiz veya hatasız çalışacağı '
        'garanti edilmez. Yorumlara dayanarak aldığın kararlardan Rytho '
        'sorumlu tutulamaz.'
  ),
  // Bu bölüm web'deki şartlarla (web/legal/kullanim.html §9) AYNI ANLAMI
  // taşımak zorunda: dört kopya var (bu dosya, markdown kaynağı ve iki HTML)
  // ve biri geride kalırsa hukuk metni sessizce çatallanır. Bekçi:
  // backend/tests/test_honesty.py::TestKullanimSartlariKopyalari.
  (
    'Ortaklık programı',
    'Rytho\'yu tanıtan kişi ve kurumlar için bir ortaklık programı '
        'yürütülür. Başvuru veya davet üzerine, kabulümüz ve ayrı bir '
        'ortaklık anlaşmasıyla katılınır; başvurmak tek başına katılım hakkı '
        'vermez. Ortağın paylaştığı bağlantı, bağlantıyı kullanan kişiye '
        'indirim veya ödül sağlamaz; fiyatlar herkes için aynıdır. Ortak, '
        'bağlantısı üzerinden gelen bir kullanıcının ilk Rytho+ aboneliği '
        'başına ödül kazanır; tutar ortaklık anlaşmasında belirlenir. Kredi '
        'paketleri, ücretsiz deneme, abonelik yenilemeleri ve mağaza test '
        '(sandbox) alımları ödül doğurmaz.'
  ),
  (
    null,
    'Hakediş, satın almadan 15 gün sonra kesinleşir; bu süre içinde iade, '
        'ödemenin tahsil edilememesi veya aboneliğin erken sona ermesi '
        'halinde iptal edilir. Ödül kişiye özeldir ve devredilemez; nakde '
        'çevrilme talebi anlaşmadaki ödeme eşiğine ulaşılmasına bağlıdır. '
        'Ortağın kendi kodunu kendi hesabında kullanması, ödül üretmek '
        'amacıyla sahte hesap açılması, yanıltıcı tanıtım ve istenmeyen '
        'toplu ileti (spam) programdan çıkarılma sebebidir; çıkarılma '
        'halinde henüz kesinleşmemiş hakedişler düşer. Kazanılan ödüle '
        'ilişkin vergi yükümlülükleri ortağa aittir. Program '
        'değiştirilebilir veya kapatılabilir; bu durumda kesinleşmiş '
        'hakedişler ödenir.'
  ),
  (
    'İletişim',
    'Sorular ve talepler için: $kLegalContact'
  ),
];

// ---------------------------------------------------------------------------
// Privacy Policy — English
// ---------------------------------------------------------------------------

const LegalSections kPrivacyPolicyEn = [
  (
    null,
    'Last updated: $kLegalLastUpdatedEn. This policy explains what data we '
        'process when you use Rytho, why we process it, who we share it with, '
        'and what rights you have.'
  ),
  (
    'Account information',
    'When you sign in with Google or e-mail we process your name, e-mail '
        'address and profile photo if you have one. Purpose: to create your '
        'account and verify your session. Legal basis: performance of a '
        'contract.\n\n'
        'If you CHANGE your profile photo: the photo you pick is taken from '
        'your gallery, cropped and UPLOADED to our cloud storage (Google '
        'Cloud Storage). That photo does not stay on your phone — it is '
        'stored on our servers and appears on the card your friends see. '
        'This is the difference from face reading: there the image is never '
        'uploaded, here it is. You can change it at any time, or remove it '
        'by deleting your account.'
  ),
  (
    'Phone number (optional)',
    'If you verify your phone, the number is confirmed via SMS and linked '
        'to your account by our identity provider (Firebase Authentication). '
        'Our servers store an irreversible digest (SHA-256) of the number, '
        'NOT the number itself; the digest is used only to keep one number '
        'bound to one account and — if you enable it — for contact '
        'matching. Verification is optional; without it, the rest of the '
        'app works unchanged.'
  ),
  (
    'Subscription and single device',
    'A Rytho+ subscription works on one device at a time. To enforce this, '
        'a randomly generated identifier is stored on your device and sent '
        'with your requests. It is not a hardware identifier, is never used '
        'for advertising or tracking, and changes if you reinstall the app.'
  ),
  (
    'Birth data',
    'Your date, time and city of birth are processed to calculate your natal '
        'chart, BaZi chart and daily readings, and are stored on your '
        'account. This combination is sensitive: no other user can access it. '
        'Friends only see derived information you have chosen to make visible '
        '(your name, username, sun sign, and your streak if you enable it). '
        'Birth data is never shared with third parties for advertising or '
        'profiling, and is never sold.'
  ),
  (
    'People you add',
    'If you add the birth details of your partner, your child or someone '
        'close to you, that record lives only under your account: no other '
        'user can reach it, it never appears in friend lists, it is never '
        'used for contact matching and it cannot be found in any directory.'
        '\n\n'
        'The person record itself holds NO name — the label you enter is '
        'kept on this phone only, and the only identifying field stored on '
        'the server is the relationship type you chose (partner, child, '
        'parent...); Rytho refers to them as "your partner" or "your '
        'child".\n\n'
        'Chat is the one exception: if YOU write their name in a message (or '
        'pick it with "@"), that name becomes part of the message, and the '
        'message enters your topic archive and is processed to generate a '
        'reply, like any other message.\n\n'
        'These people do not use the app, so their consent cannot be '
        'collected. That is why the data is visible only to you, can be '
        'deleted by you at any time, and is removed together with your '
        'account. Entering their details with their knowledge and agreement '
        'is your responsibility.'
  ),
  (
    'Chat and user memory',
    'Your chat messages are sent to our AI provider to generate a reply.\n\n'
        'So that conversations can continue where you left off, your '
        'messages ARE stored against your account, organised by topic. This '
        'archive is visible only to you; it is never shown to other users '
        'and never used for advertising or profiling. You can delete any '
        'topic at any time; topics untouched for 30 days are deleted '
        'automatically together with their messages. Deleting your account '
        'deletes all conversations.\n\n'
        'In addition, short structured facts are distilled from the '
        'conversation so that later conversations can understand you better '
        '— for example a recurring theme, a goal you mentioned, or the tone '
        'you prefer. These facts fit a closed set of categories, are stored '
        'against your account, and are never shown to other users. Health '
        'conditions, diagnoses and medication are explicitly NOT retained.'
  ),
  (
    'The friends layer',
    'We store your username, your mutually accepted friendships and the '
        'preset reactions you send. Users cannot send each other free text in '
        'this app; interaction is limited to a fixed set of reactions.\n\n'
        'By default we do NOT access your contacts. If you enable "Suggest '
        'friends from my contacts", the phone numbers in your address book '
        'are converted to irreversible digests (SHA-256) ON YOUR DEVICE and '
        'only those digests are sent for matching. Contact names are read ON '
        'YOUR DEVICE — so the list can show you who is on Rytho — but names '
        'and every other contact field are never TRANSMITTED. The digest '
        'list is '
        'discarded after matching and never stored on our servers. Matching '
        'is MUTUAL: you only see each other if you have both enabled the '
        'setting. Turning it off makes you invisible immediately.'
  ),
  (
    'Your journal',
    'The journal notes you keep in the app are free text and you alone '
        'decide what goes in them. Notes are stored on our servers tied to '
        'your account and serve two purposes: showing you your own history, '
        'and grounding a reading in where you are today when you ask for '
        'one. For that, a note may be sent to our AI provider (Google '
        'Gemini). You can delete notes one by one; deleting your account '
        'removes them all. We recommend not writing health conditions, '
        'diagnoses or medication — those are not data types we can process.'
  ),
  (
    'Feedback',
    'The text you send us through Profile → Feedback is stored together '
        'with your account. Alongside the text we record the app version, '
        'platform, language and the name of the screen you were on, so the '
        'problem can be reproduced. Only the app administrator reads these; '
        'if we reply, the reply reaches you as a notification. Deleting your '
        'account deletes the feedback you sent.'
  ),
  (
    'Measurement and crash logs',
    'If the app crashes, a technical record goes to Firebase Crashlytics: '
        'the stack trace, device model, operating system and app version. '
        'That record contains no name, e-mail, birth data or text you '
        'wrote.\n\n'
        'Firebase Analytics is used to see which screens are used. Events '
        'are narrow categories (which report was generated, where a purchase '
        'flow stopped, whether notification permission was granted); they '
        'carry no personal data. The app shows no ads and does NOT use '
        'Android\'s Advertising ID: that permission was removed from the '
        'app package, and events are tied only to an identifier specific '
        'to your app installation.\n\n'
        'We also keep a technical usage record on the server so we can track '
        'the cost of AI calls: which feature, which model, how many token '
        'units, how long it took. That record contains no TEXT of your '
        'question or the answer. Deleting your account deletes these too.'
  ),
  (
    'Affiliate link clicks',
    'If you came to Rytho through an affiliate link, opening that link '
        'incremented a PER-DAY counter on that partner\'s code by one. What '
        'is counted is the CLICK, not the person: the PERSISTENT record of '
        'this measurement holds no IP address, no browser information, no '
        'cookie and no identifier — not a single byte about you is in it. '
        'The one transient exception is not specific to this endpoint: the '
        'rate-limiting layer that keeps the endpoint from being abused holds '
        'the IP address as a counter key, as it does for every '
        'unauthenticated request, in server memory only and for a window of '
        'a few minutes; it reaches no durable store. As a direct consequence '
        'unique visitors CANNOT be measured, and are not: uniqueness would '
        'require a marker, and that marker would be personal data. The '
        'partner\'s dashboard shows this number as "clicks".'
  ),
  (
    'Face reading',
    'Face reading works in two ways: the live camera, or a photo you pick '
        'from your gallery. In BOTH cases the IMAGE NEVER LEAVES YOUR '
        'PHONE: facial landmark detection and the hairline measurement run '
        'entirely on your device, with offline models. The image is not '
        'sent to our servers and not uploaded to any cloud. On the camera '
        'path no photo is ever taken — the frame is processed in memory and '
        'discarded as soon as the measurement finishes; on the gallery path '
        'the copy handed to the app is processed in memory and deleted when '
        'the measurement finishes — your original photo is untouched.\n\n'
        'Only DERIVED RATIOS are sent to the server (for example, forehead '
        'height as a fraction of face height). These numbers are rounded to '
        'two decimals and cannot identify you: a value of "0.34" is shared by '
        'millions of people. No face recognition, identity verification or '
        'person matching is performed, and your face cannot be reconstructed '
        'from these numbers.\n\n'
        'The ratios and the resulting reading are stored against your account '
        'and are never shown to other users. The feature runs only with your '
        'separate, explicit consent, which you can withdraw at any time from '
        'Profile > Privacy. Withdrawing deletes your ratios and any readings '
        'produced from them.\n\n'
        'Face reading is a form of entertainment and self-reflection. It is '
        'not used, and must not be used, for any decision about health, '
        'employment, credit, insurance or anything similar.'
  ),
  (
    'Notifications',
    'Your time zone and your chosen interface language are written against '
        'your account on every sign-in, even if you never turn notifications '
        'on; your device\'s notification token (FCM) can only be obtained, '
        'and is only stored, once you have granted notification permission. '
        'The time zone is what lets a notification land in your own '
        'morning; we do not collect your location, only the time zone name '
        'your device reports (for example "Europe/Istanbul"). Notification '
        'text is generated on our servers and IS individual: the body of the '
        'morning reading, the midday notification and the evening check-in '
        'question is produced from the day\'s signal in your own birth '
        'chart. The personal line in the morning and midday notifications '
        'and the evening question are written by AI, and only if you have '
        'allowed AI processing (see "AI processing"). If you have not, the '
        'morning and midday notifications carry the technical line for the '
        'same signal and the evening question is not sent at all. On a day '
        'when your chart yields no signal to send, the '
        'shared per-sign text goes out instead; the streak reminder and the '
        'friend-reaction notification are fixed templates (how many days '
        'your streak is, who sent the reaction). The evening circle note '
        'describes a transit measured that day between you and someone you '
        'added to your circle or a friend; its title carries that person\'s '
        'display name or relation label. If you do not open the app for 3, '
        '10 and 30 days, one reminder goes out at each step and then they '
        'stop; the day-10 reminder may mention someone in your circle. '
        'Your chat history is never '
        'used to produce any of them. You can switch types off and set quiet '
        'hours under Profile > Notifications, or turn them off entirely in '
        'your device settings. If you delete the app the token stops working '
        'and we drop it on the first failed delivery.'
  ),
  (
    'Subscriptions',
    'Purchases are handled by your device\'s app store. We never see or store '
        'your payment details. We receive your subscription status (active or '
        'inactive, period end) through RevenueCat and store it against your '
        'account.'
  ),
  (
    'AI processing',
    'Personal readings (daily reading, natal report, BaZi, Year Chart, Inner '
        'Calendar, Birth Hexagram, I Ching, relationship readings), chat '
        'replies, the face reading interpretation, the comment lines on '
        'signal cards and calendar events, the personal lines in the morning '
        'and midday notifications, and the evening check-in question are '
        'generated by a '
        'third-party AI service: the Gemini API of Google LLC. We ask for '
        'your SEPARATE, explicit permission for these features inside the '
        'app. If you do not give it, these features stay off and the data '
        'below is not sent to Gemini; your birth chart, the sky, the '
        'calendar and friend features keep working.\n\n'
        'Once you allow it, depending on the feature you use, the following '
        'is sent to Google: information calculated from your birth chart '
        '(planet positions, houses, aspects, transits, BaZi pillars; for the '
        'Year Chart, the solar return date and city names); your chat '
        'messages and the recent part of the conversation; the question you '
        'ask the I Ching; short notes drawn from your chats, your mood trend '
        'and your latest journal notes; your name (in relationship '
        'readings); your friends\' display names and signs (in relationship '
        'readings and chat); the relationship type and chart of people you '
        'added (the name you gave '
        'them stays on your phone); for face reading, ratios derived from '
        'your facial features (your photo is not sent). Anything you type '
        'into a chat message, a name included, goes as part of that message.'
        '\n\n'
        'This data is sent only to generate the reading or reply you asked '
        'for. General sign horoscopes and notification lines written per '
        'sun sign are also produced with AI, but none of your personal data '
        'goes into them.\n\n'
        'You can withdraw and give this permission again at any time under '
        'Profile > Privacy. Sending stops from the moment you withdraw; '
        'readings already generated and your chat history are not deleted '
        'by this. Readings are for insight; they are not medical, legal or '
        'financial advice.'
  ),
  (
    'Sub-processors',
    'Google LLC (Firebase Authentication, Cloud Firestore, Cloud Run, Gemini '
        'API) and RevenueCat, Inc. (subscription management). Data is '
        'processed primarily in the Google Cloud us-central1 region, which '
        'means it is transferred outside the EU and the United Kingdom.'
  ),
  (
    'Retention',
    'Your account and birth data are kept for as long as your account exists. '
        'AI response caches are kept for at most 30 days. When you delete '
        'your account, your data is permanently deleted: your birth record, '
        'your chats and the notes drawn from them, your journal entries, the '
        'people you added, your friendships, your username, the readings '
        'generated for you, your AI usage records, your phone verification '
        'attempts and the feedback you sent us.\n\n'
        'Two records are kept on purpose. Your purchase and refund records '
        'are financial documents; tax law requires us to keep them for five '
        'years, and they contain only the product, the amount and the date. '
        'The audit trail of administrator actions on your account is also '
        'kept; if it could be deleted it would not be an audit trail. '
        'Reports you filed are likewise kept, for the safety of others.'
  ),
  (
    'Your rights',
    'You have the right to access, correct, delete, restrict the processing '
        'of, and port your data. You can delete your account from inside the '
        'app, or write to $kLegalContact. Requests are resolved within 30 days '
        'at the latest.'
  ),
  (
    'Age limit',
    'Rytho is not directed at children under 13, and we do not knowingly '
        'collect data from that age group.'
  ),
  (
    'Contact',
    'For privacy questions: $kLegalContact'
  ),
];

// ---------------------------------------------------------------------------
// Terms of Use — English
// ---------------------------------------------------------------------------

const LegalSections kTermsOfUseEn = [
  (
    null,
    'Last updated: $kTermsLastUpdatedEn. By using Rytho you accept these '
        'terms.'
  ),
  (
    'For insight only',
    'All readings, reports and chat replies are for personal insight. Nothing '
        'in the app is medical, legal, financial or psychological advice. The '
        'app deliberately DECLINES to make predictions about health, illness, '
        'pregnancy, death or investments; for those decisions, consult a '
        'qualified professional.'
  ),
  (
    'An honest note about astrology',
    'The sky calculations are based on real astronomical data (Swiss '
        'Ephemeris). Drawing conclusions about personality or events from '
        'those positions, however, is a traditional interpretive practice — '
        'not a scientifically validated method of prediction.'
  ),
  (
    'Account and age limit',
    'You need an account to use the app and you must be at least 13 years '
        'old. You are responsible for keeping your account credentials safe.'
  ),
  (
    'Subscription',
    'A Rytho+ subscription renews automatically unless it is cancelled at '
        'least 24 hours before the end of the period. Billing and cancellation '
        'are handled through your device\'s app store account. If a free trial '
        'is offered and you cancel before it ends, you will not be charged.'
  ),
  (
    'Conduct',
    'Users cannot send each other free text in this app; interaction is '
        'limited to preset reactions. Even so, if someone behaves in a way '
        'that troubles you, you can block and report them. Accounts that '
        'abuse the service may be closed.'
  ),
  (
    'Intellectual property',
    'The design, software and knowledge base of the app belong to Rytho. '
        'Ephemeris calculations use Swiss Ephemeris (© Astrodienst AG). '
        'City and country data is sourced from GeoNames (geonames.org), '
        'used under the CC-BY 4.0 licence.'
  ),
  (
    'Limitation of liability',
    'The service is provided "as is"; we do not guarantee it will run without '
        'interruption or error. Rytho is not liable for decisions you make on '
        'the basis of its readings.'
  ),
  // Karşılığı: web/en/legal/terms.html §9. Türkçe gövdeyle aynı maddeleri
  // saymak zorunda — iki dil ayrışırsa hangisinin bağlayıcı olduğu belirsiz
  // kalır.
  (
    'Partner programme',
    'We run a partner programme for people and organisations who promote '
        'Rytho. Participation follows an application or an invitation and '
        'requires our acceptance and a separate partner agreement; applying '
        'alone does not grant participation. A partner\'s link gives the '
        'person who uses it no discount and no reward; prices are the same '
        'for everyone. A partner earns a reward for each first Rytho+ '
        'subscription taken by a user who arrived through their link; the '
        'amount is set in the partner agreement. Credit packs, the free '
        'trial, subscription renewals and store test (sandbox) purchases '
        'earn nothing.'
  ),
  (
    null,
    'A reward is confirmed 15 days after the purchase; if the purchase is '
        'refunded, the payment cannot be collected, or the subscription ends '
        'early within that period, the reward is cancelled. Rewards are '
        'personal and cannot be transferred; payment in cash may be '
        'requested once the payout threshold stated in the agreement is '
        'reached. A partner using their own code on their own account, '
        'creating fake accounts to generate rewards, misleading promotion '
        'and unsolicited bulk messaging (spam) end participation; rewards '
        'not yet confirmed are then forfeited. Any tax obligations arising '
        'from rewards are the partner\'s responsibility. The programme may '
        'be changed or discontinued; rewards already confirmed are still '
        'paid.'
  ),
  (
    'Contact',
    'For questions and requests: $kLegalContact'
  ),
];

// ---------------------------------------------------------------------------

/// Dile göre gizlilik politikası bölümleri.
LegalSections privacyPolicySections(String languageCode) =>
    languageCode == 'en' ? kPrivacyPolicyEn : kPrivacyPolicyTr;

/// Dile göre kullanım şartları bölümleri.
LegalSections termsOfUseSections(String languageCode) =>
    languageCode == 'en' ? kTermsOfUseEn : kTermsOfUseTr;
