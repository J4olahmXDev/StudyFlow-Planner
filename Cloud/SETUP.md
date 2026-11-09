# StudyFlow ซิงก์ด้วยโค้ด

1. สร้างโปรเจกต์ Supabase ของซัวว์ แล้วรัน `schema.sql` ใน SQL Editor เพื่อเตรียมตารางและคำสั่งซิงก์
2. ใช้ Project URL แบบ `https://<project>.supabase.co` และ Publishable Key ที่ขึ้นต้นด้วย `sb_publishable_` ใส่ใน `../Resources/CloudDeployment.plist` ก่อน build แอป Mac และ iPhone/iPad หรือกรอกเองที่ **Settings → ซิงก์ด้วยโค้ด** ในโหมดข้อมูลจริง
3. เครื่องแรกกด **สร้างโค้ดและซิงก์** แล้วเก็บโค้ดไว้ส่วนตัว เครื่องถัดไปเลือกโปรเจกต์เดียวกันและกด **ใช้โค้ดนี้** ข้อมูลที่มีอยู่ในเครื่องจะรวมกับชุดข้อมูลของโค้ด
4. เว็บบน iPhone, iPad และ Android ใช้ Project URL และ Publishable Key ใน `Web/config.mjs` เปิดลิงก์ HTTPS แล้วใส่โค้ดเดียวกัน สำหรับ Windows x64 ดู `../Windows/README.md`

## แชร์เฉพาะข้อมูลที่เลือก

- ในแอป Mac, iPhone หรือ iPad เปิดหน้าตารางแล้วกดไอคอน **แชร์ตารางหรืองาน** เลือกตารางและวิชา งาน หรือกิจกรรมได้หลายหมวด แล้วกด **สร้างโค้ดและรหัส**
- ในเว็บ Windows หรือ Android ใส่โค้ด 6 ตัวและรหัส 12 ตัวลงคนละช่อง ผู้รับดูได้เฉพาะหมวดที่เลือก งานรวมโน้ตและงานย่อยในงาน
- เมื่ออุปกรณ์ที่แชร์เปิดแอปและออนไลน์ การแก้ไขจะส่งไปยังชุดแชร์ประมาณทุก 15 วินาที เว็บตรวจอัปเดตในช่วงเดียวกันเมื่อเปิดอยู่ กด **หยุดแชร์** บนอุปกรณ์ที่สร้างชุดแชร์เพื่อยกเลิกการเข้าถึงออนไลน์ของชุดนั้น
- ถ้าเคยติดตั้ง Supabase สำหรับซิงก์รุ่นก่อน ให้รัน `schema.sql` ฉบับนี้อีกครั้งเพื่อเพิ่มคำสั่งชุดแชร์

## ซิงก์ส่วนตัวทั้งชุด

Mac, iPhone และ iPad บันทึกในเครื่องก่อน และตรวจซิงก์ประมาณทุก 15 วินาทีขณะเปิดแอปเมื่อเชื่อมแล้ว เว็บและแอป Windows ดูตาราง วิชา งาน กิจกรรม เพิ่มงาน และติ๊กงานได้ หลังเชื่อมออนไลน์ครั้งแรก ข้อมูลส่วนตัวและคิวงานจะเข้ารหัสไว้ในเครื่อง เปิดใหม่ด้วยโค้ดเดิมได้แม้ออฟไลน์ ระบบจะส่งคิวเมื่อเปิดแอปและกลับมาออนไลน์ ชุดแชร์เปิดดูได้ขณะออนไลน์

โค้ดใช้ค่าสุ่ม 128 บิต ผู้ที่มีโค้ดสามารถอ่านและแก้ข้อมูลในชุดนั้นได้ คลาวด์เก็บข้อมูลเข้ารหัส AES-GCM การลบชนะการแก้ฉบับเก่า ส่วนการแก้รายการเดียวกันพร้อมกันจะเลือกหนึ่งฉบับอย่างสม่ำเสมอ

## My Term

สร้าง เปลี่ยนชื่อ และสลับเทอมในแอป Mac, iPhone หรือ iPad ข้อมูลเดิมจะอยู่ในเทอมเดิม ส่วนรายการใหม่จะบันทึกเข้าเทอมที่เลือก โค้ดซิงก์ส่วนตัวใช้ร่วมกันได้ทุกเทอม และโค้ดแชร์จะอัปเดตเฉพาะเทอมที่เลือกตอนสร้าง

อัปเดตแอปบนทุกเครื่องก่อนซิงก์เทอมใหม่ เพราะรุ่นก่อนอ่านข้อมูลเทอมไม่ได้ เว็บเลือกดูเทอมและเพิ่มงานในเทอมที่เลือกได้ ส่วน Apple Watch แสดงเทอมที่เปิดอยู่บน iPhone

## iPhone, iPad และ Apple Watch

เปิด `../StudyFlow Planner.xcodeproj` ใน Xcode แล้วเลือก scheme **StudyFlow Planner** สำหรับ iPhone และ iPad หรือ **StudyFlow Watch** สำหรับ Apple Watch ตัวแอปรองรับ iOS/iPadOS 17 และ watchOS 10 ขึ้นไป หากลงบนเครื่องจริงให้เลือก Signing Team เดียวกันในทั้งสอง target

Apple Watch แสดงตารางวันนี้และงานค้างจากข้อมูลจริงของ iPhone ที่จับคู่กัน เปิด StudyFlow บน iPhone ให้แอปส่งข้อมูลก่อน แล้วเปิดแอปบนนาฬิกา งานที่แก้บน iPhone จะอัปเดตผ่าน Watch Connectivity เมื่อนาฬิการับข้อมูลรอบถัดไป

ขั้นก่อนใช้งานจริงคือทดสอบกับโปรเจกต์ Supabase และอุปกรณ์จริง แล้วกำหนดการจำกัดอัตราการเรียก API ก่อนเปิดให้คนทั่วไปสร้างชุดข้อมูล

- [Supabase Publishable Keys](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase SQL Editor](https://supabase.com/docs/guides/database/overview)

## วิดเจ็ตคาบและงานถัดไป

- **Mac, iPhone, iPad และ Apple Watch** เปิดโปรเจกต์ Xcode แล้วเลือก scheme StudyFlow Mac, StudyFlow Planner หรือ StudyFlow Watch ตามอุปกรณ์ ตั้ง Signing Team และ App Groups ของแอปกับวิดเจ็ตให้ตรงกันก่อนติดตั้ง เปิดแอปครั้งแรกให้วิดเจ็ตรับข้อมูลจริงของเทอมที่เลือก แล้วเพิ่ม StudyFlow จากรายการวิดเจ็ต บน Apple Watch ข้อมูลมาจาก iPhone ที่จับคู่
- **Windows 11** หลังนำเว็บขึ้น HTTPS แล้ว ให้ติดตั้งเว็บผ่าน Edge และเพิ่ม StudyFlow ใน Widgets Board บนเครื่องที่รองรับ เปิด “แสดงข้อมูลบน Windows Widgets Board” หลังเชื่อมด้วยโค้ดส่วนตัว วิดเจ็ตจะแสดงข้อมูลล่าสุดที่เว็บส่งไว้
- **Android** การ์ดคาบและงานถัดไปอยู่ในเว็บ StudyFlow หลังเชื่อมชุดข้อมูล วิดเจ็ตที่ปักบนหน้าจอหลักจะมาพร้อมแอป Android

เอกสารแพลตฟอร์ม [Apple WidgetKit](https://developer.apple.com/documentation/widgetkit/) · [Windows PWA widgets](https://learn.microsoft.com/en-us/microsoft-edge/progressive-web-apps/how-to/widgets) · [Android App Widgets](https://developer.android.com/develop/ui/views/appwidgets/overview)

## เผยแพร่เว็บและติดตั้งบน iPhone / iPad

เว็บจริง [StudyFlow Planner](https://suanaph-studyflow-planner.netlify.app/)

นำไฟล์ใน `Cloud/Web` ขึ้น Netlify ผ่าน Deploy manually โดยให้ `index.html` อยู่ที่รากของชุด deploy ชุด `StudyFlow-Web.zip` ในโฟลเดอร์ Timetable ใช้อัปโหลดได้ หรือลากโฟลเดอร์ `Web` เข้า Netlify Drop

Netlify ให้บริการหน้าเว็บเท่านั้น Supabase เก็บข้อมูลที่เข้ารหัส เว็บใช้เฉพาะ Project URL และ Publishable Key ห้ามใส่รหัสฐานข้อมูล, Secret Key, Service Role Key หรือโค้ดซิงก์จริงในไฟล์เว็บ

เปิดลิงก์ผ่าน Safari → แชร์ → เพิ่มไปยังหน้าจอโฮม แล้วเปิดจากไอคอนได้ทันที เว็บเริ่มจากข้อมูลในเครื่องและบันทึกในเบราว์เซอร์ กดซิงก์หรือเปิดชุดแชร์เมื่อจะเชื่อมข้ามเครื่อง ใช้โค้ดจากเครื่องอื่นเพื่อเปิดชุดนั้น หรือสร้างโค้ดจากข้อมูลในเครื่องเมื่อต้องการส่งชุดนี้ขึ้นคลาวด์ การล้างข้อมูลเว็บไซต์จะลบข้อมูลที่เก็บเฉพาะในเครื่อง วิดเจ็ต iOS/iPadOS และหน้าจอ Apple Watch ใช้แอป Apple ที่ติดตั้งผ่าน Xcode การส่งข้อมูลไป Apple Watch ใช้แอป native บน iPhone ที่จับคู่

[Netlify manual deploy](https://docs.netlify.com/deploy/create-deploys/) · [เพิ่มเว็บแอปลงหน้าจอโฮม](https://support.apple.com/guide/iphone/iphea86e5236/ios)
