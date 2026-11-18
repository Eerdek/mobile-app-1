# AKI Foods — ажилтны апп (Flutter)

`zahialgiin-system`-ийн web хувилбарын (seller / factory / delivery) mobile апп.
Backend нь ижил (`akifoodsBackend`), API-д өөрчлөлт хийгээгүй.

## Төлөв

| Хэсэг | Төлөв |
|---|---|
| Нэвтрэлт, session (Keychain/Keystore) | ✅ |
| **Үйлдвэр** — бэлтгэл, хүлээлгэн өгөх, үлдэгдэл, заавар, бүсийн зураг, түүх | ✅ |
| Түгээлтийн хуудас / бэлтгэх нэгтгэл → BLE принтер | ✅ (бодит принтер дээр туршаагүй) |
| Excel (хуваалцах цонхоор) | ✅ |
| Түгээгч | ⏳ дараагийн шат |
| Борлуулагч | ⏳ дараагийн шат |

## Ажиллуулах

```bash
flutter pub get
flutter test                       # логик + хэвлэлтийн зураг + layout тест
flutter run                        # утас холбосон бол (production backend)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1   # эмулятор + local backend
```

⚠ Анхдагч backend нь **production** (`akifoodsbackend.fly.dev`). Туршилтын
тэмдэглэгээ (бэлтгэл, «Өгсөн») жинхэнэ өгөгдөлд бичигдэнэ.

Android build хийхэд Android Studio (SDK + cmdline-tools) суулгаад
`flutter doctor --android-licenses` ажиллуулна.

## Бүтэц

```
lib/
  core/          config, api_client, session, format (монгол эрэмбэ), ui, excel
  printing/      escpos (raster), ble_printer, receipt (576px зохиомж), print_button
  features/
    auth/        нэвтрэх
    factory/     models → logic (цэвэр, тестлэгдсэн) → controller → табууд
```

## Хэвлэлт — анхаарах

- `printing/escpos.dart` ба `ble_printer.dart` дахь тоонууд (хурд 12000 Б/с,
  урт баримтад 10000, ×1.25 босоо залруулга, m=0, 0x10→0x30) нь web-ийн
  `bt-print.js`-д 80HB6 принтер дээр **хэмжиж** тогтоосон утга. Тайлбаргүйгээр
  бүү өөрчил.
- Баримтын фонт нь web-ийн `receipt-mono.css`-ээс гаргасан ижил subset
  (`assets/fonts`). Subset-д «·» байхгүй тул баримтад «•» хэрэглэнэ.
- BLE сан: `universal_ble` (BSD-3). `flutter_blue_plus` нь ашгийн
  байгууллагад төлбөртэй лиценз шаарддаг тул хэрэглээгүй.
