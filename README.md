# Chess 3D

یک بازی شطرنج سه‌بعدی با کیفیت بالا، الهام‌گرفته از حس‌وحال Chess Titans و طراحی‌شده از ابتدا برای Android.

## فناوری‌ها

- **Godot 4.4.1** و GDScript
- رندر موبایل `gl_compatibility` برای پوشش گسترده دستگاه‌ها
- حداقل Android 7.0 (API 24)
- معماری هدف: ARM64

## اجرای پروژه

1. [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/) را نصب کنید.
2. این پوشه را از Project Manager باز کنید.
3. کلید F6/F5 را بزنید.

بازی کامل است: موتور مستقل قوانین شطرنج، هوش مصنوعی آفلاین، دوربین لمسی (چرخش، زوم، جابه‌جایی مهره با کشیدن)، ساعت، آرشیو بازی، صدا و موسیقی، دسترس‌پذیری و رابط دوزبانه فارسی/انگلیسی.

تست‌های خودکار:

```bash
godot --headless --path . --script res://tests/test_chess.gd
```

## خروجی Android در سیستم محلی

پیش‌نیازها:

- Godot 4.4.1 به‌همراه Export Templates
- Android Studio یا Android SDK
- OpenJDK 17

در Godot مسیرهای Java SDK و Android SDK را در `Editor Settings > Export > Android` تنظیم و سپس از `Project > Export`، پیش‌تنظیم **Android** را اجرا کنید.

```bash
mkdir -p build/android
godot --headless --path . --export-debug "Android" build/android/chess-3d.apk
```

فایل‌های keystore نباید وارد Git شوند. انتشار AAB نهایی به keystore خصوصی و GitHub Secrets نیاز دارد و بعد از تعیین مشخصات انتشار فعال خواهد شد.

## GitHub Actions

Workflow موجود در `.github/workflows/ci.yml` در هر Push و Pull Request:

1. پروژه و صحنه آغازین را به‌صورت headless اعتبارسنجی می‌کند.
2. یک APK دیباگ امضاشده می‌سازد.
3. APK را به‌مدت ۱۴ روز در بخش Artifacts همان اجرای Actions قرار می‌دهد.

## نقشه راه نزدیک

- مدل‌های اصلی صفحه و مهره‌ها
- منطق مستقل و تست‌پذیر قوانین شطرنج
- انتخاب مهره و نمایش حرکت‌های مجاز
- دوربین لمسی کامل (چرخش، زوم و بازنشانی)
- پروفایل‌های گرافیکی Low / Medium / High
- هوش مصنوعی آفلاین


## نکات فنی پیکربندی

چند تنظیم در `project.godot` مستقیماً روی رفتار اندروید اثر می‌گذارد و نباید بدون دلیل تغییر کند:

| تنظیم | مقدار | دلیل |
|---|---|---|
| `input_devices/pointing/emulate_mouse_from_touch` | `true` | **باید روشن بماند.** در گودوت، نودهای داخلی `Control` (همهٔ `Button`های UI) روی صفحهٔ لمسی فقط به رویداد موس واکنش می‌دهند؛ با `false` هیچ دکمه‌ای روی اندروید کار نمی‌کند. رویداد موس مصنوعی که همین تنظیم تولید می‌کند در `_unhandled_input` با `device == -1` فیلتر می‌شود. |
| `display/window/stretch/aspect` | `expand` | بدون آن، HUD روی گوشی‌های غیر ۱۶:۹ نامتناسب کشیده می‌شود. |
| `application/config/quit_on_go_back` | `false` | دکمهٔ Back اندروید را به `ui_cancel` تبدیل می‌کند تا منو بسته شود، نه اینکه اپ بسته شود. |
| `application/config/version` | `0.16.1` | منبع یگانهٔ شمارهٔ نسخه؛ برچسب داخل بازی از همین‌جا خوانده می‌شود. |

شمارهٔ نسخهٔ نمایش‌داده‌شده در بازی از `APP_VERSION_FALLBACK` و `APP_BUILD` در `src/main/main.gd` به‌همراه `application/config/version` در `project.godot` می‌آید؛ آن را با `version/name` در `export_presets.cfg` هماهنگ نگه دارید.

## انتشار Beta

سیاست حریم خصوصی در [`PRIVACY.md`](PRIVACY.md)، اطلاعات فروشگاه در `store/` و راهنمای انتشار امضاشده در [`docs/BETA_RELEASE.md`](docs/BETA_RELEASE.md) قرار دارد. Workflow دستی `Android Beta Release` فقط با GitHub Secrets خصوصی، AAB امضاشده تولید می‌کند.
