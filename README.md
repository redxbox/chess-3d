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

نمونه فعلی یک صفحه سه‌بعدی تولیدشده در زمان اجرا، نورپردازی اولیه و کنترل چرخش لمسی/ماوس دارد.

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


## انتشار Beta

سیاست حریم خصوصی در [`PRIVACY.md`](PRIVACY.md)، اطلاعات فروشگاه در `store/` و راهنمای انتشار امضاشده در [`docs/BETA_RELEASE.md`](docs/BETA_RELEASE.md) قرار دارد. Workflow دستی `Android Beta Release` فقط با GitHub Secrets خصوصی، AAB امضاشده تولید می‌کند.
