
# 📐 HedgeDrift Minimal — Master System Architecture & Development Blueprint (v3.0 Final Master Spec)

## 📌 1. Execution Workflow Rules (กฎการทำงานใหม่)
1. **Compile-Only Validation per Phase:** ทุกๆ Phase ที่พัฒนานั้น ไอ้จ้อยต้องเขียนโค้ดและส่งมาให้ Compile ผ่าน MetaEditor (0 Errors, 0 Warnings) เท่านั้น **ไม่ต้องหยุดรอให้ผู้ใช้ไปนั่งกด Runtime Test ทีละข้อบนกราฟ!**
2. **Phase-by-Phase Progress:** พัฒนาและเชื่อมต่อโครงสร้างต่อได้ทันทีเมื่อผ่าน Compile เพื่อรันยาวไปจนจบ Phase 4 (Persistence & Recovery Engine)
3. **Mid-Way Adjustments Allowed:** ผู้ใช้สามารถสั่งปรับ เพิ่ม หรือลด ฟังก์ชันการทำงานระหว่างการพัฒนาได้ตลอดเวลา
4. **Final Integration Test Checklist:** เมื่อโค้ดครบทุก Phase (Phase 1 - 4) จะทำการทดสอบระบบรวมทั้งหมดจาก Master Checklist ในรอบเดียว

---

## 🎛️ 2. Input Parameter Standards & Explicit Toggle Rules (กฎเหล็ก Input 6 กลุ่ม)
> **CRITICAL RULE:** ทุกฟังก์ชันและทุก Sub-option ต้องมีสวิตช์ `bool` (`true`/`false`) ควบคุมระดับหัวหมวดและซับฟังก์ชันเสมอ **ห้ามใช้ค่า `0`, `-1` หรือข้อความว่าง `""` ในการเปิด-ปิดฟังก์ชันเด็ดขาด!**

```mql5
//=== Group 1: Virtual Capital Auto-Lot ===
input bool     InpEnableAutoLot           = true;          // เปิด/ปิด ระบบคํานวณ Lot อัตโนมัติ
input double   InpBaseCapital             = 50.0;          // ทุนเริ่มต้นจำลองต่อบอท ($)
input double   InpStartLot                = 0.01;          // ขนาด Lot เริ่มต้น
input double   InpStepCapital             = 50.0;          // ขั้นบันไดเพิ่ม Lot ทุกๆ ($)
input double   InpStepLot                 = 0.01;          // ขนาด Lot ที่เพิ่มต่อขั้นบันได
input double   InpRefillAmount            = 10.0;          // จำนวนเงินจำลองที่เพิ่มต่อการกด Refill ($)

//=== Group 2: Hard Risk Control ===
input bool     InpEnableHardCutLoss       = true;          // เปิด/ปิด ตัดขาดทุนรายไม้เมื่อผิดทาง
input int      InpCutLossPoints           = 1000;          // ระยะตัดขาดทุน (Points)

//=== Group 3: Core Strategy & Direction Selector ===
enum ENUM_STRATEGY_MODE {
   MODE_TIME_SESSION = 0,   // 1. Time Session Mode
   MODE_LOCK_PRICE   = 1,   // 2. Distance Lock Price Mode
   MODE_MANUAL_FREE  = 2    // 3. Manual / Free Trade Mode
};
input ENUM_STRATEGY_MODE InpStrategyMode  = MODE_LOCK_PRICE; // เลือกกลยุทธ์การเทรดหลัก

enum ENUM_TRADE_DIRECTION {
   DIR_BUY_ONLY  = 0,       // Buy Only
   DIR_SELL_ONLY = 1,       // Sell Only
   DIR_BOTH      = 2,       // Both Buy & Sell
   DIR_HEDGE     = 3        // Hedge
};
input ENUM_TRADE_DIRECTION InpTradeDirection = DIR_BOTH;     // เลือกทิศทางออร์เดอร์

//--- Sub-Settings: Distance Lock Price System ---
input bool     InpEnableHedgeTriggerLock  = true;          // เปิด/ปิด ระบบยึด Lock Price
input int      InpLockDistancePoints      = 1000;          // ระยะทางจาก Lock Price ที่จะเริ่มยิง Order (Points)
input bool     InpEnableCutLossReLock     = true;          // โดน CutLoss แล้วยึดราคาปิดเป็น Lock Price ใหม่ทันที (Loop)

//--- Sub-Settings: Auto Cycle & Timeout ---
input bool     InpEnableAutoNewCycle      = true;          // เปิดออร์เดอร์รอบใหม่อัตโนมัติเมื่อ Basket ว่าง
input bool     InpEnableCycleTimeout      = true;          // เปิด/ปิด ระบบ Timeout บังคับเปิดรอบใหม่
input int      InpTimeoutSeconds          = 300;           // ระยะเวลา Timeout (วินาที)

//=== Group 4: Profit Protection & Targets ===
input bool     InpEnableAutoBE            = true;          // เปิด/ปิด ระบบ Auto Break-Even
input int      InpBETriggerPoints         = 1000;          // ระยะบวกที่เริ่มล็อกทุน (Points)
input double   InpBELockPercent           = 20.0;          // % การล็อกทุนของระยะ Trigger

enum ENUM_BE_TYPE {
   BE_TYPE_FIXED   = 0,     // 1. Fixed Percent (ล็อกนิ่งไม่เลื่อนตาม)
   BE_TYPE_DYNAMIC = 1      // 2. Dynamic Trailing Percent (เลื่อนขึ้นตามราคาเมื่อบวกเพิ่มทุก 10 pts)
};
input ENUM_BE_TYPE InpBEType              = BE_TYPE_FIXED;  // รูปแบบ Break-Even

input bool     InpEnableRRTarget          = true;          // เปิด/ปิด การปิดทำกำไรตามเป้า RR
input double   InpRRTargetPercent         = 100.0;         // % RR Target คิดจาก CutLoss Points

//--- Sub-Settings: Trailing TP (Best Price) ---
input bool     InpEnableTrailingTP        = false;         // เปิด/ปิด ระบบ Trailing TP ตามราคาที่ดีที่สุด
input int      InpTrailingStepPoints      = 500;           // ระยะย้อนกลับจากราคาที่ดีที่สุดก่อนปิดออเดอร์ (Points)

//=== Group 5: Multi-Trading Sessions (สวิตช์ bool แยกอิสระทุก Session) ===
input bool     InpEnableSession1          = true;          // เปิด/ปิด ช่วงเวลาเทรด 1
input string   InpSession1Time            = "01:30-05:00"; // ช่วงเวลา 1
input bool     InpEnableSession2          = true;          // เปิด/ปิด ช่วงเวลาเทรด 2
input string   InpSession2Time            = "10:00-14:00"; // ช่วงเวลา 2
input bool     InpEnableSession3          = true;          // เปิด/ปิด ช่วงเวลาเทรด 3
input string   InpSession3Time            = "21:00-24:00"; // ช่วงเวลา 3

//=== Group 6: System Identity ===
input ulong    InpMagicNumber             = 998874;        // รหัสประจำตัว EA
input string   InpEAComment               = "HedgeDrift_RR1:2"; // ข้อความอธิบายกลยุทธ์

```

---

## 🎯 3. Core Strategy Architecture (3 Independent Strategy Modes)

ระบบแยก Pipeline การทำงานออกเป็น 3 โหมดอิสระจากกันเด็ดขาด (Decoupled Isolation) ห้ามนำ Filter ของโหมดหนึ่งไปบล็อกการทำงานของอีกโหมดหนึ่ง:

```
                  ┌───────────────────────────────────────────┐
                  │           HedgeDrift Core Engine          │
                  └─────────────────────┬─────────────────────┘
                                        │
      ┌─────────────────────────────────┼─────────────────────────────────┐
      ▼                                 ▼                                 ▼
┌───────────────────────────┐ ┌───────────────────────────┐ ┌───────────────────────────┐
│ 1. Manual / Panel Mode    │ │ 2. Timeout Mode           │ │ 3. Lock Crossing Mode     │
├───────────────────────────┤ ├───────────────────────────┤ ├───────────────────────────┤
│ • Instant Execution       │ │ • Elapsed Time Trigger    │ │ • Price Action Crossing   │
│ • Bypass Lock & Session   │ │ • Condition: Pos == 0     │ │ • Session Filter Aware    │
│ • Manual Order Override   │ │ • Action: Auto HEDGE OPEN │ │ • Strict Level Breakout   │
└───────────────────────────┘ └───────────────────────────┘ └───────────────────────────┘

```

### 🔹 Execution Policy:

1. **Manual Mode (Panel Execution):**
* ทำงานทันทีเมื่อมีการกดปุ่มบน Panel (Instant Execution)
* **Bypass Rule:** บังคับข้ามการตรวจ Lock Crossing และ Session Filter ทันที (ถือเป็นคำสั่ง Manual Override โดยมนุษย์)


2. **Timeout Mode (Auto Initial Trigger):**
* ทำงานเมื่อระบบไม่มีสถานะค้างในพอร์ต (`Pos == 0`)
* เริ่มนับถอยหลัง Timer (เช่น 300 วินาที)
* เมื่อนับครบเวลา ให้สั่งยิง **`HEDGE OPEN` (เปิดทั้ง Buy และ Sell พร้อมกันเป็นคู่)** ทันที เพื่อเริ่มนับ Cycle ACTIVE และสร้างจุดอ้างอิงใหม่
* **Bypass Rule:** ข้ามการตรวจ Lock Crossing ทันที


3. **Lock Crossing Mode (Algorithmic Breakout):**
* ยิงออเดอร์เมื่อราคา Bid/Ask ข้ามระดับ Lock Price ที่กำหนด
* ทำงานร่วมกับ Direction Rules (`BUY_ONLY`, `SELL_ONLY`, `DIR_BOTH`) และอยู่ในขอบเขตของ Session Filter



---

## 🎨 4. UI/UX & Responsive Display Specs

1. **Button High-Contrast:**
* ปุ่มสถานะเปิดใช้งาน (`State ON` / พื้นหลังสีเขียว) ให้ปรับตัวหนังสือบนปุ่มเป็น **"สีดำ" (`clrBlack`)** เพื่อเพิ่ม Contrast และทำให้อ่านข้อความชัดเจน 100%


2. **Responsive Dynamic Scaling:**
* ตรวจสอบขนาดหน้าต่างกราฟผ่าน `ChartGetInteger(0, CHART_WIDTH_IN_PIXELS)`
* ปรับขนาด Panel, ความกว้าง-สูงของปุ่ม และ Font Size แปรผันตามสัดส่วนจออัตโนมัติ เพื่อรองรับการเปิดใช้งานบนโน้ตบุ๊กหน้าจอเล็ก


3. **Minimize / Panel Toggle:**
* เพิ่มปุ่มพับเก็บ Panel `[_]` ที่มุมบนขวา เพื่อย่อ Panel ให้เหลือขนาดมินิมอล ไม่บังพื้นที่วิเคราะห์กราฟเวลาไม่ได้กดปุ่ม



---

## 💾 5. Persistence & Recovery Engine (Phase 4 Specs)

1. **State Isolation & Storage:**
* บันทึกไฟล์สถานะไว้ที่ Sandbox Path:
`<data folder>\MQL5\Files\HedgeDrift\<account-server-symbol-magic>\state.json`


2. **Atomic Safe Save Protocol:**
* เขียนข้อมูลลง Temp File -> Flush/Close -> สำรองไฟล์เดิม -> Replace ไฟล์หลัก


3. **Recovery State Mapping:**
* กู้คืน Capital (EQ) จาก `Base Capital + Refill + Realized Profit` ที่บันทึกไว้
* คำนวณ Floating Profit (OR) จากสถานะการเทรดจริงบนกราฟปัจจุบัน (ไม่โหลดค่า Floating เก่า)
* กู้คืน `Initial Risk Money` เดิมคงที่ ไม่ลดลงตามการเลื่อน Step ของ Dynamic BE
* กู้คืนสถานะ Lock Price, State Machine (`IDLE`, `ACTIVE`, `CLOSING`), Active Strategy Mode และ Timeout Countdown Counter
* ตรวจสอบ Deal History ที่เกิดขึ้นระหว่าง EA หยุดทำงาน และนับเฉพาะรายการที่ยังไม่เคย Replay


4. **Safety Guards:**
* หากไฟล์ state.json หายหรือเสียหายระหว่างมีไม้ค้าง ให้เข้าสู่โหมด Safe-Lock บล็อกการเปิดออเดอร์ใหม่จนกว่าจะมีการยืนยันจากผู้ใช้



---

## 🛠️ 6. Phase 4 Implementation Plan

1. สร้างโมดูล `Persistence.mqh` ทำหน้าที่ I/O และ Serialize/Deserialize สภาพแวดล้อมลง `state.json`
2. ทำ Patch ใน `OnInit()` ของ `HedgeDrift_Minimal_GPT.mq5` ให้เลิก Reject การโหลดเมื่อมีไม้ค้าง เปลี่ยนเป็นเข้าสู่กระบวนการ `RestoreState()`
3. เชื่อมต่อ `AccountingEngine`, `RiskEngine`, `StrategyEngine`, และ `PanelEngine` เข้ากับระบบ Persistence
4. ส่งมอบโค้ดครบทุกไฟล์ในรูปแบบ Full Code ที่พร้อม Compile ทันที (0 Errors, 0 Warnings)

---
