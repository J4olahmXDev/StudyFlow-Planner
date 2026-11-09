# StudyFlow Planner สำหรับ Windows

แอป Windows x64 เปิดในหน้าต่างของตัวเองด้วย WinForms และแสดงหน้าจอ StudyFlow จากไฟล์ที่แนบมากับแอป ใช้ WebView2 Runtime และ .NET Framework 4.8

1. แตก ZIP ทั้งโฟลเดอร์ แล้วเปิด `StudyFlow Planner.exe`
2. ใช้โค้ดส่วนตัวจาก Settings → ซิงก์ด้วยโค้ด บน Mac เพื่อเปิดและซิงก์ชุดเดียวกัน หรือใช้โค้ด 6 ตัวกับรหัส 12 ตัวเพื่อดูเฉพาะหมวดที่แชร์
3. เชื่อมเน็ตครั้งแรกเพื่อดาวน์โหลดข้อมูล จากนั้นเปิดด้วยโค้ดเดิมและเพิ่มงานหรือทำเครื่องหมายเสร็จแล้วได้ออฟไลน์ ระบบส่งการแก้ไขเมื่อกลับมาออนไลน์ขณะเปิดแอป

รุ่นนี้เป็น ZIP แบบพกพาและยังไม่ได้เซ็น Windows การติดตั้งวิดเจ็ตใน Windows Widgets Board ใช้รุ่นเว็บที่ติดตั้งผ่าน Edge บน Windows 11 ที่รองรับ

[ติดตั้ง WebView2 Runtime จาก Microsoft](https://developer.microsoft.com/microsoft-edge/webview2/#download-section)

## สร้างรุ่นใหม่

ใช้ .NET SDK แล้วรันจากโฟลเดอร์ `app`

```sh
dotnet build Windows/StudyFlow.Windows.csproj -c Release -p:Platform=x64
```

แพ็กไฟล์จาก `Windows/bin/x64/Release/net48/` โดยเก็บโฟลเดอร์ `Web` และ `runtimes` ไว้ข้าง EXE
