
### 🏛️ 1. Architecture Directory Structure (โครงสร้างไฟล์ 8 โมดูล)
ให้จัดโครงสร้างไฟล์ตามที่ไอ้จ้อยเสนอ โดยคุมให้อยู่ในโฟลเดอร์หลักเพียงชุดเดียวดังนี้:

`MQL5/Include/HedgeDrift/`
├── `Config.mqh`           // ค่าเริ่มต้น Validation & Inputs Mapping
├── `RuntimeState.mqh`     // สถานะ Cycle (IDLE/ACTIVE/WAIT) & Master Switches
├── `StrategyEngine.mqh`   // Logic การจับระยะ Trigger & Distance Lock Price
├── `TradeEngine.mqh`      // ส่งคำสั่ง OrderSend, Modify, CloseAll
├── `RiskEngine.mqh`       // คํานวณ CutLoss, Dynamic/Fixed BE และ Basket Target
├── `AccountingEngine.mqh` // คำนวณ Virtual Balance (EQ), Virtual Equity (TT), Refill
├── `Persistence.mqh`      // บันทึก/กู้คืน state.json เฉพาะส่วนจำแนกได้
└── `PanelEngine.mqh`      // UI Graphical Interface v2.1 & Click Handlers

---

### 🔐 2. Final Logic Lock & Specification (การล็อกสเปกและแก้จุดโหว่)

#### 2.1 Cycle Lifecycle & Anti-Trigger Loop (ป้องกันการยิงออร์เดอร์ซ้ำ)
* **State Machine:** `IDLE` ➔ `WAIT_TRIGGER` ➔ `OPENING` ➔ `ACTIVE` ➔ `CLOSING` ➔ `IDLE`
* **Rule:** ใน 1 Cycle อนุญาตให้มีสถานะ `ACTIVE` ได้เพียง **1 Basket (หรือ 1 ไม้ตาม Direction)** เท่านั้น!
* **Trigger Condition:** เมื่อราคาวิ่งข้ามระดับ `Lock Price` ตามระยะที่กำหนด ให้ทำการส่ง Order ทันที แล้วเปลี่ยนสถานะเป็น `ACTIVE` 
* **Prevent Re-trigger:** ถ้าราคายังคงวิ่งเลยระดับราคาไปเรื่อยๆ ขณะอยู่ในสถานะ `ACTIVE` **ห้ามส่งออร์เดอร์ซ้ำเด็ดขาด!**
* **Reset Cycle:** จะกลับมาจับระยะเพื่อ Trigger ใหม่ได้ก็ต่อเมื่อ Basket ปิดลงทั้งหมด (ด้วย RR Target, CutLoss, BE หรือ Manual Close) แล้วสถานะสลับกลับมาเป็น `IDLE` พร้อมเริ่ม Auto New Cycle เท่านั้น!

#### 2.2 Virtual Accounting Formulas & UI Mapping (สูตรทุนจำลอง)
เพื่อไม่ให้สับสนระหว่างชื่อตัวแปรภายในกับ Label บน Panel ให้ใช้ mapping ตามนี้:
* `VirtualBalance` (แสดงบน Panel ชื่อ **`EQ`**):
  $$\text{VirtualBalance} = \text{BaseCapital} + \text{RefillTotal} + \text{RealizedNetPnL}$$
* `FloatingNetPnL` (แสดงบน Panel ชื่อ **`OR`**): ผลรวมกำไร/ขาดทุน ลอยตัวของสถานะที่ยังเปิดอยู่
* `VirtualEquity` (แสดงบน Panel ชื่อ **`TT`**):
  $$\text{VirtualEquity} = \text{VirtualBalance} + \text{FloatingNetPnL}$$
* **Auto-Lot Calculation:** การคำนวณ Auto-Lot ให้ใช้ฐานจาก `VirtualBalance` (`EQ`) เสมอ!

#### 2.3 Basket RR Target Calculation (การคิดเป้าหมายกำไร Basket)
เปลี่ยนการคำนวณเป้าหมายจาก Points เป็น **เป้าเงิน ($) สุธิ** เพื่อรองรับกรณี Hedge หรือเปิดหลายไม้:
1. `InitialRiskMoney ($)` = $(\text{Distance CutLoss Points} \times \text{TickValue}) \times \text{Total Lot}$
2. `TargetMoney ($)` = $\text{InitialRiskMoney} \times \left(\frac{\text{InpRRTargetPercent}}{100}\right)$
3. **Execution:** เมื่อ `FloatingNetPnL` ($\text{OR}$) $\ge$ `TargetMoney ($)` ให้ `TradeEngine` ทำการ **Close All Basket ทันที!**

#### 2.4 UI Panel Specs & Input Normalization (ปรับชื่อปุ่ม/สวิตช์ให้ตรงกัน)
* **Version Label:** กำหนด Text บน Header และ เอกสารให้เป็น **`v2.1`** เหมือนกันทั้งหมด
* **`[Auto Lot: ON/OFF]`:** ปุ่มบน Panel ที่เคยใช้คำว่า `Auto Refill` ให้เปลี่ยนชื่อเป็น `[Auto Lot]` ให้ตรงกับ Input `InpEnableAutoLot`
* **`[Session Filter: ON/OFF]`:** ทำหน้าที่เป็น Master Switch ของเวลา หากตั้งเป็น `OFF` ระบบจะข้ามการเช็คเวลา Session 1–3 และเทลดิ์ได้ 24 ชม.
* **Comment String:** ปรับ Comment string ของ Order ให้แสดงผลตรงกับค่า Input RR จริง เช่น `HedgeDrift_RR1:1` ตามค่า `InpRRTargetPercent`

---

### 🎯 3. Phase Development Plan (ลำดับการขึ้นโค้ด)

* **Phase 1 (Core Foundations):** ล็อกโครงสร้าง 8 ไฟล์ย่อย, `Config.mqh`, `RuntimeState.mqh` และ `AccountingEngine.mqh` พร้อมระบบติดตาม Deal ID เพื่อป้องกันการนับทุนซ้ำ
* **Phase 2 (Manual & Trade Engine):** พัฒนา `TradeEngine.mqh` และ `PanelEngine.mqh` ให้กดเปิด/ปิด Manual, Close All, Refill ทุนจำลอง และอัปเดตหน้าจอได้ลื่นไหล
* **Phase 3 (Risk & Strategy Engine):** เพิ่ม `RiskEngine.mqh` (CutLoss, BE, Basket TargetMoney) และ `StrategyEngine.mqh` (Lock Mode, Re-Lock หลัง CutLoss, Session Filter)
* **Phase 4 (Persistence & Auto Cycle):** ทำระบบ `Persistence.mqh` เซฟ/กู้สถานะ `state.json` และทดสอบระบบ Auto New Cycle รวมทั้งชุด

---

