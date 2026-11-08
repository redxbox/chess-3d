# پوشهٔ آپلود ست مهره

این پوشه جایی است که فایل‌های سه‌بعدی مهره‌هایت را **اینجا** می‌گذاری. هرچه اینجا
باشد در APK بسته نمی‌شود (`export_presets.cfg` کل `tools/*` را حذف می‌کند)، پس
حجمش به بازی اضافه نمی‌شود؛ فقط ورودیِ ساخت است.

فارسی توضیح داده شده، چون این پوشه برای تو نوشته شده. نسخهٔ انگلیسی خلاصه در
انتهای همین فایل است.

---

## چطور آپلود کنی

روی گیت‌هاب، داخل همین پوشه:

1. دکمهٔ **Add file** → **Upload files**
2. فایل‌ها را با ماوس داخل کادر بینداز (یا انتخاب کن)
3. پایین صفحه **Commit changes**

اگر از git استفاده می‌کنی، همان:

```sh
cp /path/to/your/pieces/*.glb tools/sources/incoming/
git add tools/sources/incoming && git commit -m "New piece set upload" && git push
```

سقف آپلود وب گیت‌هاب **۲۵ مگابایت برای هر فایل** است. اگر فایلی بزرگ‌تر است، در
همان برنامه‌ای که ساختی یک بار decimate کن (مثلاً به ۳۰۰–۵۰۰ هزار مثلث) و بعد
آپلود کن؛ ایمپورتر خودش تا ۱۰٬۰۰۰ مثلث کم می‌کند، پس جزئیات بیشتر از این حد
به بازی نمی‌رسد و فقط آپلود را کند می‌کند.

## چه شکلی بفرست

| مورد | پیشنهاد |
| --- | --- |
| فرمت | **`.glb`** بهترین است (یک فایل، تکسچر داخلش). `.gltf`، `.obj`، `.stl`، `.ply`، `.fbx`، `.dae` هم قبول‌اند. |
| `.obj` | اگر `.obj` می‌فرستی، `.mtl` و تکسچرها را هم در همین پوشه بگذار. |
| `.blend` / `.max` / `.ztl` | قبول نمی‌شود؛ اول export بگیر. |
| نام فایل | هرچه باشد؛ اسم قطعه باید داخلش باشد: `pawn`, `rook`, `knight`, `bishop`, `queen`, `king` — یا `pown`, `quin`, `horse`, `elephant`, `shah`, `rokh`، یا فارسی: `پیاده`, `رخ`, `اسب`, `فیل`, `وزیر`, `شاه`. |
| تعداد | دقیقاً شش فایل، یک فایل برای هر قطعه. دو فایل با اسم یک قطعه = خطا. |
| محورها | **+Y بالا**، **+Z جلو** (صورت مهره رو به ارتش حریف). |
| مقیاس | مهم نیست؛ هر قطعه خودکار روی «نردبان قد» می‌نشیند (پیاده ۰٫۹۱ … شاه ۱٫۶۲). |
| مبدأ | مهم نیست؛ خودکار وسط‌چین و روی `y = 0` گذاشته می‌شود. |

اگر مدل‌هایت رو به ‎−Z‎ یا +X هستند، اسمشان را عوض نکن — فقط در فایل `NOTES.md`
بنویس؛ جدول جهت در `src/chess/piece_facing.gd` تست دارد و من درستش می‌کنم.

## یک فایل `NOTES.md` هم بگذار (اختیاری ولی مفید)

```md
- نام ست: (مثلاً royal-gold)
- جهت صورت مهره‌ها: +Z / -Z / +X / -X
- رنگ و تکسچر بخشی از طرح است؟ بله / نه
- نکته‌ای دربارهٔ هر قطعه؟
```

## ست فعلی (`pars`)

شش فایلی که در `assets/` آپلود شده بود، همین‌جاست، و ست `pars` از همین‌ها ساخته شد.
نام هر فایل با نقشش شروع می‌شود تا ایمپورتر پیدایش کند:

| نقش | فایل | مثلث | تکسچر | حجم آپلود |
| --- | --- | --- | --- | --- |
| پیاده | `pawn-104217.179.glb` | 472k | 4096² | 18.5 MB |
| رخ | `rook-105358.655.glb` | 282k | 2048² | 12.7 MB |
| اسب | `knight-110155.406.glb` | 470k | 4096² | 19.1 MB |
| فیل | `bishop-111346.525.glb` | 474k | 4096² | 20.3 MB |
| وزیر | `queen-111935.605.glb` | 468k | 4096² | 19.3 MB |
| شاه | `king-110725.578.glb` | 496k | 4096² | 19.3 MB |

خروجی: شش مهرهٔ ۱۰٬۰۰۰ مثلثی در `assets/models/pars/`، هر کدام ۲۷۰ کیلوبایت OBJ
به‌علاوهٔ ۱۵ کیلوبایت `.tint`. کل ست ۱٫۸ مگابایت — همان‌قدر که دو ست دیگر.

## رنگ خودِ مدل (دیگر یک تصمیم باز نیست)

از این نسخه به بعد بازی **رنگ خودِ مدل را می‌خوانَد**. ست `pars` دقیقاً همین‌طور
ساخته شده: رنگ تکسچر ۴۰۹۶×۴۰۹۶ روی رأس‌ها bake شده و کنار OBJ در یک فایل
`<kind>.tint` نشسته (۱۵ کیلوبایت برای هر مهره، در برابر ۱٫۳ مگابایت تکسچر).

```bash
python3 tools/prepare_sculpt_set.py --colours tools/sources/incoming assets/models/<set-name>
python3 tools/normalise_set_scale.py
```

⚠️ فایل `.tint` ایمپورتر گودو ندارد؛ بدون `include_filter` در `export_presets.cfg`
داخل APK بسته نمی‌شود و مهره‌ها روی گوشی **سفید بی‌رنگ** دیده می‌شوند (همین اتفاق یک
بار افتاد). `tools/check_export_presets.py` این را در CI چک می‌کند و اجازهٔ ساخت
نمی‌دهد.

بعد از آن، در `src/main/main.gd` یک ورودی در `PIECE_THEMES` بساز که
`"vertex_colour": true` داشته باشد (مثل `pars`) و `light` و `dark` آن `Color(1,1,1)`
باشند — یعنی «رنگ از رأس‌ها بیاید».

دو ارتش از یک bake می‌آیند: ارتش روشن همان رنگ مدل است، ارتش تیره همان رنگ با یک
گاما و گین (`pale ** gamma * gain + lift`) که عددهایش در هدر همان `.tint` نوشته
شده. پس لازم نیست دو نسخه از مدل بسازی.

`tools/check_visual_balance.py` بعد از ایمپورت خودش این دو عدد را از فایل‌های
`.tint` می‌خواند و چک می‌کند هر ارتش از هر چهار تخته به‌اندازهٔ کافی جدا باشد.

## بعدش چه می‌شود

بعد از آپلود، این را اجرا کن (بدون نیاز به باز کردن بازی):

```sh
python3 tools/check_incoming_set.py
```

یک جدول می‌دهد: کدام قطعه هست، چند مثلث، چه قدی، چه حجمی، رنگ دارد یا نه، و
چه چیزی کم است. اگر نوشت `complete set`، تبدیل به ستِ قابل بازی با این دو دستور:

```sh
python3 tools/prepare_sculpt_set.py tools/sources/incoming assets/models/<set-name>
python3 tools/normalise_set_scale.py
```

`prepare_sculpt_set.py` هر قطعه را تا حد امکان به ۱۰٬۰۰۰ مثلث می‌رساند، روی نردبان قد
می‌آورد، وسط‌چین می‌کند و OBJ می‌نویسد. `normalise_set_scale.py` هم پای مهره را
با ست `classic` هم‌اندازه می‌کند تا سه ست روی یک تخته هم‌اندازه دیده شوند.

CI هم این پوشه را می‌خواند و نتیجه را در خلاصهٔ اجرا می‌گذارد، پس لازم نیست خودت
یادت بماند چه چیزی آپلود کرده‌ای.

---

## English summary

`tools/sources/incoming/` is the drop zone for new piece models: upload six files
(one per piece), `.glb` preferred, +Y up, front toward +Z, any scale, any file
name that contains the piece's name (English or Persian). Web uploads are capped
at 25 MB per file. Run `python3 tools/check_incoming_set.py` to see what is
missing or too heavy, then `prepare_sculpt_set.py` turns the folder into a
playable set. Nothing here ships in the APK.

The game reads a model's own colour when the set asks for it: import with
`--colours`, then give the theme `"vertex_colour": true` in `PIECE_THEMES`. Both
armies come from the one bake - the ink army is a gamma and a gain over the pale
one, and both numbers live in the `.tint` header. That is how the current `pars`
set is built.
