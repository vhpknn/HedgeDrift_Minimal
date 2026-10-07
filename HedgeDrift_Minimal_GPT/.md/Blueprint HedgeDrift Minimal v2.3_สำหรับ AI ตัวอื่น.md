
# 📐 Blueprint.md: HedgeDrift Minimal v2.1 (Full Architecture & Ultra-Minimal UI Spec)

---

## 🎯 1. System Overview & Core Philosophy
* **Goal:** ปรับปรุงโครงสร้าง EA HedgeDrift ให้กลายเป็นระบบ **Minimal & Modular Architecture**
* **Core Rules:** 
  1. ทุกฟังก์ชั่นที่มีการตั้งค่าตัวเลข ต้องมีสวิตช์ `bool` (true/false) ควบคุมระดับหัวหมวดเสมอ ห้ามใช้ `0` ในการเปิด-ปิดเด็ดขาด!
  2. โครงสร้าง Panel บนหน้าจอ ต้องเป็นสวิตช์ Interactive Direct Control สามารถกด Toggle On/Off และสลับโหมดได้ทันทีโดยไม่ต้องเข้าหน้า Inputs
  3. โหมดการเทรดหลัก 3 โหมด ต้องตัดกันเด็ดขาด (Mutually Exclusive Strategy Selector) เพื่อป้องกัน Logic Concurrency

---

## 🎛️ 2. Input Parameters Structure (Explicit Toggles)

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
   DIR_BOTH      = 2,       // Both Buy & Sell (ตามจังหวะ)
   DIR_HEDGE     = 3        // Hedge (เปิด Buy + Sell พร้อมกันทันที)
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
input double   InpRRTargetPercent         = 100.0;         // % RR Target คิดจาก CutLoss Points (100% = 1:1)

//=== Group 5: Multi-Trading Sessions ===
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

## 🧠 3. Detailed Program Logic & Transaction Tracking Rules

### A. Strategy Execution Flow

1. **Mode 1: Time Session Mode**
* เช็กช่วงเวลาเทรด `Session 1-3` ถ้าอยู่นอกเวลา ห้ามเปิดออร์เดอร์ใหม่เด็ดขาด
* เช็กทิศทาง `Trade Direction` (Buy Only, Sell Only, Both, Hedge) แล้วออกออร์เดอร์ตามจังหวะ


2. **Mode 2: Distance Lock Price Mode**
* ยึดราคาปัจจุบันเป็น `Lock Price` (บันทึกค่าไว้ใน Static/Global Variable)
* **Rule Buy:** ถ้าราคาถอยต่ำกว่า `Lock Price` >= `InpLockDistancePoints` ➔ เปิด **BUY**
* **Rule Sell:** ถ้าราคาพุ่งสูงกว่า `Lock Price` >= `InpLockDistancePoints` ➔ เปิด **SELL**
* **Re-Lock Loop Logic:** เมื่อเกิด Hard CutLoss ให้บันทึกราคาที่โดนปิดนั้นเป็น `Lock Price` ใหม่ทันที แล้วเริ่มลูปจับระยะทางต่อทันที!


3. **Mode 3: Manual Free Trade Mode**
* EA หยุดยิงออร์เดอร์เปิดรอบอัตโนมัติ รอรับคำสั่งกดปุ่ม `BUY`, `SELL`, `HEDGE OPEN` บน Panel หน้าจอเท่านั้น
* ระบบคุมความเสี่ยง (BE, CutLoss, RR Target) ยังคงทำงานคุมออร์เดอร์ให้อัตโนมัติ



### B. Manual Close Tracking Logic (OnTradeTransaction)

> **CRITICAL RULE:** หากผู้ใช้ทำการปิดออร์เดอร์บางไม้ด้วยตัวเองผ่าน Terminal / Toolbox หน้าจอ (ไม่ได้กดปุ่ม Close All บน Panel) ระบบ EA ต้องสามารถรับรู้และลงบัญชีได้ถูกต้องแบบ Real-time!

1. ใช้ Event Handler `OnTradeTransaction()` ดักจับประเภท `TRADE_TRANSACTION_DEAL_ADD`
2. ตรวจสอบว่า Deal ที่เกิดขึ้นเป็น Transaction การปิดออร์เดอร์ (`DEAL_ENTRY_OUT` หรือ `DEAL_ENTRY_INOUT`) และมี `MagicNumber` ตรงกับ EA ตัวนี้หรือไม่
3. **Realized PnL Calculation:** ดึงค่ากำไร/ขาดทุนสุทธิ (`Deal Profit + Commission + Swap`) ของไม้นั้นไปหักลบและอัปเดตลงในค่า **`EQ` (Virtual Equity)** ทันที
4. **Floating Recalculation:** คำนวณค่า **`OR` (Order Floating PnL)** เฉพาะไม้ที่ยังเปิดค้างอยู่ใหม่ทันที เพื่อให้ค่า **`TT` (Total Net = EQ + OR)** สะท้อนผลลัพธ์สุทธิที่ถูกต้อง 100% เสมอ!

### C. Break-Even (BE) & RR Target Engine

* **Fixed BE:** เมื่อราคาบวกถึง `InpBETriggerPoints` วาง SL ล็อกกำไร ณ `% Lock` ค้างไว้นิ่งๆ
* **Dynamic Trailing BE:** เมื่อราคาบวกถึง `InpBETriggerPoints` วาง SL ล็อกกำไร ณ `% Lock` แล้วหากราคาขยับบวกเพิ่มขึ้นทุกๆ 10 Points ให้เลื่อน SL ขึ้นตามไปในอัตราส่วน 20% เสมอ (ห้ามเลื่อนถอยหลัง)
* **RR Target:** คำนวณกำไรสะสมลอยใน Basket ถ้ารวมได้กำไรถึงเป้า `Target_Points` ให้สั่ง Close Basket ทั้งหมดทันที

---

## 🎨 4. UI Style & Color Palette Spec (Opaque & High-Contrast Panel)

> **Design Goal:** หน้าต่าง Panel ต้องมีความทึบแสง 100% (Non-Transparent) เพื่อแยกชั้น Visual ออกจากแท่งเทียนบนกราฟเด็ดขาด อ่านง่าย สบายตา สลับสีปุ่มแสดงสถานะชัดเจน
> 
> 

### A. Container & Layout Properties

* **Background Frame:** `#181825` (Dark Slate Gray - ทึบแสง 100% ห้ามโปร่งแสงเด็ดขาด)
* **Border Line:** `1px solid #45475A` (เส้นขอบกล่องสีเทาสว่าง เน้นขอบเขต Panel บนหน้าจอ)
* **Corner Radius:** 6px (มุมกล่องมนเล็กน้อย)
* **Font Family:** `Segoe UI` หรือ `Arial` (Font มาตรฐานอ่านง่าย)

### B. Color Palette Mapping

| Element Type | Color Name | Hex Code | Purpose & Application |
| --- | --- | --- | --- |
| **Main Header & Title** | Gold / Yellow | `#FFD700` / `#F9E2AF` | ใช้กับเวอร์ชั่น, Symbol และ Magic Number

 |
| **Active Status / ON** | Neon Green | `#A6E3A1` / `#00FF7F` | ใช้กับสถานะเปิดใช้งาน, ไฟ S1-S3 และปุ่ม Toggle ที่กด ON

 |
| **Inactive Status / OFF** | Slate Gray | `#585B70` | ใช้กับปุ่ม Toggle หรือฟังก์ชั่นที่กด OFF

 |
| **Warning / Alert / Loss** | Crimson Red / Orange | `#F38BA8` / `#FF4500` | ใช้กับสถานะแจ้งเตือน, CutLoss และตัวเลขติดลบ

 |
| **General Text & Labels** | Off-White / Soft Blue | `#CDD6F4` / `#89B4FA` | ใช้กับข้อความอธิบายทั่วไป และค่าตัวเลขปกติ

 |

### C. Action Button Color Styles

* **`[ BUY ]` Button:** Background `#1E66F5` (Royal Blue) | Text `#FFFFFF` (Bold)


* **`[ SELL ]` Button:** Background `#E64553` (Brick Red) | Text `#FFFFFF` (Bold)


* **`[ HEDGE OPEN ]` Button:** Background `#8839EF` (Electric Purple) | Text `#FFFFFF` (Bold)


* **`[ CLOSE ALL ORDER ]` Button:** Background `#E5C890` (Dark Amber) | Text `#11111B` (Bold)


* **`[ LOCK PRICE ]` & `[ REFILL ]` Buttons:** Background `#313244` | Text `#CDD6F4`


---

## 🖥️ 5. Dashboard Panel Wireframe & Text Specs (Ultra-Minimal Layout)

```text
┌─────────────────────────────────────────────────────────┐
│ 🔲 Background: #181825 (Opaque) | Border: #45475A      │
├─────────────────────────────────────────────────────────┤
│ [HEADER ZONE]                                           │
│ 🟡 v2.1 | XAUUSD | #998874                              │
│ 🏷️ Comment: HedgeDrift_RR1:2                            │
├─────────────────────────────────────────────────────────┤
│ [STATUS & METRICS ZONE]                                 │
│  Mode    : 🔵 LOCK_PRICE                                │
│  Dir     : 🟢 BOTH (BUY & SELL)                         │
│  Lock P. : 2650.50 (Dist: +420 pts)                     │
│  Sess    : S1:🟢 ON | S2:🔴 OFF | S3:🟡 WAIT             │
│ ─────────────────────────────────────────────────────── │
│  Cap : $50.00 (B) | Ref : $20.00 (2 T) | Lot : 0.01     │
│  EQ  : $26.58     | OR  : -$10.35      | TT  : $16.23   │
├─────────────────────────────────────────────────────────┤
│ [TOGGLE SWITCHES ZONE] (กดสลับสี เขียว=ON/เทา=OFF)     │
│  [Auto Refill: ON]   [Hard CutLoss: ON]                 │
│  [Auto BE: ON]       [RR Target: OFF]                   │
│  [Re-Lock Loop: ON]  [Session Filter: ON]               │
├─────────────────────────────────────────────────────────┤
│ [MANUAL ACTION BUTTONS]                                 │
│  [  BUY  ]       [  SELL  ]      [ HEDGE OPEN (B+S) ]   │
│  [ LOCK PRICE ]  [ REFILL $10 ]  [ CLOSE ALL ORDER ]    │
└─────────────────────────────────────────────────────────┘

```

### 📌 Metric Abbreviations Key:

* **`Cap` (Capital):** `$50.00 (B)` ➔ ทุนจำลองเริ่มต้น Base Capital
* **`Ref` (Refill):** `$20.00 (2 T)` ➔ ยอดเติมเงินรวม และจำนวนครั้งที่กดเติม (2 Times)
* **`EQ` (Equity):** ยอดเงินสะสมพอร์ตจำลอง
* **`OR` (Order Floating PnL):** กำไร/ขาดทุน ลอยอยู่ของ Order ปัจจุบัน
* **`TT` (Total Net):** ผลรวมหักลบสุทธิแบบ Real-time (`EQ + OR`)
* **`Lot` (Effective Lot):** ขนาด Lot ล่าสุดที่ใช้งาน

---

1. **อย่าลืมเช็ก `OnChartEvent()`:** บรรดาปุ่ม Toggle On/Off บน Panel ต้องเปลี่ยนค่าตัวแปรใน Global Scope ทันทีที่โดนกด และต้องเปลี่ยนสีปุ่มไฮไลต์ให้เห็นชัดเจน!
2. **จัดระเบียบ Code Structure:** แยกโมดูล `TradeEngine.mqh`, `PanelEngine.mqh`, และ `RiskEngine.mqh` ให้คลีนที่สุด!
3. **เรื่อง UI Panel:** กราฟรอบนี้ห้ามโปร่งแสงเด็ดขาด! ใช้สีทึบ `#181825` คุมโทนตาม UI Spec ด้านบนให้ลอยเด่นเด้งออกมาจาก Candlestick บนกราฟ!
4. **เรื่อง Event Handling (`OnChartEvent`):** ปุ่ม Toggle ทุกตัวต้องกดแล้วเปลี่ยนสีเขียว/เทาทันทีเรียลไทม์ และอัปเดตสวิตช์ Global Variable โดยไม่ต้องรีสตาร์ต EA!
5. **ห้ามแอบเอา `0 = Disabled` ซ่อนไว้เด็ดขาด:** เช็กสวิตช์ `bool` คุมทุกตัวให้เนียน!



---
